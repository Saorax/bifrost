#ifndef BHFRE_H
#define BHFRE_H

#include <stdint.h>

typedef void *FREContext;
typedef void *FREObject;

typedef enum {
    FRE_OK = 0,
    FRE_NO_SUCH_NAME = 1,
    FRE_INVALID_OBJECT = 2,
    FRE_TYPE_MISMATCH = 3,
    FRE_ACTIONSCRIPT_ERROR = 4,
    FRE_INVALID_ARGUMENT = 5,
    FRE_READ_ONLY = 6,
    FRE_WRONG_THREAD = 7,
    FRE_ILLEGAL_STATE = 8,
    FRE_INSUFFICIENT_MEMORY = 9,
    FREResult_ENUMPADDING = 0xfffff
} FREResult;

typedef FREObject (*FREFunction)(FREContext ctx, void *functionData, uint32_t argc, FREObject argv[]);

typedef struct {
    const uint8_t *name;
    void *functionData;
    FREFunction function;
} FRENamedFunction;

typedef void (*FREContextInitializer)(void *extData, const uint8_t *ctxType, FREContext ctx,
                                      uint32_t *numFunctionsToSet, const FRENamedFunction **functionsToSet);
typedef void (*FREContextFinalizer)(FREContext ctx);
typedef void (*FREInitializer)(void **extDataToSet, FREContextInitializer *ctxInitializerToSet,
                               FREContextFinalizer *ctxFinalizerToSet);
typedef void (*FREFinalizer)(void *extData);

enum { BHFRE_UINT = 0, BHFRE_DOUBLE = 1, BHFRE_STRING = 2, BHFRE_ARRAY = 3, BHFRE_NULL = 4 };

typedef struct BhFreValue {
    int type;
    uint32_t u;
    double d;
    const uint8_t *s;
    uint32_t length;
    struct BhFreValue **items;
} BhFreValue;

#endif
