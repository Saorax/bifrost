#define HL_NAME(n) bhsound_##n
#include <hl.h>
#include <windows.h>
#include <psapi.h>

static double filetime_ms(FILETIME t) {
    ULARGE_INTEGER v;
    v.LowPart = t.dwLowDateTime;
    v.HighPart = t.dwHighDateTime;
    return (double)v.QuadPart / 10000.0;
}

HL_PRIM double HL_NAME(thread_user_ms)(void) {
    FILETIME c, e, k, u;
    if (!GetThreadTimes(GetCurrentThread(), &c, &e, &k, &u)) return -1;
    return filetime_ms(u);
}

HL_PRIM double HL_NAME(thread_kernel_ms)(void) {
    FILETIME c, e, k, u;
    if (!GetThreadTimes(GetCurrentThread(), &c, &e, &k, &u)) return -1;
    return filetime_ms(k);
}

HL_PRIM double HL_NAME(thread_mcycles)(void) {
    ULONG64 cycles = 0;
    if (!QueryThreadCycleTime(GetCurrentThread(), &cycles)) return -1;
    return (double)cycles / 1e6;
}

HL_PRIM int HL_NAME(page_faults)(void) {
    PROCESS_MEMORY_COUNTERS pmc;
    if (!K32GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) return -1;
    return (int)pmc.PageFaultCount;
}

DEFINE_PRIM(_F64, thread_user_ms, _NO_ARG);
DEFINE_PRIM(_F64, thread_kernel_ms, _NO_ARG);
DEFINE_PRIM(_F64, thread_mcycles, _NO_ARG);
DEFINE_PRIM(_I32, page_faults, _NO_ARG);

#include <dbghelp.h>

#define SAMPLE_MS 20
#define MAX_DEPTH 12
#define MAX_STACKS 16
#define OUT_SIZE 8192

static HANDLE stall_thread_handle = NULL;
static DWORD stall_main_id = 0;
static volatile LONG64 stall_frame_start = 0;
static LONG64 stall_freq = 1;
static int stall_threshold_ms = 60;
static CRITICAL_SECTION stall_lock;
static DWORD64 stall_stacks[MAX_STACKS][MAX_DEPTH];
static int stall_depths[MAX_STACKS];
static int stall_counts[MAX_STACKS];
static int stall_n = 0;
static int stall_dropped = 0;

static int unwind_context(CONTEXT ctx, DWORD64 *pcs, int depth) {
    int n = 0;
    while (n < depth && ctx.Rip != 0) {
        DWORD64 base = 0, frame = 0;
        PVOID handler = NULL;
        PRUNTIME_FUNCTION fn;
        pcs[n++] = ctx.Rip;
        fn = RtlLookupFunctionEntry(ctx.Rip, &base, NULL);
        if (fn == NULL) {
            if (n > 1) break;
            ctx.Rip = *(DWORD64 *)ctx.Rsp;
            ctx.Rsp += 8;
            continue;
        }
        RtlVirtualUnwind(UNW_FLAG_NHANDLER, base, ctx.Rip, fn, &ctx, &handler, &frame, NULL);
    }
    return n;
}

static int stall_unwind(HANDLE thread, DWORD64 *pcs) {
    CONTEXT ctx;
    ZeroMemory(&ctx, sizeof(ctx));
    ctx.ContextFlags = CONTEXT_FULL;
    if (!GetThreadContext(thread, &ctx)) return 0;
    return unwind_context(ctx, pcs, MAX_DEPTH);
}

static char crash_path[MAX_PATH] = "";
static volatile LONG crash_count = 0;

static void crash_write(const char *text) {
    DWORD wrote;
    HANDLE f = CreateFileA(crash_path, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS,
                           FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    WriteFile(f, text, (DWORD)strlen(text), &wrote, NULL);
    FlushFileBuffers(f);
    CloseHandle(f);
}

static const char *module_of(DWORD64 pc, char *path, HMODULE *module) {
    const char *base;
    *module = NULL;
    path[0] = '?';
    path[1] = 0;
    if (!GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
                            (LPCSTR)pc, module) || *module == NULL)
        return NULL;
    GetModuleFileNameA(*module, path, MAX_PATH);
    base = strrchr(path, '\\');
    return base ? base + 1 : path;
}

static void crash_frame(DWORD64 pc, char *out, size_t size) {
    HMODULE module;
    char path[MAX_PATH];
    const char *base = module_of(pc, path, &module);
    if (base == NULL)
        _snprintf_s(out, size, _TRUNCATE, "jit@%llx", (unsigned long long)pc);
    else
        _snprintf_s(out, size, _TRUNCATE, "%s+0x%llx", base, (unsigned long long)(pc - (DWORD64)module));
}

static LONG WINAPI crash_handler(PEXCEPTION_POINTERS info) {
    DWORD code = info->ExceptionRecord->ExceptionCode;
    DWORD64 pcs[32];
    char line[4096], frame[300];
    size_t len;
    int n, i;
    HMODULE module = NULL;
    if (code != 0xC0000005 && code != 0xC0000374 && code != 0xC0000409 && code != 0xC000001D && code != 0xC00000FD
        && code != 0xC0000096 && code != 0xC0000006)
        return EXCEPTION_CONTINUE_SEARCH;
    if (code == 0xC0000005 && !GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
            GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT, (LPCSTR)info->ContextRecord->Rip, &module))
        return EXCEPTION_CONTINUE_SEARCH;
    if (InterlockedIncrement(&crash_count) > 16) return EXCEPTION_CONTINUE_SEARCH;
    len = _snprintf_s(line, sizeof(line), _TRUNCATE, "exception 0x%08lx thread %lu address %llx%s:",
                      (unsigned long)code, (unsigned long)GetCurrentThreadId(),
                      (unsigned long long)info->ExceptionRecord->ExceptionAddress,
                      GetCurrentThreadId() == stall_main_id ? " (main thread)" : "");
    if (code == 0xC0000005 && info->ExceptionRecord->NumberParameters >= 2)
        len += _snprintf_s(line + len, sizeof(line) - len, _TRUNCATE, " %s %llx;",
                           info->ExceptionRecord->ExceptionInformation[0] ? "writing" : "reading",
                           (unsigned long long)info->ExceptionRecord->ExceptionInformation[1]);
    n = unwind_context(*info->ContextRecord, pcs, 32);
    for (i = 0; i < n && len < sizeof(line) - 320; i++) {
        crash_frame(pcs[i], frame, sizeof(frame));
        len += _snprintf_s(line + len, sizeof(line) - len, _TRUNCATE, "%s%s", i ? " < " : " ", frame);
    }
    _snprintf_s(line + len, sizeof(line) - len, _TRUNCATE, "\r\n");
    crash_write(line);
    return EXCEPTION_CONTINUE_SEARCH;
}

static void stall_record(DWORD64 *pcs, int n) {
    int i;
    EnterCriticalSection(&stall_lock);
    for (i = 0; i < stall_n; i++) {
        if (stall_depths[i] == n && memcmp(stall_stacks[i], pcs, n * sizeof(DWORD64)) == 0) {
            stall_counts[i]++;
            LeaveCriticalSection(&stall_lock);
            return;
        }
    }
    if (stall_n < MAX_STACKS) {
        memcpy(stall_stacks[stall_n], pcs, n * sizeof(DWORD64));
        stall_depths[stall_n] = n;
        stall_counts[stall_n] = 1;
        stall_n++;
    } else {
        stall_dropped++;
    }
    LeaveCriticalSection(&stall_lock);
}

static DWORD WINAPI stall_watch(LPVOID main_thread) {
    LONG64 sampled_frame = 0, next_at = 0;
    for (;;) {
        LARGE_INTEGER now;
        LONG64 start;
        DWORD64 pcs[MAX_DEPTH];
        int n;
        Sleep(5);
        start = stall_frame_start;
        if (start == 0) continue;
        QueryPerformanceCounter(&now);
        if ((now.QuadPart - start) * 1000 / stall_freq < stall_threshold_ms) continue;
        if (start != sampled_frame) {
            sampled_frame = start;
            next_at = 0;
        }
        if (now.QuadPart < next_at) continue;
        next_at = now.QuadPart + stall_freq * SAMPLE_MS / 1000;
        if (SuspendThread((HANDLE)main_thread) == (DWORD)-1) continue;
        n = stall_unwind((HANDLE)main_thread, pcs);
        ResumeThread((HANDLE)main_thread);
        if (n > 0 && stall_frame_start == start) stall_record(pcs, n);
    }
    return 0;
}

HL_PRIM int HL_NAME(stall_start)(int threshold_ms) {
    HANDLE main_thread;
    LARGE_INTEGER freq;
    if (stall_thread_handle != NULL) return 1;
    if (!DuplicateHandle(GetCurrentProcess(), GetCurrentThread(), GetCurrentProcess(), &main_thread,
                         THREAD_SUSPEND_RESUME | THREAD_GET_CONTEXT | THREAD_QUERY_INFORMATION, FALSE, 0)) return 0;
    QueryPerformanceFrequency(&freq);
    stall_freq = freq.QuadPart;
    stall_threshold_ms = threshold_ms;
    InitializeCriticalSection(&stall_lock);
    stall_main_id = GetCurrentThreadId();
    if (!GetEnvironmentVariableA("BH_PORT_CRASH_LOG", crash_path, MAX_PATH))
        strcpy_s(crash_path, MAX_PATH, "crash-stack.txt");
    AddVectoredExceptionHandler(1, crash_handler);
    stall_thread_handle = CreateThread(NULL, 0, stall_watch, main_thread, 0, NULL);
    return stall_thread_handle != NULL;
}

HL_PRIM void HL_NAME(stall_frame)(int begin) {
    LARGE_INTEGER now;
    if (!begin) {
        stall_frame_start = 0;
        return;
    }
    if (stall_thread_handle != NULL) {
        EnterCriticalSection(&stall_lock);
        stall_n = 0;
        stall_dropped = 0;
        LeaveCriticalSection(&stall_lock);
    }
    QueryPerformanceCounter(&now);
    stall_frame_start = now.QuadPart;
}

static void stall_name(HANDLE process, DWORD64 pc, char *out, size_t size) {
    char buffer[sizeof(SYMBOL_INFO) + 256];
    SYMBOL_INFO *symbol = (SYMBOL_INFO *)buffer;
    DWORD64 displacement = 0;
    HMODULE module;
    char path[MAX_PATH];
    const char *base = module_of(pc, path, &module);
    if (base == NULL) {
        _snprintf_s(out, size, _TRUNCATE, "jit@%llx", (unsigned long long)pc);
        return;
    }
    ZeroMemory(buffer, sizeof(buffer));
    symbol->SizeOfStruct = sizeof(SYMBOL_INFO);
    symbol->MaxNameLen = 255;
    if (SymFromAddr(process, pc, &displacement, symbol))
        _snprintf_s(out, size, _TRUNCATE, "%s!%s+0x%llx", base, symbol->Name, (unsigned long long)displacement);
    else
        _snprintf_s(out, size, _TRUNCATE, "%s+0x%llx", base, (unsigned long long)(pc - (DWORD64)module));
}

HL_PRIM vbyte *HL_NAME(stall_take)(void) {
    static int sym_ready = 0;
    static char out[OUT_SIZE];
    static DWORD64 stacks[MAX_STACKS][MAX_DEPTH];
    static int depths[MAX_STACKS], counts[MAX_STACKS];
    HANDLE process = GetCurrentProcess();
    int n, dropped, i, j;
    size_t len = 0;
    out[0] = 0;
    if (stall_thread_handle == NULL) return hl_copy_bytes((vbyte *)out, 1);
    EnterCriticalSection(&stall_lock);
    n = stall_n;
    dropped = stall_dropped;
    memcpy(stacks, stall_stacks, sizeof(stacks));
    memcpy(depths, stall_depths, sizeof(depths));
    memcpy(counts, stall_counts, sizeof(counts));
    stall_n = 0;
    stall_dropped = 0;
    LeaveCriticalSection(&stall_lock);
    if (n > 0 && !sym_ready) {
        SymSetOptions(SYMOPT_UNDNAME | SYMOPT_DEFERRED_LOADS);
        SymInitialize(process, NULL, TRUE);
        sym_ready = 1;
    }
    for (i = 0; i < n && len < OUT_SIZE - 400; i++) {
        len += _snprintf_s(out + len, OUT_SIZE - len, _TRUNCATE, "%s%dx ", i ? " | " : "", counts[i]);
        for (j = 0; j < depths[i] && len < OUT_SIZE - 400; j++) {
            char name[300];
            stall_name(process, stacks[i][j], name, sizeof(name));
            len += _snprintf_s(out + len, OUT_SIZE - len, _TRUNCATE, "%s%s", j ? " < " : "", name);
        }
    }
    if (dropped > 0 && len < OUT_SIZE - 64)
        len += _snprintf_s(out + len, OUT_SIZE - len, _TRUNCATE, " | %d more samples", dropped);
    return hl_copy_bytes((vbyte *)out, (int)strlen(out) + 1);
}

DEFINE_PRIM(_I32, stall_start, _I32);
DEFINE_PRIM(_VOID, stall_frame, _I32);
DEFINE_PRIM(_BYTES, stall_take, _NO_ARG);
