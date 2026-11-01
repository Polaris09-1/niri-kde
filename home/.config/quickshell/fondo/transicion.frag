#version 440
// Transiciones del fondo: mezcla "desde" (fondo viejo) -> "hasta" (fondo nuevo).
// tipo: 0 fundido · 1 círculo desde el clic · 2 ola · 3 barrido diagonal
// Compilar:  /usr/lib/qt6/bin/qsb --qt6 -o transicion.frag.qsb transicion.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progreso;   // 0..1
    float tipo;
    float aspecto;    // ancho / alto
    vec2 centro;      // punto de origen, 0..1
};

layout(binding = 1) uniform sampler2D desde;
layout(binding = 2) uniform sampler2D hasta;

void main() {
    vec2 uv = qt_TexCoord0;
    float p = clamp(progreso, 0.0, 1.0);
    float m = p;                 // cuánto se ve del fondo nuevo
    vec2 uvViejo = uv;

    if (tipo > 0.5 && tipo < 1.5) {
        // Círculo que crece desde el punto del clic, con borde suave
        vec2 d = (uv - centro) * vec2(aspecto, 1.0);
        vec2 lejos = max(centro, 1.0 - centro) * vec2(aspecto, 1.0);
        float radioMax = length(lejos) + 0.05;
        float r = p * radioMax;
        float borde = 0.035;
        m = 1.0 - smoothstep(r - borde, r, length(d));
        // Leve empuje del fondo viejo justo en el borde
        float anillo = smoothstep(borde * 3.0, 0.0, abs(length(d) - r)) * (1.0 - p);
        uvViejo = uv - normalize(d + 1e-5) / vec2(aspecto, 1.0) * anillo * 0.012;
    } else if (tipo > 1.5 && tipo < 2.5) {
        // Ola: frente ondulado que cruza la pantalla desde el lado del clic
        float x = centro.x < 0.5 ? uv.x : 1.0 - uv.x;
        float onda = sin(uv.y * 14.0 + p * 9.0) * 0.035 + sin(uv.y * 5.0 - p * 4.0) * 0.025;
        float frente = p * 1.25 - 0.12;
        m = 1.0 - smoothstep(frente - 0.04, frente + 0.04, x + onda);
        float cerca = smoothstep(0.12, 0.0, abs(x + onda - frente));
        uvViejo = uv + vec2(0.0, sin(uv.x * 30.0 + p * 20.0) * 0.006 * cerca);
    } else if (tipo > 2.5) {
        // Barrido diagonal desde la esquina más cercana al clic
        vec2 q = uv;
        if (centro.x > 0.5) q.x = 1.0 - q.x;
        if (centro.y > 0.5) q.y = 1.0 - q.y;
        float diag = (q.x * aspecto + q.y) / (aspecto + 1.0);
        float frente = p * 1.2 - 0.1;
        m = 1.0 - smoothstep(frente - 0.06, frente + 0.06, diag);
    } else {
        // Fundido suave
        m = smoothstep(0.0, 1.0, p);
    }

    vec4 a = texture(desde, uvViejo);
    vec4 b = texture(hasta, uv);
    fragColor = mix(a, b, m) * qt_Opacity;
}
