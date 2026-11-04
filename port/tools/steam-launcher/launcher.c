#include <windows.h>
#include <shellapi.h>
#include <stdlib.h>
#include <string.h>

int bifrost_discord_bridge(int argc, wchar_t **argv);

__declspec(dllexport) DWORD NvOptimusEnablement = 1;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;

static wchar_t dir[MAX_PATH], engine[MAX_PATH], bin[MAX_PATH], path[MAX_PATH], other[MAX_PATH], game[MAX_PATH];
static wchar_t marker[MAX_PATH], backup[MAX_PATH];

static DWORD run(const wchar_t *exe, wchar_t *cmd, const wchar_t *cwd, int tied)
{
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    DWORD code = 1;
    HANDLE job = NULL;
    ZeroMemory(&si, sizeof si);
    si.cb = sizeof si;
    if (tied) {
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits;
        ZeroMemory(&limits, sizeof limits);
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        job = CreateJobObjectW(NULL, NULL);
        if (job) SetInformationJobObject(job, JobObjectExtendedLimitInformation, &limits, sizeof limits);
    }
    if (!CreateProcessW(exe, cmd, NULL, NULL, FALSE, job ? CREATE_SUSPENDED : 0, NULL, cwd, &si, &pi))
        return 1;
    if (job) {
        AssignProcessToJobObject(job, pi.hProcess);
        ResumeThread(pi.hThread);
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return code;
}

static void log_line(const wchar_t *name, const wchar_t *line)
{
    char utf8[2048];
    HANDLE f;
    DWORD n;
    int len;
    wsprintfW(other, L"%s\\logs\\%s", engine, name);
    f = CreateFileW(other, FILE_APPEND_DATA, FILE_SHARE_READ, NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    len = WideCharToMultiByte(CP_UTF8, 0, line, -1, utf8, sizeof utf8, NULL, NULL);
    if (len > 1) WriteFile(f, utf8, (DWORD)(len - 1), &n, NULL);
    CloseHandle(f);
}

static void record(const wchar_t *renderer, const wchar_t *note)
{
    wchar_t line[512], app[64];
    SYSTEMTIME t;
    if (!GetEnvironmentVariableW(L"SteamAppId", app, 64)) lstrcpyW(app, L"-");
    GetLocalTime(&t);
    wsprintfW(line, L"%04d-%02d-%02d %02d:%02d:%02d steam=%s\r\n", t.wYear, t.wMonth, t.wDay, t.wHour, t.wMinute,
              t.wSecond, app);
    log_line(L"starts.txt", line);
    wsprintfW(line, L"%04d-%02d-%02d %02d:%02d:%02d renderer %s%s%s\r\n", t.wYear, t.wMonth, t.wDay, t.wHour,
              t.wMinute, t.wSecond, renderer, note[0] ? L": " : L"", note);
    log_line(L"launcher.txt", line);
}

static void launcher_log(const wchar_t *line)
{
    log_line(L"launcher.txt", line);
}

static int exists(const wchar_t *file)
{
    return GetFileAttributesW(file) != INVALID_FILE_ATTRIBUTES;
}

static int read_json_string(const wchar_t *file, const char *key, char *out, int size)
{
    char text[16384], *p, *q;
    DWORD n = 0;
    HANDLE f = CreateFileW(file, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return 0;
    ReadFile(f, text, sizeof text - 1, &n, NULL);
    CloseHandle(f);
    text[n] = 0;
    p = strstr(text, key);
    if (!p) return 0;
    p = strchr(p + lstrlenA(key), ':');
    if (!p) return 0;
    p = strchr(p, '"');
    if (!p) return 0;
    q = strchr(++p, '"');
    if (!q || q - p >= size) return 0;
    memcpy(out, p, q - p);
    out[q - p] = 0;
    return 1;
}

static int read_json_path(const wchar_t *file, const char *key, wchar_t *out, int size)
{
    char raw[MAX_PATH * 6], hex[5];
    const char *p, *run;
    int n = 0;
    if (!read_json_string(file, key, raw, sizeof raw) || raw[0] == 0) return 0;
    p = raw;
    while (*p && n < size - 1) {
        if (*p == '\\') {
            if (p[1] == 'u' && p[2] && p[3] && p[4] && p[5]) {
                memcpy(hex, p + 2, 4);
                hex[4] = 0;
                out[n++] = (wchar_t)strtoul(hex, NULL, 16);
                p += 6;
            } else if (p[1]) {
                out[n++] = (wchar_t)(unsigned char)p[1];
                p += 2;
            } else {
                break;
            }
            continue;
        }
        for (run = p; *p && *p != '\\'; p++) {
        }
        n += MultiByteToWideChar(CP_UTF8, 0, run, (int)(p - run), out + n, size - 1 - n);
    }
    out[n] = 0;
    for (n = 0; out[n]; n++) {
        if (out[n] == L'/') out[n] = L'\\';
    }
    return out[0] != 0;
}

static int engine_from_tail(void)
{
    wchar_t self[MAX_PATH];
    char tail[8], text[MAX_PATH * 4];
    LARGE_INTEGER size, at;
    DWORD n = 0, len;
    HANDLE f;
    int ok = 0, i;
    if (!GetModuleFileNameW(NULL, self, MAX_PATH)) return 0;
    f = CreateFileW(self, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return 0;
    if (GetFileSizeEx(f, &size) && size.QuadPart > 8) {
        at.QuadPart = size.QuadPart - 8;
        if (SetFilePointerEx(f, at, NULL, FILE_BEGIN) && ReadFile(f, tail, 8, &n, NULL) && n == 8 &&
            memcmp(tail + 4, "BFEN", 4) == 0) {
            len = (DWORD)(unsigned char)tail[0] | (DWORD)(unsigned char)tail[1] << 8 |
                  (DWORD)(unsigned char)tail[2] << 16 | (DWORD)(unsigned char)tail[3] << 24;
            at.QuadPart = size.QuadPart - 8 - len;
            if (len > 0 && len < sizeof text && at.QuadPart > 0 && SetFilePointerEx(f, at, NULL, FILE_BEGIN) &&
                ReadFile(f, text, len, &n, NULL) && n == len) {
                i = MultiByteToWideChar(CP_UTF8, 0, text, (int)len, engine, MAX_PATH - 1);
                engine[i] = 0;
                for (i = 0; engine[i]; i++) {
                    if (engine[i] == L'/') engine[i] = L'\\';
                }
                ok = engine[0] != 0;
            }
        }
    }
    CloseHandle(f);
    return ok;
}

static void find_engine(void)
{
    if (engine_from_tail()) {
        wsprintfW(marker, L"%s\\bifrost-engine.json", engine);
        wsprintfW(backup, L"%s\\Brawlhalla.exe.bifrost-original", engine);
        return;
    }
    wsprintfW(marker, L"%s\\bifrost-engine.json", dir);
    wsprintfW(backup, L"%s\\Brawlhalla.exe.bifrost-original", dir);
    if (!read_json_path(marker, "\"engine_dir\"", engine, MAX_PATH)) wsprintfW(engine, L"%s\\bifrost-engine", dir);
}

static void read_renderer(const wchar_t *storage, char *out, int size)
{
    lstrcpyA(out, "dx11");
    wsprintfW(other, L"%s\\engine.json", storage);
    read_json_string(other, "\"renderer\"", out, size);
}

static void save_renderer(const wchar_t *storage, const char *value)
{
    char text[4096], out[4200], *p, *q;
    DWORD n = 0;
    HANDLE f;
    wsprintfW(other, L"%s\\engine.json", storage);
    f = CreateFileW(other, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    ReadFile(f, text, sizeof text - 1, &n, NULL);
    CloseHandle(f);
    text[n] = 0;
    p = strstr(text, "\"renderer\"");
    if (!p || !(p = strchr(p + 10, ':')) || !(p = strchr(p, '"')) || !(q = strchr(p + 1, '"'))) return;
    memcpy(out, text, p + 1 - text);
    lstrcpyA(out + (p + 1 - text), value);
    lstrcatA(out, q);
    f = CreateFileW(other, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
    if (f == INVALID_HANDLE_VALUE) return;
    WriteFile(f, out, (DWORD)lstrlenA(out), &n, NULL);
    CloseHandle(f);
}

static int host(const wchar_t *renderer, int gargc, wchar_t **gargv)
{
    typedef int (*run_fn)(const wchar_t *, int, wchar_t **, void (*)(const wchar_t *));
    HMODULE vm;
    run_fn run_game;
    wchar_t note[512];
    SetDefaultDllDirectories(LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
    AddDllDirectory(bin);
    if (lstrcmpW(renderer, L"vulkan") == 0) {
        wsprintfW(other, L"%s\\vulkan", bin);
        AddDllDirectory(other);
        wsprintfW(other, L"%s\\logs", engine);
        SetEnvironmentVariableW(L"DXVK_LOG_PATH", other);
    }
    SetCurrentDirectoryW(bin);
    wsprintfW(other, L"%s\\bifrost-vm.dll", bin);
    vm = LoadLibraryExW(other, NULL, LOAD_LIBRARY_SEARCH_DEFAULT_DIRS | LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR);
    run_game = vm ? (run_fn)GetProcAddress(vm, "bifrost_run_game") : NULL;
    if (!run_game) {
        wsprintfW(note, L"could not load %s (error %lu)\r\n", other, GetLastError());
        log_line(L"launcher.txt", note);
        return 1;
    }
    return run_game(game, gargc, gargv, launcher_log);
}

static wchar_t forwarded[32768];
static wchar_t *fargv[256];
static int fargc = 0;

static int filter_args(int argc, wchar_t **argv)
{
    int i, asked = -1;
    forwarded[0] = 0;
    for (i = 1; argv && i < argc && fargc < 255; i++) {
        if (lstrcmpiW(argv[i], L"-official") == 0) { asked = 1; continue; }
        if (lstrcmpiW(argv[i], L"-bifrost") == 0) { asked = 0; continue; }
        fargv[fargc++] = argv[i];
        if (lstrlenW(forwarded) + lstrlenW(argv[i]) + 4 >= 32768) continue;
        if (forwarded[0]) lstrcatW(forwarded, L" ");
        if (wcschr(argv[i], L' ')) {
            lstrcatW(forwarded, L"\"");
            lstrcatW(forwarded, argv[i]);
            lstrcatW(forwarded, L"\"");
        } else {
            lstrcatW(forwarded, argv[i]);
        }
    }
    return asked;
}

static int read_mode(void)
{
    char mode[16];
    return read_json_string(marker, "\"mode\"", mode, sizeof mode) && lstrcmpA(mode, "official") == 0;
}

static int game_file_name(const wchar_t *name)
{
    int n = lstrlenW(name);
    return n > 4 && (lstrcmpiW(name + n - 4, L".swf") == 0 || lstrcmpiW(name + n - 4, L".swz") == 0);
}

static int files_match(const wchar_t *list)
{
    HANDLE f, find;
    DWORD size, n = 0;
    char *text, *p, *end;
    int listed = 0, present = 0, ok = 1;
    WIN32_FIND_DATAW fd;
    f = CreateFileW(list, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, 0, NULL);
    if (f == INVALID_HANDLE_VALUE) return 0;
    size = GetFileSize(f, NULL);
    text = (char *)HeapAlloc(GetProcessHeap(), 0, size + 1);
    if (!text) { CloseHandle(f); return 0; }
    ReadFile(f, text, size, &n, NULL);
    CloseHandle(f);
    text[n] = 0;
    for (p = text; ok && *p; p = end) {
        unsigned __int64 want_size = 0, want_time = 0;
        wchar_t name[MAX_PATH], full[MAX_PATH * 2];
        WIN32_FILE_ATTRIBUTE_DATA a;
        char *line_end = strchr(p, '\n');
        end = line_end ? line_end + 1 : p + lstrlenA(p);
        if (line_end) *line_end = 0;
        if (!*p) continue;
        while (*p >= '0' && *p <= '9') want_size = want_size * 10 + (unsigned)(*p++ - '0');
        if (*p++ != ' ') { ok = 0; break; }
        while (*p >= '0' && *p <= '9') want_time = want_time * 10 + (unsigned)(*p++ - '0');
        if (*p++ != ' ') { ok = 0; break; }
        if (!MultiByteToWideChar(CP_UTF8, 0, p, -1, name, MAX_PATH)) { ok = 0; break; }
        listed++;
        wsprintfW(full, L"%s\\%s", dir, name);
        if (!GetFileAttributesExW(full, GetFileExInfoStandard, &a)
            || (((unsigned __int64)a.nFileSizeHigh << 32) | a.nFileSizeLow) != want_size
            || (((unsigned __int64)a.ftLastWriteTime.dwHighDateTime << 32) | a.ftLastWriteTime.dwLowDateTime) != want_time)
            ok = 0;
    }
    HeapFree(GetProcessHeap(), 0, text);
    if (!ok) return 0;
    wsprintfW(other, L"%s\\*", dir);
    find = FindFirstFileW(other, &fd);
    if (find != INVALID_HANDLE_VALUE) {
        do {
            if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) && game_file_name(fd.cFileName)) present++;
        } while (FindNextFileW(find, &fd));
        FindClose(find);
    }
    return present == listed;
}

static void make_dirs(const wchar_t *folder)
{
    wchar_t part[MAX_PATH * 2];
    int i, n = lstrlenW(folder);
    for (i = 0; i < n && i < MAX_PATH * 2 - 1; i++) {
        part[i] = folder[i];
        if ((folder[i] == L'\\' || folder[i] == L'/') && i > 2) {
            part[i] = 0;
            CreateDirectoryW(part, NULL);
            part[i] = folder[i];
        }
    }
    part[i] = 0;
    CreateDirectoryW(part, NULL);
}

static void link_file(const wchar_t *from, const wchar_t *to)
{
    WIN32_FILE_ATTRIBUTE_DATA a, b;
    if (GetFileAttributesExW(from, GetFileExInfoStandard, &a) && GetFileAttributesExW(to, GetFileExInfoStandard, &b) &&
        a.nFileSizeLow == b.nFileSizeLow && a.nFileSizeHigh == b.nFileSizeHigh &&
        CompareFileTime(&a.ftLastWriteTime, &b.ftLastWriteTime) == 0)
        return;
    DeleteFileW(to);
    if (!CreateHardLinkW(to, from, NULL)) CopyFileW(from, to, FALSE);
}

static void refresh_view(const wchar_t *view)
{
    wchar_t from[MAX_PATH * 2], to[MAX_PATH * 2], ext[MAX_PATH * 2], ane[MAX_PATH * 2];
    HANDLE find, inner;
    WIN32_FIND_DATAW fd, dll;
    make_dirs(view);
    lstrcpyW(from, backup);
    wsprintfW(to, L"%s\\Brawlhalla.exe", view);
    link_file(from, to);
    wsprintfW(from, L"%s\\BrawlhallaAir.swf.bifrost-original", dir);
    if (!exists(from)) wsprintfW(from, L"%s\\BrawlhallaAir.swf", dir);
    wsprintfW(to, L"%s\\BrawlhallaAir.swf", view);
    link_file(from, to);
    wsprintfW(other, L"%s\\*.swz", dir);
    find = FindFirstFileW(other, &fd);
    if (find != INVALID_HANDLE_VALUE) {
        do {
            wsprintfW(from, L"%s\\%s", dir, fd.cFileName);
            wsprintfW(to, L"%s\\%s", view, fd.cFileName);
            link_file(from, to);
        } while (FindNextFileW(find, &fd));
        FindClose(find);
    }
    wsprintfW(ext, L"%s\\META-INF\\AIR\\extensions\\*", dir);
    find = FindFirstFileW(ext, &fd);
    if (find == INVALID_HANDLE_VALUE) return;
    do {
        if (!(fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) || fd.cFileName[0] == L'.') continue;
        wsprintfW(ane, L"%s\\META-INF\\AIR\\extensions\\%s\\META-INF\\ANE\\Windows-x86-64\\*.dll", dir, fd.cFileName);
        inner = FindFirstFileW(ane, &dll);
        if (inner == INVALID_HANDLE_VALUE) continue;
        wsprintfW(to, L"%s\\META-INF\\AIR\\extensions\\%s\\META-INF\\ANE\\Windows-x86-64", view, fd.cFileName);
        make_dirs(to);
        do {
            wsprintfW(from, L"%s\\META-INF\\AIR\\extensions\\%s\\META-INF\\ANE\\Windows-x86-64\\%s", dir, fd.cFileName,
                      dll.cFileName);
            wsprintfW(to, L"%s\\META-INF\\AIR\\extensions\\%s\\META-INF\\ANE\\Windows-x86-64\\%s", view, fd.cFileName,
                      dll.cFileName);
            link_file(from, to);
        } while (FindNextFileW(inner, &dll));
        FindClose(inner);
    } while (FindNextFileW(find, &fd));
    FindClose(find);
}

static DWORD original_game(const wchar_t *why)
{
    static wchar_t cmd[32768];
    wchar_t line[512];
    wsprintfW(line, L"%s: starting Brawlhalla's own game\r\n", why);
    log_line(L"launcher.txt", line);
    lstrcpyW(path, backup);
    wsprintfW(cmd, L"\"%s\" %s", path, forwarded);
    return run(path, cmd, dir, 0);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR line, int show)
{
    static wchar_t cmd[32768];
    wchar_t *slash, renderer[16], note[256], storage[MAX_PATH], vulkan[MAX_PATH], games[MAX_PATH], view[MAX_PATH];
    char asked[16];
    int argc = 0, official, forced;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    (void)inst; (void)prev; (void)line; (void)show;
    if (argv && argc >= 3 && lstrcmpW(argv[1], L"--discord-bridge") == 0)
        return bifrost_discord_bridge(argc - 1, argv + 1);
    if (argv && argc >= 2 && lstrcmpW(argv[1], L"--hosted-vulkan") == 0) {
        if (!GetEnvironmentVariableW(L"BH_PORT_APP_DIR", dir, MAX_PATH)) return 1;
        find_engine();
        wsprintfW(bin, L"%s\\bin", engine);
        if (!GetEnvironmentVariableW(L"BIFROST_GAME_HL", game, MAX_PATH)) wsprintfW(game, L"%s\\game-dx11.hl", bin);
        return host(L"vulkan", argc - 2, argv + 2);
    }
    GetModuleFileNameW(NULL, dir, MAX_PATH);
    slash = wcsrchr(dir, L'\\');
    if (slash) *slash = 0;
    find_engine();
    wsprintfW(bin, L"%s\\bin", engine);
    forced = filter_args(argc, argv);
    wsprintfW(path, L"%s\\libhl.dll", bin);
    if (!exists(path)) return (int)original_game(L"no engine");
    wsprintfW(other, L"%s\\logs", engine);
    CreateDirectoryW(other, NULL);
    official = forced >= 0 ? forced : read_mode();
    wsprintfW(other, L"%s\\game-dx11.hl", bin);
    if (!official && !exists(other)) {
        wsprintfW(other, L"%s\\official\\game-dx11.hl", engine);
        if (exists(other)) official = 1;
    }
    if (official) {
        wsprintfW(games, L"%s\\official", engine);
        wsprintfW(other, L"%s\\game-dx11.hl", games);
        if (!exists(other)) return (int)original_game(L"official: not installed");
        wsprintfW(other, L"%s\\game-files.txt", games);
        if (!files_match(other)) return (int)original_game(L"official: Steam changed the game files since the install");
        wsprintfW(view, L"%s\\view", games);
        refresh_view(view);
        SetEnvironmentVariableW(L"BH_NC_VIEW", view);
        wsprintfW(storage, L"%s\\storage-official", engine);
        wsprintfW(other, L"%s\\logs\\boot-official.txt", engine);
    } else {
        lstrcpyW(games, bin);
        wsprintfW(other, L"%s\\game-files.txt", engine);
        if (exists(other) && !files_match(other)) {
            if (MessageBoxW(NULL, L"Steam updated Brawlhalla, and Bifrost needs an update for it: open the Bifrost app.\n\n"
                                  L"Start Brawlhalla's own game now?", L"Bifrost", MB_YESNO | MB_ICONINFORMATION) == IDYES)
                return (int)original_game(L"bifrost: Steam changed the game files since the install");
            return 0;
        }
        wsprintfW(storage, L"%s\\storage", engine);
        wsprintfW(other, L"%s\\logs\\boot.txt", engine);
    }
    SetEnvironmentVariableW(L"BH_PORT_APP_DIR", dir);
    SetEnvironmentVariableW(L"BH_PORT_MARKER", marker);
    SetEnvironmentVariableW(L"BH_PORT_STORAGE_DIR", storage);
    SetEnvironmentVariableW(L"BH_PORT_LOG", other);
    {
        wchar_t previous[MAX_PATH];
        wsprintfW(previous, L"%s\\logs\\%s", engine, official ? L"boot-official-previous.txt" : L"boot-previous.txt");
        MoveFileExW(other, previous, MOVEFILE_REPLACE_EXISTING);
    }

    read_renderer(storage, asked, sizeof asked);
    MultiByteToWideChar(CP_UTF8, 0, asked, -1, renderer, 16);
    note[0] = 0;
    wsprintfW(vulkan, L"%s\\vulkan", bin);
    if (lstrcmpW(renderer, L"dx12") == 0) wsprintfW(game, L"%s\\game-dx12.hl", games);
    else wsprintfW(game, L"%s\\game-dx11.hl", games);
    if (lstrcmpW(renderer, L"vulkan") == 0) {
        wsprintfW(other, L"%s\\d3d11.dll", vulkan);
        if (!exists(other)) {
            wsprintfW(note, L"%s is missing, starting dx11", other);
            lstrcpyW(renderer, L"dx11");
        }
    } else if (lstrcmpW(renderer, L"dx11") != 0 && lstrcmpW(renderer, L"dx12") != 0) {
        wsprintfW(note, L"unknown renderer, starting dx11");
        lstrcpyW(renderer, L"dx11");
    }
    if (!exists(game)) {
        wsprintfW(note, L"%s is missing, starting dx11", game);
        lstrcpyW(renderer, L"dx11");
        wsprintfW(game, L"%s\\game-dx11.hl", games);
    }
    if (lstrcmpW(renderer, L"vulkan") == 0) {
        wsprintfW(path, L"%s\\bifrost-vulkan.exe", vulkan);
        {
            wchar_t local[MAX_PATH], copy[MAX_PATH];
            WIN32_FILE_ATTRIBUTE_DATA a, b;
            if (GetEnvironmentVariableW(L"LOCALAPPDATA", local, MAX_PATH) && exists(path)) {
                wsprintfW(copy, L"%s\\Bifrost", local);
                CreateDirectoryW(copy, NULL);
                wsprintfW(copy, L"%s\\Bifrost\\engine", local);
                CreateDirectoryW(copy, NULL);
                wsprintfW(copy, L"%s\\Bifrost\\engine\\bifrost-vulkan.exe", local);
                if (!GetFileAttributesExW(copy, GetFileExInfoStandard, &b) ||
                    !GetFileAttributesExW(path, GetFileExInfoStandard, &a) ||
                    CompareFileTime(&a.ftLastWriteTime, &b.ftLastWriteTime) != 0 || a.nFileSizeLow != b.nFileSizeLow)
                    CopyFileW(path, copy, FALSE);
                if (exists(copy)) lstrcpyW(path, copy);
            }
        }
        if (exists(path)) {
            DWORD code;
            record(renderer, official ? L"official, in bifrost-vulkan.exe" : L"in bifrost-vulkan.exe");
            wsprintfW(other, L"%s\\game-dx11.hl", games);
            SetEnvironmentVariableW(L"BIFROST_GAME_HL", other);
            wsprintfW(cmd, L"\"%s\" --hosted-vulkan %s", path, forwarded);
            code = run(path, cmd, bin, 1);
            if (code >= 0xC0000000u) {
                wsprintfW(note, L"the Vulkan start crashed (exit code %08lx); dx11 saved as the renderer\r\n", code);
                log_line(L"launcher.txt", note);
                save_renderer(storage, "dx11");
            }
            return (int)code;
        }
    }
    record(renderer, official ? (note[0] ? note : L"official") : note);
    return host(renderer, fargc, fargv);
}

