import SwiftUI

/// Le verre liquide de Cadence — même principe que le verre d'Apple, adapté à un fond CLAIR.
///
/// **`.glassEffect()` natif DÉSACTIVÉ par défaut, pour l'instant.** L'idée de départ était de
/// l'utiliser quand il existe (iOS 26+) et de replier sur une recette maison sinon. En pratique,
/// sur ce SDK, il s'est montré deux fois en faute dans cette app : un `GeometryReader` posé
/// dedans se fait mesurer à plus de 22 000 points au lieu de ~370 (voir `StaffView`), et un
/// simple bouton texte enveloppé dedans reste PARFAITEMENT VIDE — la place est bien réservée
/// dans la mise en page, mais rien n'est peint, ni le verre ni le texte. Ce n'est pas un usage
/// incorrect de l'API de notre part : un `Text` seul dans un `.glassEffect()` est le cas le plus
/// simple possible. Plutôt que de traquer un bug d'un SDK tout juste sorti, la recette maison —
/// prévisible, déjà correcte — devient le chemin par défaut ; `native: true` reste disponible
/// pour repasser au verre système le jour où ce comportement sera corrigé.
struct LiquidGlass: ViewModifier {
    var radius: CGFloat
    /// Teinte du verre — chaque bouton peut porter la couleur de son action (l'orbe orange
    /// derrière le micro, le lilas derrière une action secondaire) sans changer de recette.
    var tint: Color = .white
    var native: Bool = false

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *), native {
            content.glassEffect(.regular.tint(tint.opacity(0.28)),
                                in: RoundedRectangle(cornerRadius: radius, style: .continuous))
        } else {
            handmade(content)
        }
    }

    @ViewBuilder
    private func handmade(_ content: Content) -> some View {
        content
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(tint.opacity(0.16))
                    // Lèvre HAUTE, blanche : c'est elle qui fait "verre" plutôt que "carte
                    // colorée" — un highlight qui simule la lumière glissant sur une tranche
                    // bombée.
                    LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.05)],
                                  startPoint: .top, endPoint: .center)
                }
                // DÉCOUPE INDISPENSABLE. `LinearGradient`, posé nu dans le `ZStack` ci-dessus,
                // n'est pas automatiquement borné à la forme des `RoundedRectangle` voisines —
                // il peint tout le rectangle qu'on lui offre, coins compris. Sans ce
                // `clipShape`, cette teinte dépassait des coins arrondis, et surtout l'OMBRE
                // portée juste en dessous se calculait sur ce rectangle plein plutôt que sur la
                // silhouette arrondie : c'est cette ombre rectangulaire qui se voyait comme une
                // arête dure derrière la pilule, sur la barre de navigation notamment.
                .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(0.75), lineWidth: 1)
            }
            // Ombre CHAUDE (teinte encre, pas noir pur) : sur un fond crème, une ombre neutre se
            // détache comme un défaut d'impression plutôt que comme du volume.
            .shadow(color: C.ink.opacity(0.12), radius: 16, y: 8)
    }
}

extension View {
    func liquidGlass(radius: CGFloat = 22, tint: Color = .white, native: Bool = false) -> some View {
        modifier(LiquidGlass(radius: radius, tint: tint, native: native))
    }
}

/// Bouton-pastille en verre : icône + libellé, pour les trois actions de l'écran d'accueil
/// (Signification / Micro / Transcription) et les onglets du bas.
struct GlassIconLabel: View {
    let systemImage: String
    let label: String
    var tint: Color = .white
    var prominent: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: prominent ? 26 : 20, weight: .medium))
                .foregroundStyle(prominent ? .white : C.ink)
                .frame(width: prominent ? 74 : 56, height: prominent ? 74 : 56)
                .background {
                    Circle().fill(prominent ? tint : .white.opacity(0.001)) // opaque pour l'effet verre en dessous
                }
                .liquidGlass(radius: prominent ? 37 : 28, tint: tint)
            Text(label)
                .font(.system(size: 13))
                .foregroundStyle(C.ink2)
        }
    }
}
