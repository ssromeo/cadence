import SwiftUI
import CadenceCore

/// Le pilier 2 du projet, tel quel : "je n'ai pas de morceau à importer maintenant — mais je
/// veux quand même travailler quelque chose." On choisit une tonalité, puis un PARCOURS
/// d'étapes distinctes s'ouvre sur elle (voir `ScalePathView`) — jamais un unique quiz qui
/// mélangerait notes, intervalles et accords sans qu'on sache lequel on travaille.
///
/// **Navigation locale, pas un onglet de plus.** Le choix d'une gamme puis son parcours restent
/// entièrement à l'intérieur de cet onglet — `selectedKey` bascule simplement entre la grille et
/// le parcours, sans jamais toucher à `RootTab`. C'est la même logique qu'une pile de navigation,
/// en plus simple : deux états, pas de pile à gérer.
struct ScalesView: View {
    @State private var selectedKey: MusicalKey?
    @State private var isMinorMode = false

    /// Ordre du cercle des quintes plutôt que l'ordre chromatique brut — do, sol, ré, la, mi…
    /// c'est l'ordre dans lequel un musicien apprend réellement les tonalités, des moins
    /// altérées vers les plus altérées.
    private static let circleOfFifths = [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5]

    /// En mode mineur, ce n'est PAS le même cercle qu'en majeur transposé au hasard — chaque
    /// tonique mineure est le RELATIF de la tonique majeure au même index (une tierce mineure en
    /// dessous, `+9` modulo 12), ce qui préserve exactement le même ordre "des moins altérées aux
    /// plus altérées" : la mineur (0 altération) d'abord, comme do majeur en mode majeur, jusqu'à
    /// ré mineur en dernier, comme fa majeur.
    private var keys: [MusicalKey] {
        Self.circleOfFifths.map { tonic in
            let effectiveTonic = isMinorMode ? (tonic + 9) % 12 : tonic
            return MusicalKey(tonicPitchClass: effectiveTonic, isMajor: !isMinorMode)
        }
    }

    var body: some View {
        ZStack {
            // Un seul fond, ICI — pas un par branche. `Group { if/else }` remplace tout son
            // contenu à chaque bascule, armure ou pas : sans ce fond posé UNE fois, autour du
            // `Group` plutôt que dans chacune de ses branches, l'écran se serait retrouvé blanc
            // le temps où aucune des deux branches ne portait plus le sien.
            AppBackground()

            // PAS de `.animation(value: selectedKey)` en plus des `withAnimation` posés aux points
            // d'appel — même piège que dans `RootView` : les deux ensemble font tourner deux
            // animations concurrentes sur le même changement d'état, et la transition clignote au
            // lieu de fondre.
            Group {
                if let key = selectedKey {
                    ScalePathView(key: key) {
                        withAnimation(.easeInOut(duration: 0.2)) { selectedKey = nil }
                    }
                    .transition(.opacity)
                } else {
                    keyGrid
                        .transition(.opacity)
                }
            }
        }
    }

    private var keyGrid: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 8)

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 12) {
                    ForEach(rows, id: \.0.tonicPitchClass) { first, second in
                        HStack(spacing: 12) {
                            keyCard(first)
                            if let second {
                                keyCard(second)
                            } else {
                                Color.clear.frame(width: cardWidth)
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sans morceau").font(.system(size: 15)).foregroundStyle(C.ink2)
                Text("Choisis une gamme")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
            }
            modeToggle
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Majeur/mineur, pas un simple bouton "mineur" en plus des douze cartes majeures — les
    /// gammes mineures ont leur PROPRE cercle des quintes (voir `keys`), donc leur propre grille
    /// complète de douze tonalités plutôt qu'un mode caché derrière une case à cocher.
    ///
    /// Deux `Button` explicitement LARGEUR FIXE côte à côte, jamais `.frame(maxWidth: .infinity)`
    /// sur des boutons voisins — un bogue connu du SDK rend alors le `Text` de l'un des deux
    /// invisible. Voir `QuizView.modeToggle` pour le même détour, déjà éprouvé ailleurs dans l'app.
    private var modeToggle: some View {
        let width = (UIScreen.main.bounds.width - 48 - 6) / 2
        return HStack(spacing: 6) {
            modeButton("Majeur", isMinor: false, width: width)
            modeButton("Mineur", isMinor: true, width: width)
        }
    }

    private func modeButton(_ title: String, isMinor: Bool, width: CGFloat) -> some View {
        let selected = isMinorMode == isMinor
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) { isMinorMode = isMinor }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(selected ? Color.white : C.ink2)
                .frame(width: width, height: 36)
                .background(selected ? C.coral : Color.white.opacity(0.5))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Grille de tonalités

    /// Même règle que partout ailleurs dans l'app : une largeur EXPLICITE par carte, jamais
    /// `.frame(maxWidth: .infinity)` sur deux voisines flexibles — voir `QuizView.choiceGrid`
    /// pour le bug précis que ce détour évite.
    private var cardWidth: CGFloat { (UIScreen.main.bounds.width - 48 - 12) / 2 }

    private var rows: [(MusicalKey, MusicalKey?)] {
        stride(from: 0, to: keys.count, by: 2).map { i in
            (keys[i], i + 1 < keys.count ? keys[i + 1] : nil)
        }
    }

    private func keyCard(_ key: MusicalKey) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedKey = key }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(key.name().capitalized)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(C.ink)
                Text(key.accidentalCount == 0 ? "Aucune altération"
                     : "\(key.accidentalCount) \(key.prefersFlats ? "bémol" : "dièse")\(key.accidentalCount > 1 ? "s" : "")")
                    .font(.system(size: 13))
                    .foregroundStyle(C.inkFaint)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            // La largeur se fixe ICI, sur le bouton complet (fond, padding compris) — pas sur
            // le `VStack` intérieur. Fixée plus tôt, elle ne comptait pas le padding ajouté
            // ensuite, et chaque carte débordait de `cardWidth` de 32 points au total : c'est
            // ce qui poussait la colonne de droite hors de l'écran.
            .frame(width: cardWidth, alignment: .leading)
            .liquidGlass(radius: 20, tint: .white)
        }
        .buttonStyle(.plain)
    }
}
