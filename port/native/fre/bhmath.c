#define HL_NAME(n) bhsound_##n
#include <hl.h>
#include <windows.h>
#include <math.h>

typedef double (*Fn1)(double);
typedef double (*Fn2)(double, double);

static const char *names1[] = {"sin", "cos", "tan", "asin", "acos", "atan", "exp", "log"};
static Fn1 fns1[8];
static Fn2 fn_atan2, fn_pow;
static int loaded = -1;

static void load(void) {
    HMODULE crt = LoadLibraryA("msvcr120.dll");
    Fn1 local1[8] = {sin, cos, tan, asin, acos, atan, exp, log};
    loaded = crt != NULL;
    for (int i = 0; i < 8; i++) {
        Fn1 f = crt ? (Fn1)GetProcAddress(crt, names1[i]) : NULL;
        fns1[i] = f ? f : local1[i];
    }
    fn_atan2 = crt ? (Fn2)GetProcAddress(crt, "atan2") : NULL;
    fn_pow = crt ? (Fn2)GetProcAddress(crt, "pow") : NULL;
    if (!fn_atan2) fn_atan2 = atan2;
    if (!fn_pow) fn_pow = pow;
}

HL_PRIM double HL_NAME(math1)(int op, double x) {
    if (loaded < 0) load();
    return op >= 0 && op < 8 ? fns1[op](x) : x;
}

HL_PRIM double HL_NAME(math2)(int op, double x, double y) {
    if (loaded < 0) load();
    return op == 0 ? fn_atan2(x, y) : fn_pow(x, y);
}

HL_PRIM int HL_NAME(math_source)() {
    if (loaded < 0) load();
    return loaded;
}

DEFINE_PRIM(_F64, math1, _I32 _F64);
DEFINE_PRIM(_F64, math2, _I32 _F64 _F64);
DEFINE_PRIM(_I32, math_source, _NO_ARG);
