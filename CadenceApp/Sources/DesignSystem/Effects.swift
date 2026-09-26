import SwiftUI

/// Grain, en Metal — voir `Shaders/Effects.metal`. Statique (pas de dépendance au temps), donc
/// mis en cache par `drawingGroup()` au lieu d'être recalculé à chaque image pour rien.
struct FilmGrain: View {
    var amount: Float = 0.035
    var body: some View {
        Rectangle()
            .colorEffect(ShaderLibrary.grain(.float(amount)))
            .drawingGroup()
            .allowsHitTesting(false)
    }
}

/// L'orbe vivant de l'écran d'accueil — voir `livingOrb` dans `Shaders/Effects.metal` pour le
/// détail du rendu. Cette vue ne fait que lui fournir une horloge et sa taille.
struct LivingOrb: View {
    var body: some View {
        TimelineView(.animation) { timeline in
            // Repli sur une fenêtre de 1000 s : voir la note dans le projet CLUB sur la perte de
            // précision d'un `float` 32 bits appliqué à `timeIntervalSinceReferenceDate` — sans
            // lui, l'orbe se fige au bout de quelques minutes d'exécution.
            let t = timeline.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
            Rectangle()
                .visualEffect { content, proxy in
                    content.colorEffect(ShaderLibrary.livingOrb(.float2(proxy.size), .float(t)))
                }
        }
        .allowsHitTesting(false)
    }
}
