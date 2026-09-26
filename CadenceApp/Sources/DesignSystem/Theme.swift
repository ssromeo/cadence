import SwiftUI

/// Palette — un thème CLAIR et chaud, à l'opposé du noir des apps de chat vocal habituelles.
/// Le choix n'est pas cosmétique : un fond crème dit "papier, carnet, étude", quand un fond noir
/// dit "studio, nuit, prestige". Cadence est un carnet d'exercices, pas une console de mixage.
enum C {
    static let cream      = Color(hex: 0xFCF4E8)
    static let creamDeep  = Color(hex: 0xF3E4CE)
    static let ink        = Color(hex: 0x2B2117)
    static let ink2       = Color(hex: 0x2B2117).opacity(0.62)
    static let inkFaint   = Color(hex: 0x2B2117).opacity(0.34)
    static let line       = Color(hex: 0x2B2117).opacity(0.08)

    static let apricot    = Color(hex: 0xF0A25C)
    static let coral      = Color(hex: 0xF0785C)
    static let lilac      = Color(hex: 0xB98CE0)

    static let good       = Color(hex: 0x4E9A6B)
    static let goodSoft   = Color(hex: 0x4E9A6B).opacity(0.14)
    static let bad        = Color(hex: 0xD5604A)
    static let badSoft    = Color(hex: 0xD5604A).opacity(0.14)
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: alpha)
    }
}

/// Fond de l'app : un aplat crème, avec un grain TRÈS discret pour casser le banding sur les
/// grands aplats clairs — le même besoin que sur un fond sombre, mais une intensité dix fois
/// plus faible : un grain calibré pour du noir écrase un fond clair sous une brume visible.
struct AppBackground: View {
    var body: some View {
        ZStack {
            C.cream
            FilmGrain(amount: 0.035)
        }
        .ignoresSafeArea()
    }
}
