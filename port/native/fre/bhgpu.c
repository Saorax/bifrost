#define HL_NAME(n) bhsound_##n
#define COBJMACROS
#include <hl.h>
#include <d3d11.h>
#include <dxgi1_3.h>

typedef struct {
    ID3D11Device *device;
    ID3D11DeviceContext *context;
} dx_driver_head;

HL_PRIM int HL_NAME(gpu_trim)(void *driver) {
    dx_driver_head *d = (dx_driver_head *)driver;
    IDXGIDevice3 *dxgi = NULL;
    if (d == NULL || d->device == NULL || d->context == NULL) return -1;
    if (FAILED(ID3D11Device_QueryInterface(d->device, &IID_IDXGIDevice3, (void **)&dxgi)) || dxgi == NULL) return 0;
    ID3D11DeviceContext_ClearState(d->context);
    ID3D11DeviceContext_Flush(d->context);
    IDXGIDevice3_Trim(dxgi);
    IDXGIDevice3_Release(dxgi);
    return 1;
}

DEFINE_PRIM(_I32, gpu_trim, _ABSTRACT(dx_driver));

HL_PRIM int HL_NAME(gpu_flush)(void *driver) {
    dx_driver_head *d = (dx_driver_head *)driver;
    if (d == NULL || d->context == NULL) return -1;
    ID3D11DeviceContext_Flush(d->context);
    return 1;
}

DEFINE_PRIM(_I32, gpu_flush, _ABSTRACT(dx_driver));

typedef HRESULT (WINAPI *create_device_swapchain_fn)(IDXGIAdapter *, D3D_DRIVER_TYPE, HMODULE, UINT,
    const D3D_FEATURE_LEVEL *, UINT, UINT, const DXGI_SWAP_CHAIN_DESC *, IDXGISwapChain **, ID3D11Device **,
    D3D_FEATURE_LEVEL *, ID3D11DeviceContext **);

static create_device_swapchain_fn real_create = NULL;
static IDXGIAdapter *chosen_adapter = NULL;
static WCHAR chosen_name[128] = L"";

static HRESULT WINAPI port_create_device_swapchain(IDXGIAdapter *adapter, D3D_DRIVER_TYPE type, HMODULE soft,
        UINT flags, const D3D_FEATURE_LEVEL *levels, UINT count, UINT sdk, const DXGI_SWAP_CHAIN_DESC *desc,
        IDXGISwapChain **swapchain, ID3D11Device **device, D3D_FEATURE_LEVEL *feature, ID3D11DeviceContext **context) {
    if (adapter == NULL && chosen_adapter != NULL && type == D3D_DRIVER_TYPE_HARDWARE)
        return real_create(chosen_adapter, D3D_DRIVER_TYPE_UNKNOWN, NULL, flags, levels, count, sdk, desc,
                           swapchain, device, feature, context);
    return real_create(adapter, type, soft, flags, levels, count, sdk, desc, swapchain, device, feature, context);
}

static IDXGIAdapter1 *find_adapter(const WCHAR *want) {
    IDXGIFactory1 *factory = NULL;
    IDXGIAdapter1 *adapter = NULL, *best = NULL;
    DXGI_ADAPTER_DESC1 d;
    SIZE_T bestMem = 0;
    UINT i;
    int index = -1, mode = 0;
    WCHAR lowWant[128];
    if (_wcsicmp(want, L"igpu") == 0) mode = 1;
    else if (_wcsicmp(want, L"dgpu") == 0) mode = 2;
    else if (want[0] >= L'0' && want[0] <= L'9' && want[1] == 0) { mode = 3; index = want[0] - L'0'; }
    else { mode = 4; wcsncpy_s(lowWant, 128, want, _TRUNCATE); _wcslwr_s(lowWant, 128); }
    if (FAILED(CreateDXGIFactory1(&IID_IDXGIFactory1, (void **)&factory)) || factory == NULL) return NULL;
    for (i = 0; IDXGIFactory1_EnumAdapters1(factory, i, &adapter) == S_OK; i++) {
        int take = 0;
        if (FAILED(IDXGIAdapter1_GetDesc1(adapter, &d)) || (d.Flags & DXGI_ADAPTER_FLAG_SOFTWARE)) {
            IDXGIAdapter1_Release(adapter);
            continue;
        }
        if (mode == 1) take = best == NULL || d.DedicatedVideoMemory < bestMem;
        else if (mode == 2) take = best == NULL || d.DedicatedVideoMemory > bestMem;
        else if (mode == 3) take = (int)i == index;
        else {
            WCHAR low[128];
            wcsncpy_s(low, 128, d.Description, _TRUNCATE);
            _wcslwr_s(low, 128);
            take = best == NULL && wcsstr(low, lowWant) != NULL;
        }
        if (take) {
            if (best != NULL) IDXGIAdapter1_Release(best);
            best = adapter;
            bestMem = d.DedicatedVideoMemory;
            wcsncpy_s(chosen_name, 128, d.Description, _TRUNCATE);
        } else IDXGIAdapter1_Release(adapter);
    }
    IDXGIFactory1_Release(factory);
    return best;
}

static int hook_import(HMODULE module, void *target, void *replacement) {
    BYTE *base = (BYTE *)module;
    IMAGE_NT_HEADERS *nt = (IMAGE_NT_HEADERS *)(base + ((IMAGE_DOS_HEADER *)base)->e_lfanew);
    IMAGE_DATA_DIRECTORY dir = nt->OptionalHeader.DataDirectory[IMAGE_DIRECTORY_ENTRY_IMPORT];
    IMAGE_IMPORT_DESCRIPTOR *imp;
    if (dir.VirtualAddress == 0) return 0;
    for (imp = (IMAGE_IMPORT_DESCRIPTOR *)(base + dir.VirtualAddress); imp->Name != 0; imp++) {
        IMAGE_THUNK_DATA *thunk = (IMAGE_THUNK_DATA *)(base + imp->FirstThunk);
        for (; thunk->u1.Function != 0; thunk++) {
            if ((void *)thunk->u1.Function == target) {
                DWORD old;
                if (!VirtualProtect(&thunk->u1.Function, sizeof(void *), PAGE_READWRITE, &old)) return 0;
                thunk->u1.Function = (ULONG_PTR)replacement;
                VirtualProtect(&thunk->u1.Function, sizeof(void *), old, &old);
                return 1;
            }
        }
    }
    return 0;
}

HL_PRIM int HL_NAME(gpu_choose_adapter)() {
    WCHAR want[128];
    HMODULE d3d, dx;
    DWORD n = GetEnvironmentVariableW(L"BH_PORT_ADAPTER", want, 128);
    if (n == 0 || n >= 128) return 0;
    if (chosen_adapter != NULL) return 1;
    chosen_adapter = (IDXGIAdapter *)find_adapter(want);
    if (chosen_adapter == NULL) return -1;
    d3d = GetModuleHandleW(L"d3d11.dll");
    dx = GetModuleHandleW(L"directx.hdll");
    if (d3d == NULL || dx == NULL) return -2;
    real_create = (create_device_swapchain_fn)GetProcAddress(d3d, "D3D11CreateDeviceAndSwapChain");
    if (real_create == NULL || !hook_import(dx, (void *)real_create, (void *)port_create_device_swapchain)) return -2;
    return 1;
}

DEFINE_PRIM(_I32, gpu_choose_adapter, _NO_ARG);

HL_PRIM vbyte *HL_NAME(gpu_adapter_name)() {
    return hl_copy_bytes((vbyte *)chosen_name, (int)(wcslen(chosen_name) + 1) * 2);
}

DEFINE_PRIM(_BYTES, gpu_adapter_name, _NO_ARG);
