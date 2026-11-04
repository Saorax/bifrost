#define HL_NAME(n) bhsound_##n
#include <hl.h>
#include <windows.h>
#include <math.h>
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

HL_PRIM int HL_NAME(load)(vbyte *dll_path, vbyte *initializer, vbyte *finalizer) {
    FREInitializer init;
    FREContextInitializer context_initializer = NULL;
    wchar_t *path;
    if (extension_module != NULL) return 0;
    path = widen(dll_path);
    extension_module = LoadLibraryW(path);
    free(path);
    if (extension_module == NULL) return 1;
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
