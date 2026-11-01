// Redirige UN nodo de render DRM a otro, solo dentro del proceso que la carga (LD_PRELOAD).
// Para qué: FFmpeg (el backend de vídeo de Qt) abre para VA-API el primer nodo, /dev/dri/renderD128,
// que en este portátil es la NVIDIA (nouveau, sin decodificación H.264) → falla y decodifica por CPU.
// Con FONDO_RENDER_DESDE=/dev/dri/renderD128 y FONDO_RENDER_HASTA=/dev/dri/renderD129 abre la Radeon.
// No cambia nada más: cualquier otra ruta se abre tal cual.
// Compilar: gcc -O2 -shared -fPIC -o ~/.local/lib/fondo/redirigir-render.so redirigir-render.c -ldl
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdlib.h>
#include <string.h>

static const char *cambiar(const char *ruta) {
    const char *desde = getenv("FONDO_RENDER_DESDE"), *hasta = getenv("FONDO_RENDER_HASTA");
    if (ruta && desde && hasta && *desde && *hasta && strcmp(ruta, desde) == 0) return hasta;
    return ruta;
}

#define ENVOLVER(nombre)                                                        \
    int nombre(const char *ruta, int flags, ...) {                              \
        static int (*real)(const char *, int, ...);                             \
        if (!real) real = dlsym(RTLD_NEXT, #nombre);                            \
        mode_t modo = 0;                                                        \
        if (flags & (O_CREAT | O_TMPFILE)) {                                    \
            va_list a; va_start(a, flags); modo = va_arg(a, mode_t); va_end(a); \
        }                                                                       \
        return real(cambiar(ruta), flags, modo);                                \
    }
ENVOLVER(open)
ENVOLVER(open64)

#define ENVOLVER_AT(nombre)                                                     \
    int nombre(int dir, const char *ruta, int flags, ...) {                     \
        static int (*real)(int, const char *, int, ...);                        \
        if (!real) real = dlsym(RTLD_NEXT, #nombre);                            \
        mode_t modo = 0;                                                        \
        if (flags & (O_CREAT | O_TMPFILE)) {                                    \
            va_list a; va_start(a, flags); modo = va_arg(a, mode_t); va_end(a); \
        }                                                                       \
        return real(dir, cambiar(ruta), flags, modo);                           \
    }
ENVOLVER_AT(openat)
ENVOLVER_AT(openat64)

// Variantes con _FORTIFY_SOURCE
int __open_2(const char *ruta, int flags) {
    static int (*real)(const char *, int);
    if (!real) real = dlsym(RTLD_NEXT, "__open_2");
    return real(cambiar(ruta), flags);
}
int __open64_2(const char *ruta, int flags) {
    static int (*real)(const char *, int);
    if (!real) real = dlsym(RTLD_NEXT, "__open64_2");
    return real(cambiar(ruta), flags);
}
