#include <metal_stdlib>
#include <SwiftUI/SwiftUI_Metal.h>
using namespace metal;

static float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static float valueNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    float a = hash21(i), b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0)), d = hash21(i + float2(1.0, 1.0));
    float2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

/// GRAIN — poussières en alpha, pas un calque à fondre. Voir la version CLUB de cet effet pour
/// le détail du raisonnement ; l'amplitude est simplement pilotée bien plus bas ici (fond clair).
[[ stitchable ]] half4 grain(float2 pos, half4 color, float amount) {
    float n = hash21(pos);
    float d = max(n - 0.5, 0.0) / 0.5;
    half a = half(d * amount);
    return half4(half3(a), a);
}

/// L'ORBE VIVANT — la sphère organique de l'écran d'accueil.
///
/// Trois couches, dans cet ordre :
/// 1. Un bord qui ondule (bruit à basse fréquence, fonction de l'angle et du temps) : un cercle
///    parfait se lit comme une icône ; un bord qui respire se lit comme une goutte vivante.
/// 2. Un dégradé qui tourne lentement entre trois teintes chaudes — le mélange n'est jamais
///    figé, comme un fluide qu'on brasse.
/// 3. Un reflet et un assombrissement radial, qui donnent le VOLUME : sans eux, la forme reste
///    plate malgré son bord organique — un dégradé de couleur seul ne suffit pas à faire une
///    sphère, il faut aussi la lumière qui la frappe d'un côté.
[[ stitchable ]] half4 livingOrb(float2 pos, half4 color, float2 size, float time) {
    float2 uv = (pos - size * 0.5) / (min(size.x, size.y) * 0.5);
    float r = length(uv);
    float a = atan2(uv.y, uv.x);

    // BORD : rayon de référence perturbé par du bruit, mais échantillonné via cos(a)/sin(a) —
    // c'est-à-dire la POSITION sur le cercle, jamais l'angle brut. `a` lui-même saute de 2π à
    // la couture (-π/π, plein "9 heures") ; l'utiliser directement dans une fonction périodique
    // dont la fréquence n'est pas un multiple entier laisse une COUTURE visible, une ligne où le
    // motif ne se raccorde pas à lui-même. cos(a) et sin(a) sont continus partout — c'est
    // pourquoi le bord organique, lui, ne montrait pas ce défaut.
    float wobble = valueNoise(float2(cos(a) * 2.1 + time * 0.15, sin(a) * 2.1 + time * 0.15)) * 0.10;
    // Bord plus net : 0,06 de rayon de transition (au lieu de 0,20) — assez pour rester
    // anti-crénelé, assez peu pour que l'orbe ait un contour, pas un halo.
    float edge = 1.0 - smoothstep(0.82 + wobble, 0.88 + wobble, r);
    if (edge <= 0.001) { return half4(0.0h); }

    // MÊME piège pour le dégradé qui tourne : `2.0 * a` et `3.0 * a` sont les fréquences
    // angulaires les plus basses qui restent EXACTEMENT 2π-périodiques (un multiple entier),
    // donc sans couture — une fréquence de 1,3 ou 0,7, comme dans la version précédente,
    // recolle mal à la jointure et y dessine une ligne nette en plein milieu du dégradé.
    float mixer1 = 0.5 + 0.5 * sin(2.0 * a + time * 0.35);
    float mixer2 = 0.5 + 0.5 * cos(3.0 * a - time * 0.22 + r * 2.2);

    float3 orange = float3(0.95, 0.56, 0.24);
    float3 coral  = float3(0.94, 0.42, 0.34);
    float3 lilac  = float3(0.73, 0.55, 0.86);

    // Le lilas reste un ACCENT, pas la moitié de la sphère : à 0,55 il dominait le mélange et
    // l'orbe virait au rose plutôt qu'à l'orange-corail annoncé par la référence.
    float3 col = mix(mix(orange, coral, mixer1), lilac, mixer2 * 0.30);

    // Reflet glacé, en haut à gauche — la marque d'une surface bombée et lisse.
    float2 highlightPos = float2(-0.32, -0.40);
    float2 dh = uv - highlightPos;
    col += exp(-dot(dh, dh) * 3.6) * 0.45;

    // Assombrissement vers le bord : le volume de la sphère.
    col *= mix(1.05, 0.70, smoothstep(0.10, 0.88, r));

    return half4(half3(col) * half(edge), half(edge));
}
