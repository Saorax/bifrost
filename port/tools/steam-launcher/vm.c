#include <hl.h>
#include <hlmodule.h>
#include <stdio.h>

typedef void (*log_fn)(const wchar_t *line);

static void say(log_fn log, const wchar_t *format, const uchar *value)
{
    wchar_t line[1024];
    _snwprintf(line, 1023, format, value);
    line[1023] = 0;
    log(line);
}

__declspec(dllexport) int bifrost_run_game(const wchar_t *file, int argc, wchar_t **argv, log_fn log)
{
    static vclosure cl;
    hl_code *code;
    hl_module *m;
    vdynamic *ret;
    char *error_msg = NULL;
    bool isExc = false;
    int dummy;
    FILE *f = _wfopen(file, L"rb");
    long size;
    char *data;
    if (!f) { say(log, L"no game build %s\r\n", file); return 1; }
    fseek(f, 0, SEEK_END);
    size = ftell(f);
    fseek(f, 0, SEEK_SET);
    data = (char*)malloc(size);
    if (!data || fread(data, 1, size, f) != (size_t)size) { fclose(f); say(log, L"could not read %s\r\n", file); return 1; }
    fclose(f);
    hl_global_init();
    hl_sys_init((void**)argv, argc, (void*)file);
    hl_register_thread(&dummy);
    code = hl_code_read((unsigned char*)data, size, &error_msg);
    free(data);
    if (code == NULL) { say(log, L"the game build could not be read: %s\r\n", file); return 1; }
    m = hl_module_alloc(code);
    if (m == NULL) return 2;
    if (!hl_module_init(m, false, false)) return 3;
    hl_code_free(code);
    cl.t = code->functions[m->functions_indexes[m->code->entrypoint]].type;
    cl.fun = m->functions_ptrs[m->code->entrypoint];
    cl.hasValue = 0;
    hl_profile_setup(-1);
    ret = hl_dyn_call_safe(&cl, NULL, 0, &isExc);
    hl_profile_end();
    if (isExc) {
        varray *a = hl_exception_stack();
        int i;
        say(log, L"uncaught exception: %s\r\n", hl_to_string(ret));
        for (i = 0; i < a->size && i < 40; i++) say(log, L"  called from %s\r\n", hl_aptr(a, uchar*)[i]);
        hl_global_free();
        return 1;
    }
    hl_module_free(m);
    hl_free(&code->alloc);
    hl_global_free();
    return 0;
}
