#include <stdlib.h>
#include "bhfre.h"

#define EXPORT __declspec(dllexport)

#define RING 256
static BhFreValue results[RING];
static unsigned next_result = 0;

EXPORT FREResult FREGetObjectAsUTF8(FREObject object, uint32_t *length, const uint8_t **value) {
    BhFreValue *v = (BhFreValue *)object;
    if (v == NULL || length == NULL || value == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type != BHFRE_STRING) return FRE_TYPE_MISMATCH;
    *length = v->length;
    *value = v->s;
    return FRE_OK;
}

EXPORT FREResult FREGetObjectAsUint32(FREObject object, uint32_t *value) {
    BhFreValue *v = (BhFreValue *)object;
    if (v == NULL || value == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type == BHFRE_UINT) {
        *value = v->u;
        return FRE_OK;
    }
    if (v->type == BHFRE_DOUBLE && v->d >= 0 && v->d <= 4294967295.0 && v->d == (double)(uint32_t)v->d) {
        *value = (uint32_t)v->d;
        return FRE_OK;
    }
    return FRE_TYPE_MISMATCH;
}

EXPORT FREResult FREGetObjectAsDouble(FREObject object, double *value) {
    BhFreValue *v = (BhFreValue *)object;
    if (v == NULL || value == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type == BHFRE_DOUBLE) {
        *value = v->d;
        return FRE_OK;
    }
    if (v->type == BHFRE_UINT) {
        *value = (double)v->u;
        return FRE_OK;
    }
    return FRE_TYPE_MISMATCH;
}

EXPORT FREResult FREGetArrayElementAt(FREObject arrayOrVector, uint32_t index, FREObject *value) {
    BhFreValue *v = (BhFreValue *)arrayOrVector;
    if (v == NULL || value == NULL) return FRE_INVALID_ARGUMENT;
    if (v->type != BHFRE_ARRAY) return FRE_TYPE_MISMATCH;
    if (index >= v->length) return FRE_INVALID_ARGUMENT;
    *value = v->items[index];
    return FRE_OK;
}

EXPORT FREResult FRENewObjectFromUint32(uint32_t value, FREObject *object) {
    BhFreValue *v;
    if (object == NULL) return FRE_INVALID_ARGUMENT;
    v = &results[next_result++ % RING];
    v->type = BHFRE_UINT;
    v->u = value;
    v->d = 0;
    v->s = NULL;
    v->length = 0;
    v->items = NULL;
    *object = v;
    return FRE_OK;
}
