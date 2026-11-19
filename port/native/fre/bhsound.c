#define HL_NAME(n) bhsound_##n
#include <hl.h>
#include <windows.h>
#include <shlobj.h>
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <string.h>
#include "bhfre.h"

static HMODULE extension_module = NULL;
static void *ext_data = NULL;
static FREContextFinalizer context_finalizer = NULL;
static FREFinalizer ext_finalizer = NULL;
static const FRENamedFunction *functions = NULL;
static uint32_t function_count = 0;
static int context_token = 1;

typedef struct { void **blocks; int count, capacity; } Arena;

static void *arena_alloc(Arena *a, size_t size) {
    void *p = calloc(1, size);
    if (a->count == a->capacity) {
        a->capacity = a->capacity ? a->capacity * 2 : 32;
        a->blocks = (void **)realloc(a->blocks, sizeof(void *) * a->capacity);
    }
    a->blocks[a->count++] = p;
    return p;
}

static void arena_free(Arena *a) {
    for (int i = 0; i < a->count; i++) free(a->blocks[i]);
    free(a->blocks);
}

static BhFreValue *decode(Arena *a, const unsigned char *buf, int len, int *pos) {
    BhFreValue *v;
    if (*pos >= len) return NULL;
    v = (BhFreValue *)arena_alloc(a, sizeof(BhFreValue));
    v->type = buf[(*pos)++];
    switch (v->type) {
    case BHFRE_UINT:
        memcpy(&v->u, buf + *pos, 4);
        *pos += 4;
        break;
    case BHFRE_DOUBLE:
        memcpy(&v->d, buf + *pos, 8);
        *pos += 8;
        break;
    case BHFRE_STRING: {
        uint8_t *s;
        memcpy(&v->length, buf + *pos, 4);
        *pos += 4;
        s = (uint8_t *)arena_alloc(a, v->length + 1);
        memcpy(s, buf + *pos, v->length);
        *pos += v->length;
        v->s = s;
        break;
    }
    case BHFRE_ARRAY:
        memcpy(&v->length, buf + *pos, 4);
        *pos += 4;
        v->items = (BhFreValue **)arena_alloc(a, sizeof(BhFreValue *) * (v->length + 1));
        for (uint32_t i = 0; i < v->length; i++) v->items[i] = decode(a, buf, len, pos);
        break;
    default:
        v->type = BHFRE_NULL;
        break;
    }
    return v;
}

static wchar_t *widen(vbyte *utf8) {
    int n = MultiByteToWideChar(CP_UTF8, 0, (const char *)utf8, -1, NULL, 0);
    wchar_t *w = (wchar_t *)malloc(sizeof(wchar_t) * (n + 1));
    MultiByteToWideChar(CP_UTF8, 0, (const char *)utf8, -1, w, n);
    return w;
}

#define MODS_TOKEN L"@bifrost-mods"
#define MODS_TOKEN_LEN 13

static wchar_t mods_dir[MAX_PATH * 2];
static CRITICAL_SECTION notes_lock;
static char notes[4096];
static int notes_ready = 0;
static int redirects = 0;
static int failures = 0;

static void note(const char *fmt, ...) {
    char line[1024];
    va_list args;
    size_t used;
    if (!notes_ready) return;
    va_start(args, fmt);
    _vsnprintf_s(line, sizeof(line), _TRUNCATE, fmt, args);
    va_end(args);
    EnterCriticalSection(&notes_lock);
    used = strlen(notes);
    if (used + strlen(line) + 2 < sizeof(notes)) {
        if (used > 0) notes[used++] = '\n';
        strcpy_s(notes + used, sizeof(notes) - used, line);
    }
    LeaveCriticalSection(&notes_lock);
}

static void narrow(const wchar_t *w, char *out, int size) {
    if (WideCharToMultiByte(CP_UTF8, 0, w, -1, out, size, NULL, NULL) == 0) out[0] = 0;
}

static wchar_t *map_path(LPCWSTR path) {
    size_t i;
    if (path == NULL || mods_dir[0] == 0) return NULL;
    for (i = 0; path[i]; i++) {
        const wchar_t *rest;
        wchar_t *out, *q;
        size_t n;
        if (i > 0 && path[i - 1] != L'\\' && path[i - 1] != L'/') continue;
        if (_wcsnicmp(path + i, MODS_TOKEN, MODS_TOKEN_LEN) != 0) continue;
        rest = path + i + MODS_TOKEN_LEN;
        if (*rest != 0 && *rest != L'\\' && *rest != L'/') continue;
        n = wcslen(mods_dir) + wcslen(rest) + 1;
        out = (wchar_t *)malloc(sizeof(wchar_t) * n);
        if (out == NULL) return NULL;
        wcscpy_s(out, n, mods_dir);
        wcscat_s(out, n, rest);
        for (q = out; *q; q++)
            if (*q == L'/') *q = L'\\';
        if (InterlockedIncrement((LONG *)&redirects) == 1) {
            char a[1024], b[1024];
            narrow(path, a, sizeof(a));
            narrow(out, b, sizeof(b));
            note("mods sound redirect: %s -> %s", a, b);
        }
        return out;
    }
    return NULL;
}

static void failed(const char *what, const wchar_t *path, DWORD error) {
    char a[1024];
    if (InterlockedIncrement((LONG *)&failures) > 5) return;
    narrow(path, a, sizeof(a));
    note("mods sound redirect: %s %s failed (error %lu)", what, a, (unsigned long)error);
}

static HANDLE WINAPI hook_CreateFileW(LPCWSTR name, DWORD access, DWORD share, LPSECURITY_ATTRIBUTES security,
                                     DWORD disposition, DWORD flags, HANDLE templ) {
    wchar_t *mapped = map_path(name);
    HANDLE h = CreateFileW(mapped ? mapped : name, access, share, security, disposition, flags, templ);
    if (mapped) {
        DWORD e = GetLastError();
        if (h == INVALID_HANDLE_VALUE) failed("open", mapped, e);
        free(mapped);
        SetLastError(e);
    }
    return h;
}

static DWORD WINAPI hook_GetFileAttributesW(LPCWSTR name) {
    wchar_t *mapped = map_path(name);
    DWORD result = GetFileAttributesW(mapped ? mapped : name);
    if (mapped) {
        DWORD e = GetLastError();
        if (result == INVALID_FILE_ATTRIBUTES) failed("attributes of", mapped, e);
        free(mapped);
        SetLastError(e);
    }
    return result;
}

static BOOL WINAPI hook_GetFileAttributesExW(LPCWSTR name, GET_FILEEX_INFO_LEVELS level, LPVOID info) {
    wchar_t *mapped = map_path(name);
    BOOL result = GetFileAttributesExW(mapped ? mapped : name, level, info);
    if (mapped) {
        DWORD e = GetLastError();
        if (!result) failed("attributes of", mapped, e);
        free(mapped);
        SetLastError(e);
    }
    return result;
}

static HANDLE WINAPI hook_FindFirstFileExW(LPCWSTR name, FINDEX_INFO_LEVELS level, LPVOID data, FINDEX_SEARCH_OPS search,
                                          LPVOID filter, DWORD flags) {
    wchar_t *mapped = map_path(name);
    HANDLE h = FindFirstFileExW(mapped ? mapped : name, level, data, search, filter, flags);
    if (mapped) {
        DWORD e = GetLastError();
        if (h == INVALID_HANDLE_VALUE) failed("listing", mapped, e);
        free(mapped);
        SetLastError(e);
    }
    return h;
}

static void *hook_for(const char *name) {
    if (strcmp(name, "CreateFileW") == 0) return (void *)hook_CreateFileW;
    if (strcmp(name, "GetFileAttributesW") == 0) return (void *)hook_GetFileAttributesW;
    if (strcmp(name, "GetFileAttributesExW") == 0) return (void *)hook_GetFileAttributesExW;
    if (strcmp(name, "FindFirstFileExW") == 0) return (void *)hook_FindFirstFileExW;
    return NULL;
}

static int patch_imports(HMODULE module) {
    BYTE *base = (BYTE *)module;
    IMAGE_DOS_HEADER *dos = (IMAGE_DOS_HEADER *)base;
    IMAGE_NT_HEADERS *nt;
    IMAGE_DATA_DIRECTORY dir;
    IMAGE_IMPORT_DESCRIPTOR *d;
    int patched = 0;
    if (dos->e_magic != IMAGE_DOS_SIGNATURE) return -1;
    nt = (IMAGE_NT_HEADERS *)(base + dos->e_lfanew);
    if (nt->Signature != IMAGE_NT_SIGNATURE) return -1;
    dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    if (dir.VirtualAddress == 0) return 0;
    for (d = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); d->Name != 0; d++) {
        const char *dll = (const char *)(base + d->Name);
        IMAGE_THUNK_DATA *names, *slots;
        if (_stricmp(dll, "KERNEL32.dll") != 0 && _strnicmp(dll, "api-ms-win-core-file-", 21) != 0) continue;
        names = (IMAGE_THUNK_DATA *)(base + (d->OriginalFirstThunk ? d->OriginalFirstThunk : d->FirstThunk));
        slots = (IMAGE_THUNK_DATA *)(base + d->FirstThunk);
        for (; names->u1.AddressOfData != 0; names++, slots++) {
            IMAGE_IMPORT_BY_NAME *by;
            void *hook;
            DWORD old;
            if (IMAGE_SNAP_BY_ORDINAL(names->u1.Ordinal)) continue;
            by = (IMAGE_IMPORT_BY_NAME *)(base + names->u1.AddressOfData);
            hook = hook_for((const char *)by->Name);
            if (hook == NULL) continue;
            if (!VirtualProtect(&slots->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) {
                note("mods sound redirect: can't patch %s (error %lu)", (const char *)by->Name, (unsigned long)GetLastError());
                continue;
            }
            slots->u1.Function = (ULONG_PTR)hook;
            VirtualProtect(&slots->u1.Function, sizeof(void *), old, &old);
            patched++;
        }
    }
    return patched;
}

static void redirect_init(HMODULE module) {
    char where[MAX_PATH * 2];
    int patched;
    DWORD n;
    InitializeCriticalSection(&notes_lock);
    notes_ready = 1;
    n = GetEnvironmentVariableW(L"BH_PORT_MODS_DIR", mods_dir, MAX_PATH * 2);
    if (n == 0 || n >= MAX_PATH * 2) {
        wchar_t docs[MAX_PATH];
        mods_dir[0] = 0;
        if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_PERSONAL, NULL, SHGFP_TYPE_CURRENT, docs)))
            swprintf_s(mods_dir, MAX_PATH * 2, L"%s\\Bifrost\\Mods", docs);
    }
    n = (DWORD)wcslen(mods_dir);
    while (n > 0 && (mods_dir[n - 1] == L'\\' || mods_dir[n - 1] == L'/')) mods_dir[--n] = 0;
    patched = patch_imports(module);
    narrow(mods_dir, where, sizeof(where));
    note("mods sound redirect: @bifrost-mods -> %s (%d imports patched)", where[0] ? where : "(no mods folder)", patched);
}

HL_PRIM vbyte *HL_NAME(redirect_note)() {
    vbyte *out;
    if (!notes_ready) return hl_copy_bytes((vbyte *)"", 1);
    EnterCriticalSection(&notes_lock);
    out = hl_copy_bytes((vbyte *)notes, (int)strlen(notes) + 1);
    notes[0] = 0;
    LeaveCriticalSection(&notes_lock);
    return out;
}

HL_PRIM int HL_NAME(load)(vbyte *dll_path, vbyte *initializer, vbyte *finalizer) {
    FREInitializer init;
    FREContextInitializer context_initializer = NULL;
    wchar_t *path;
    if (extension_module != NULL) return 0;
    path = widen(dll_path);
    extension_module = LoadLibraryW(path);
    free(path);
    if (extension_module == NULL) return 1;
    redirect_init(extension_module);
    init = (FREInitializer)GetProcAddress(extension_module, (const char *)initializer);
    ext_finalizer = (FREFinalizer)GetProcAddress(extension_module, (const char *)finalizer);
    if (init == NULL) return 2;
    init(&ext_data, &context_initializer, &context_finalizer);
    if (context_initializer == NULL) return 2;
    context_initializer(ext_data, (const uint8_t *)"", &context_token, &function_count, &functions);
    return 0;
}

HL_PRIM int HL_NAME(function_count)() {
    return (int)function_count;
}

HL_PRIM double HL_NAME(call)(vbyte *name, vbyte *args, int length) {
    Arena arena = {0};
    BhFreValue *argv[64];
    uint32_t argc = 0;
    int pos = 0;
    double out = NAN;
    for (uint32_t i = 0; i < function_count; i++) {
        if (strcmp((const char *)functions[i].name, (const char *)name) != 0) continue;
        while (pos < length && argc < 64) argv[argc++] = decode(&arena, args, length, &pos);
        {
            BhFreValue *result = (BhFreValue *)functions[i].function(&context_token, functions[i].functionData, argc,
                                                                     (FREObject *)argv);
            if (result != NULL) {
                if (result->type == BHFRE_UINT) out = (double)result->u;
                else if (result->type == BHFRE_DOUBLE) out = result->d;
            }
        }
        break;
    }
    arena_free(&arena);
    return out;
}

HL_PRIM void HL_NAME(dispose)() {
    if (context_finalizer != NULL) context_finalizer(&context_token);
    context_finalizer = NULL;
    if (ext_finalizer != NULL) ext_finalizer(ext_data);
    ext_finalizer = NULL;
    function_count = 0;
}

DEFINE_PRIM(_I32, load, _BYTES _BYTES _BYTES);
DEFINE_PRIM(_I32, function_count, _NO_ARG);
DEFINE_PRIM(_F64, call, _BYTES _BYTES _I32);
DEFINE_PRIM(_VOID, dispose, _NO_ARG);
DEFINE_PRIM(_BYTES, redirect_note, _NO_ARG);
