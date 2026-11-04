#version 440
// Tarjeta de la galería: un solo shader para la forma y el desenfoque.
// - Forma: rectángulo redondeado con el MARCO inclinado (sesgo = 0 → recto; la imagen no se inclina).
// - Desenfoque: niveles de mipmap (sesgo de LOD) + 8 muestras para suavizar; barato y sin pasadas extra.
// - Borde y sombra salen de la misma distancia (SDF), sin capas aparte.
// Compilar:  /usr/lib/qt6/bin/qsb --qt6 -o tarjeta.frag.qsb tarjeta.frag

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 tam;           // tamaño del elemento en px (tarjeta + inclinación + margen de la sombra)
    vec2 caja;          // tamaño de la tarjeta sin inclinar, en px
    float sesgo;        // px horizontales por px de alto
    float radio;        // px
    float desenfoque;   // niveles de mipmap que se suben (0 = nítida)
    float relacion;     // ancho / alto de la imagen
    float grosorBorde;  // px
    float alfaBorde;
    float alfaSombra;
    float alcanceSombra; // px
    vec4 colorBorde;
    vec4 colorSombra;
};

layout(binding = 1) uniform sampler2D fuente;

float distancia(vec2 p) {
    vec2 q = abs(vec2(p.x + sesgo * p.y, p.y)) - caja * 0.5 + vec2(radio);
    return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radio;
}

vec4 muestra(vec2 uv) {
    if (desenfoque < 0.02) return texture(fuente, uv);
    // Ocho muestras en círculo: quitan el aspecto de cuadros de los mipmaps. El radio equivale a un
    // texel del nivel que se lee (2^desenfoque píxeles de pantalla), sea cual sea el tamaño de la tarjeta.
    vec2 e = vec2(abs(dFdx(uv.x)), abs(dFdy(uv.y))) * pow(2.0, desenfoque) * 1.2;
    vec4 s = texture(fuente, uv, desenfoque) * 2.0;
    s += texture(fuente, uv + e * vec2( 1.000,  0.000), desenfoque);
    s += texture(fuente, uv + e * vec2( 0.707,  0.707), desenfoque);
    s += texture(fuente, uv + e * vec2( 0.000,  1.000), desenfoque);
    s += texture(fuente, uv + e * vec2(-0.707,  0.707), desenfoque);
    s += texture(fuente, uv + e * vec2(-1.000,  0.000), desenfoque);
    s += texture(fuente, uv + e * vec2(-0.707, -0.707), desenfoque);
    s += texture(fuente, uv + e * vec2( 0.000, -1.000), desenfoque);
    s += texture(fuente, uv + e * vec2( 0.707, -0.707), desenfoque);
    return s / 10.0;
}

void main() {
    vec2 p = (qt_TexCoord0 - 0.5) * tam;
    float d = distancia(p);
    float aa = max(fwidth(d), 0.75);   // filtro de unos 2 px: en un lado inclinado, uno más fino deja puntitos
    float dentro = 1.0 - smoothstep(-aa, aa, d);

    // La imagen cubre la caja que envuelve al marco inclinado y NO se inclina con él.
    // Se lee siempre, sin un "if dentro": las derivadas de texture()/dFdx() fallan en los bordes si la
    // lectura solo ocurre en parte de los píxeles, y salían puntitos a lo largo del lado inclinado.
    vec2 envolvente = vec2(caja.x + abs(sesgo) * caja.y, caja.y);
    vec2 rel = p / envolvente;
    float a = envolvente.x / envolvente.y;
    vec2 uv = a > relacion ? vec2(rel.x, rel.y * relacion / a) : vec2(rel.x * a / relacion, rel.y);
    vec4 col = muestra(uv + 0.5);
    if (grosorBorde > 0.0 && alfaBorde > 0.0) {
        float anillo = smoothstep(-grosorBorde - aa, -grosorBorde + aa, d) * alfaBorde;
        col = mix(col, vec4(colorBorde.rgb, 1.0), anillo);
    }

    vec4 salida = col * dentro;
    if (alfaSombra > 0.0 && d > -aa) {
        float s = 1.0 - clamp(d / alcanceSombra, 0.0, 1.0);
        salida += vec4(colorSombra.rgb, 1.0) * alfaSombra * s * s * (1.0 - dentro);
    }
    fragColor = salida * qt_Opacity;
}
