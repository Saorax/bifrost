#define HL_NAME(n) bhsound_##n
#include <hl.h>
#include <windows.h>
#include <shellapi.h>

HL_PRIM int HL_NAME(shell_open)(vbyte *path) {
    AllowSetForegroundWindow(ASFW_ANY);
    return (int)(INT_PTR)ShellExecuteW(NULL, L"open", (LPCWSTR)path, NULL, NULL, SW_SHOWNORMAL);
}

DEFINE_PRIM(_I32, shell_open, _BYTES);
