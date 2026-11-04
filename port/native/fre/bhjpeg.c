#define HL_NAME(n) bhsound_##n
#include <hl.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO
#define STBIW_ASSERT(x)
#include "third_party/stb_image_write.h"

typedef struct {
    unsigned char *out;
    int cap;
    int size;
} Sink;

static void put(void *context, void *data, int size) {
    Sink *sink = (Sink *)context;
    if (sink->size < 0) return;
    if (sink->size + size > sink->cap) {
        sink->size = -1;
        return;
    }
    memcpy(sink->out + sink->size, data, size);
    sink->size += size;
}

HL_PRIM int HL_NAME(jpeg_encode)(vbyte *words, int stride, int x, int y, int width, int height, int quality, vbyte *out,
                                 int cap) {
    Sink sink = {(unsigned char *)out, cap, 0};
    unsigned char *rgb;
    int ok;
    if (width <= 0 || height <= 0) return -1;
    rgb = (unsigned char *)malloc((size_t)width * height * 3);
    if (rgb == NULL) return -1;
    for (int row = 0; row < height; row++) {
        const unsigned int *src = (const unsigned int *)words + (size_t)(y + row) * stride + x;
        unsigned char *dst = rgb + (size_t)row * width * 3;
        for (int col = 0; col < width; col++) {
            unsigned int c = src[col];
            dst[0] = (unsigned char)(c >> 16);
            dst[1] = (unsigned char)(c >> 8);
            dst[2] = (unsigned char)c;
            dst += 3;
        }
    }
    ok = stbi_write_jpg_to_func(put, &sink, width, height, 3, rgb, quality);
    free(rgb);
    return ok ? sink.size : -1;
}

DEFINE_PRIM(_I32, jpeg_encode, _BYTES _I32 _I32 _I32 _I32 _I32 _I32 _BYTES _I32);
