// wallfx.frag — customizable character-outline & contagion transition shader for DMS WallFX.
#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// qt_Matrix + qt_Opacity first, then floats only, then vec4s (std140 layout).
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float t;            // 0..1, linear in time
    float mode;         // 0 contagion, 1 outline
    float sw;           // screen width, px
    float sh;           // screen height, px
    float fw;           // fieldTex width, texels
    float fh;           // fieldTex height, texels
    float lw;           // lineTex width, texels
    float lh;           // lineTex height, texels
    float glow;         // 0..1.5, contagion burning edge & spark intensity
    float outlineGlow;  // 0..1.5, character aura / neon silhouette glow intensity
    float lineW;        // outline pen width, px
    float cellSize;     // pixel cell size, px (1 = smooth liquid, 4 = default, 8..12 = chunky pixel art)
    float parallax;     // 0..0.08, 3D camera zoom-in settle depth
    float stageDim;     // 0..0.85, old wallpaper dimming/desaturation
    float tDrawStart;   // normalized start of character outline trace
    float tDrawDur;     // normalized duration of character outline trace
    float tFillStart;   // normalized start of character interior fill
    float tFillDur;     // normalized duration of character interior fill
    float tBgStart;     // normalized start of background eruption
    float tBgDur;       // normalized duration of background eruption
    float sdRange;      // fieldTex B spans +-sdRange map px
    float seed;         // random seed per transition
    vec4 cropOld;       // image uv = xy + screen uv * zw
    vec4 cropNew;
    vec4 ember;         // vivid glow / burning edge color
    vec4 ink;           // outline pen stroke color
};

layout(binding = 1) uniform sampler2D oldTex;
layout(binding = 2) uniform sampler2D newTex;
layout(binding = 3) uniform sampler2D fieldTex;
layout(binding = 4) uniform sampler2D lineTex;

const float PI = 3.14159265;

float escena(float x) {
    x = clamp(x, 0.0, 1.0);
    return x * x * (3.0 - 2.0 * x);
}

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7)) + seed * 13.17) * 43758.5453);
}

float luma(vec3 c) {
    return dot(c, vec3(0.299, 0.587, 0.114));
}

vec2 cam(vec2 uv, float z) {
    return 0.5 + (uv - 0.5) / max(z, 0.001);
}

vec3 oldAt(vec2 uv) {
    return texture(oldTex, cropOld.xy + uv * cropOld.zw).rgb;
}

vec2 newUv(vec2 uv, float z) {
    return cropNew.xy + cam(uv, z) * cropNew.zw;
}

// Fast 4-tap hardware-bilinear Cubic B-Spline filter.
// Converts 8-bit 1280p SDF textures into C2-continuous vector-smooth curves with zero staircase artifacts.
vec4 textureBicubic(sampler2D tex, vec2 uv, vec2 texSize) {
    vec2 coord = uv * texSize - 0.5;
    vec2 f = fract(coord);
    vec2 i = floor(coord);

    vec2 f2 = f * f;
    vec2 f3 = f2 * f;

    vec2 w0 = (1.0 - f) * (1.0 - f) * (1.0 - f) / 6.0;
    vec2 w1 = (3.0 * f3 - 6.0 * f2 + 4.0) / 6.0;
    vec2 w2 = (-3.0 * f3 + 3.0 * f2 + 3.0 * f + 1.0) / 6.0;
    vec2 w3 = f3 / 6.0;

    vec2 g0 = w0 + w1;
    vec2 g1 = w2 + w3;

    vec2 h0 = (i - 0.5 + w1 / g0) / texSize;
    vec2 h1 = (i + 1.5 + w3 / g1) / texSize;

    vec4 tex00 = texture(tex, vec2(h0.x, h0.y));
    vec4 tex10 = texture(tex, vec2(h1.x, h0.y));
    vec4 tex01 = texture(tex, vec2(h0.x, h1.y));
    vec4 tex11 = texture(tex, vec2(h1.x, h1.y));

    return mix(
        mix(tex00, tex10, g1.x),
        mix(tex01, tex11, g1.x),
        g1.y
    );
}

// 16-bit surface in lineTex's G (high) and B (low), bilinearly interpolated in float
float s16(vec2 texel) {
    texel = clamp(texel, vec2(0.0), vec2(lw, lh) - 1.0);
    vec4 f = texture(lineTex, (texel + 0.5) / vec2(lw, lh));
    return (floor(f.g * 255.0 + 0.5) * 256.0 + floor(f.b * 255.0 + 0.5)) / 65535.0;
}

float surface(vec2 tuv) {
    vec2 p = tuv * vec2(lw, lh) - 0.5;
    vec2 i = floor(p), f = p - i;
    return mix(
        mix(s16(i), s16(i + vec2(1.0, 0.0)), f.x),
        mix(s16(i + vec2(0.0, 1.0)), s16(i + vec2(1.0, 1.0)), f.x),
        f.y
    );
}

// ───────────────────────────── contagion ─────────────────────────────

float arrivalAt(vec2 c) {
    c = clamp(c, vec2(0.0), vec2(fw, fh) - 1.0);
    vec4 f = texture(fieldTex, (c + 0.5) / vec2(fw, fh));
    return (floor(f.r * 255.0 + 0.5) * 256.0 + floor(f.g * 255.0 + 0.5)) / 65535.0;
}

vec3 contagion(vec2 uv) {
    const float LIFE = 0.05;
    float energy = sin(PI * t);
    float T = escena(t) * (1.0 + LIFE + 0.01) - 0.01;
    float s = surface(uv);
    float scaleFactor = 4.0 / max(cellSize, 1.0);
    vec2 effGrid = vec2(fw, fh) * scaleFactor;
    vec2 cell = floor(uv * effGrid) / scaleFactor;
    float a = cellSize <= 1.05 ? s : arrivalAt(floor(cell));
    float flick = hash(floor(uv * effGrid));
    vec3 hot = mix(ember.rgb, vec3(1.0), 0.18);
    float zCon = 1.0 + (parallax * 0.85) * (1.0 - escena(t));
    vec3 c;
    if (a > T) {
        c = oldAt(uv);
        float ahead = a - T;
        if (flick > 0.985 && ahead < 0.02) {
            c = mix(c, hot, (1.0 - ahead / 0.02) * 0.8 * glow * step(0.0, T));
        }
    } else {
        c = texture(newTex, newUv(uv, zCon)).rgb;
        vec2 bc = floor(cell);
        bool edge = max(
            max(arrivalAt(bc + vec2(1.0, 0.0)), arrivalAt(bc - vec2(1.0, 0.0))),
            max(arrivalAt(bc + vec2(0.0, 1.0)), arrivalAt(bc - vec2(0.0, 1.0)))
        ) > T;
        float life = clamp((T - a) / LIFE, 0.0, 1.0);
        float burn = (1.0 - life) * (1.0 - life) * (edge ? 1.0 : 0.55);
        c = mix(c, hot, burn * (0.55 + 0.45 * flick) * 0.85 * glow);
    }
    return c + ember.rgb * 0.22 * glow * energy * exp(-abs(s - T) / 0.006);
}

// ───────────────────────────── outline ─────────────────────────────

vec3 outline(vec2 uv) {
    float zCh = 1.0 + parallax * (1.0 - escena(t));
    float zBg = 1.0 + (parallax * 0.5) * (1.0 - escena(t));
    vec2 nuvCh = newUv(uv, zCh);

    // Sample the signed distance field with C2 bicubic B-spline filtering to eliminate texel staircase
    vec4 f = textureBicubic(fieldTex, nuvCh, vec2(fw, fh));
    float mapToScreenPx = sw * zCh / (fw * cropNew.z);
    float sdPx = (f.b * 2.0 - 1.0) * sdRange * mapToScreenPx;

    // True screen-pixel antialiasing (no noisy 8-bit texel fwidth artifacts)
    float inside = smoothstep(0.9, -0.9, sdPx);

    // Stage dimming: darken and desaturate the old wallpaper according to stageDim
    float dimRamp = escena(t / max(tDrawStart + tDrawDur * 0.5, 0.08));
    vec3 st = oldAt(uv);
    st = mix(st, vec3(luma(st)), min(stageDim * 1.25, 1.0) * dimRamp) * (1.0 - stageDim * dimRamp);

    // Cell quantization (1 px = smooth liquid, >=2 px = stepped cells)
    vec2 cuv = uv;
    if (cellSize > 1.05) {
        vec2 grid = vec2(sw, sh) / cellSize;
        cuv = (floor(uv * grid) + 0.5) / grid;
    }

    // Stage 2: Character interior fills inward from silhouette
    float Ti = escena((t - tFillStart) / max(tFillDur, 0.001)) * 1.02 - 0.01;
    float inDepth = texture(fieldTex, newUv(cuv, zCh)).g;
    vec3 cIn = inDepth <= Ti ? texture(newTex, nuvCh).rgb : st;

    // Stage 3: Background erupts outward from silhouette
    float To = escena((t - tBgStart) / max(tBgDur, 0.001)) * 1.02 - 0.01;
    float outOrder = surface(newUv(cuv, zBg));
    vec3 cOut = outOrder <= To ? texture(newTex, newUv(uv, zBg)).rgb : st;
    vec3 c = mix(cOut, cIn, inside);

    // Stage 1: Two pen strokes trace the character silhouette from top to bottom
    float drawP = escena((t - tDrawStart) / max(tDrawDur, 0.001));
    float lp = texture(lineTex, nuvCh).r;
    float fade = 1.0 - escena((t - tBgStart) / max(tBgDur * 0.55, 0.05));
    if (lp > 0.0 && fade > 0.0) {
        // Smooth pen-tip progression instead of hard single-texel cutoff
        float tipMask = smoothstep(-0.004, 0.014, drawP - lp);
        if (tipMask > 0.0) {
            float halfW = max(lineW * 0.5, 0.4);
            float d = abs(sdPx) - halfW;
            // Crisp screen-space antialiased core + subtle 1.2px brush edge softness
            float core = smoothstep(1.15, -0.85, d) * tipMask;
            c = mix(c, ink.rgb, core * 0.88 * fade);

            if (outlineGlow > 0.001) {
                float halo = exp(-max(d, 0.0) / (5.0 + 10.0 * outlineGlow)) * tipMask;
                float tipBoost = 1.0 + 0.85 * exp(-max(drawP - lp, 0.0) / 0.035);
                c += mix(ember.rgb, ink.rgb, 0.35) * halo * tipBoost * 0.55 * outlineGlow * fade;
            }
        }
    }

    // Optional outer aura & shockwave rim glow when outlineGlow > 0
    if (outlineGlow > 0.001) {
        float energy = sin(PI * t);
        float aura = (1.0 - inside) * exp(-f.r * 4.5) * fade * clamp(drawP * 1.5, 0.0, 1.0);
        float inRim = inside * exp(-abs(inDepth - Ti) / 0.025) * step(0.001, Ti) * step(Ti, 0.999);
        float outRim = (1.0 - inside) * exp(-abs(outOrder - To) / 0.012) * step(0.001, To) * step(To, 0.999);
        c += ember.rgb * outlineGlow * energy * (0.38 * aura + 0.35 * inRim + 0.30 * outRim);
    }

    return c;
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec3 c = mode < 0.5 ? contagion(uv) : outline(uv);
    fragColor = vec4(clamp(c, 0.0, 1.0), 1.0) * qt_Opacity;
}
