import SwiftUI
import CadenceCore

/// Le parcours d'UNE gamme, dans l'esprit d'un parcours d'apprentissage de langues : plusieurs
/// THÈMES (notes, intervalles, accords, armure, rapidité), et sous chacun PLUSIEURS niveaux reliés
/// par un chemin — pas un unique nœud par thème, pas des cercles isolés sans lien visuel entre
/// eux.
///
/// **Pourquoi chaque thème gère ses propres coordonnées, plutôt qu'un seul calcul pour tout le
/// parcours.** Le nombre de niveaux par thème est FIXE (`levelsPerTheme`), donc la hauteur et les
/// positions de ses nœuds se déduisent de constantes qu'on choisit soi-même — jamais d'un
/// `GeometryReader` qui mesurerait la mise en page après coup. C'est la même prudence que partout
/// ailleurs dans ce projet : ce SDK a, à deux reprises déjà, menti sur une taille mesurée depuis
/// l'intérieur d'un effet (`.glassEffect()`) ou d'une portée. En calculant les positions AVANT de
/// dessiner, le trait qui relie les nœuds tombe forcément juste, quoi qu'il arrive.
struct ScalePathView: View {
    let key: MusicalKey
    let onBack: () -> Void

    @Environment(AppStore.self) private var store
    @State private var activeNode: PathNode?
    @State private var completed: Set<String> = []

    struct PathNode: Identifiable, Hashable {
        let focus: ExerciseGenerator.ScaleFocus
        let level: Int // 0 = le nœud principal du thème, 1... = les niveaux suivants
        var id: String { "\(focus.rawValue)-\(level)" }
        var isThemeStart: Bool { level == 0 }
    }

    static let levelsPerTheme = 3
    static let themeOrder: [ExerciseGenerator.ScaleFocus] = [.notes, .intervals, .chords, .keySignature, .speed]

    var body: some View {
        ZStack(alignment: .top) {
            if let node = activeNode {
                QuizView()
                    // Le retour au parcours marque LE NIVEAU terminé — c'est le seul signal
                    // fiable qu'on ait : `store.isFinished` ne devient vrai qu'après la dernière
                    // bonne ou mauvaise réponse, jamais en cours de route.
                    .onChange(of: store.isFinished) { _, finished in
                        if finished { completed.insert(node.id) }
                    }
                    .transition(.opacity)
            } else {
                pathScroll
                    .transition(.opacity)
            }

            backButton {
                if activeNode != nil {
                    withAnimation(.easeInOut(duration: 0.2)) { activeNode = nil }
                } else {
                    onBack()
                }
            }
        }
    }

    // MARK: - Le chemin

    private var pathScroll: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 0) {
                header

                ForEach(Array(Self.themeOrder.enumerated()), id: \.1) { themeIndex, focus in
                    themeBanner(focus)
                    ThemeSection(focus: focus, themeIndex: themeIndex, key: key,
                                completed: completed, tint: color(for: focus), icon: icon(for: focus)) { node in
                        store.startScaleFocus(key: key, focus: node.focus)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { activeNode = node }
                    }
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 76)
            // Généreux à dessein : la barre du bas FLOTTE (elle vit dans le `safeAreaInset` de
            // `RootView`, pas dans le flux normal), donc rien n'empêche mécaniquement le dernier
            // nœud du chemin de défiler jusque sous elle si on lui laisse trop peu de marge.
            .padding(.bottom, 140)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Parcours").font(.system(size: 15)).foregroundStyle(C.ink2)
            Text(key.name().capitalized)
                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
        }
        .padding(.bottom, 12)
    }

    /// La bannière de thème — le repère visuel qui dit "voici un NOUVEAU groupe de niveaux",
    /// posée juste avant ses nœuds, dans la couleur de ce thème.
    private func themeBanner(_ focus: ExerciseGenerator.ScaleFocus) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon(for: focus))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(.white.opacity(0.22)))
            VStack(alignment: .leading, spacing: 2) {
                Text("THÈME").font(.system(size: 11, weight: .bold)).foregroundStyle(.white.opacity(0.8)).tracking(1)
                Text(focus.displayName).font(.system(size: 18, weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            Spacer()
        }
        .padding(16)
        .background(color(for: focus), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 32)
        .padding(.top, 28)
        .padding(.bottom, 6)
    }

    private func color(for focus: ExerciseGenerator.ScaleFocus) -> Color {
        switch focus {
        case .notes: C.apricot
        case .intervals: C.coral
        case .chords: C.lilac
        case .keySignature: C.ink2
        case .speed: C.good
        }
    }

    /// Un logo par catégorie qui se lit sans avoir besoin du libellé à côté : des touches de
    /// piano pour les accords (pas un simple empilement abstrait), un drapeau numéroté pour
    /// l'armure (l'idée de "compter" les altérations), une distance à deux flèches pour
    /// l'intervalle — chacun renvoie à UNE seule idée, pas à la musique en général.
    private func icon(for focus: ExerciseGenerator.ScaleFocus) -> String {
        switch focus {
        case .notes: "music.note.list"
        case .intervals: "arrow.up.arrow.down"
        case .chords: "pianokeys"
        case .keySignature: "number.square.fill"
        case .speed: "bolt.fill"
        }
    }

    // MARK: - Retour

    private func backButton(_ action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(C.ink)
                    .frame(width: 40, height: 40)
                    .liquidGlass(radius: 20)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}

/// Les `levelsPerTheme` nœuds d'UN thème, reliés par un vrai chemin — positions calculées une
/// fois, PAS mesurées, pour que le trait qui les relie tombe exactement sur leurs centres.
private struct ThemeSection: View {
    let focus: ExerciseGenerator.ScaleFocus
    let themeIndex: Int
    let key: MusicalKey
    let completed: Set<String>
    let tint: Color
    let icon: String
    let onSelect: (ScalePathView.PathNode) -> Void

    private let primaryDiameter: CGFloat = 76
    private let secondaryDiameter: CGFloat = 58
    private let gap: CGFloat = 128

    /// Largeur de travail — mesurée une seule fois depuis l'écran, jamais via un `GeometryReader`
    /// interne : même convention que `QuizView.contentWidth` et `ScalesView.cardWidth`.
    private var sectionWidth: CGFloat { UIScreen.main.bounds.width - 48 }
    private var amplitude: CGFloat { sectionWidth * 0.26 }
    private var centerX: CGFloat { sectionWidth / 2 }
    /// Alterne le sens du serpentin d'un thème à l'autre, pour que le chemin continue de zigzaguer
    /// au lieu de repartir identique à chaque bannière.
    private var direction: CGFloat { themeIndex.isMultiple(of: 2) ? 1 : -1 }

    private var nodes: [ScalePathView.PathNode] {
        (0..<ScalePathView.levelsPerTheme).map { .init(focus: focus, level: $0) }
    }

    /// Marge du haut égale au rayon du halo du plus gros nœud : sans elle, la moitié supérieure de
    /// son anneau en pointillés se ferait couper par le bord de ce `ZStack`, `.position()` plaçant
    /// son CENTRE et non son coin — un cercle centré en y=0 déborderait pour moitié hors cadre.
    private var topInset: CGFloat { (primaryDiameter + 20) / 2 }

    /// Centre de chaque nœud, dans l'ordre — la MÊME fonction sert à positionner les cercles et à
    /// tracer le trait qui les relie, donc les deux ne peuvent pas diverger.
    private func center(for level: Int) -> CGPoint {
        switch level {
        case 0: CGPoint(x: centerX, y: topInset)
        case 1: CGPoint(x: centerX + direction * amplitude, y: topInset + gap)
        default: CGPoint(x: centerX - direction * amplitude, y: topInset + gap * 1.85)
        }
    }

    private var sectionHeight: CGFloat { topInset + gap * 1.85 + (secondaryDiameter + 20) / 2 + 12 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            connectingPath
            ForEach(nodes) { node in
                nodeButton(node)
                    .position(center(for: node.level))
            }
        }
        .frame(width: sectionWidth, height: sectionHeight)
        .padding(.vertical, 8)
    }

    /// Le vrai chemin qui manquait — un ruban en pointillés qui serpente d'un nœud à l'autre,
    /// dessiné EN DESSOUS d'eux (premier dans le `ZStack`), sur des courbes plutôt que des
    /// segments droits pour rester dans l'esprit "sentier", pas "diagramme".
    private var connectingPath: some View {
        Path { path in
            let p0 = center(for: 0), p1 = center(for: 1), p2 = center(for: 2)
            path.move(to: p0)
            path.addQuadCurve(to: p1, control: CGPoint(x: (p0.x + p1.x) / 2, y: (p0.y + p1.y) / 2))
            path.addQuadCurve(to: p2, control: CGPoint(x: (p1.x + p2.x) / 2, y: (p1.y + p2.y) / 2))
        }
        .stroke(tint.opacity(0.4), style: StrokeStyle(lineWidth: 6, lineCap: .round, dash: [1, 20]))
    }

    private func nodeButton(_ node: ScalePathView.PathNode) -> some View {
        let isDone = completed.contains(node.id)
        let isPrimary = node.level == 0
        let diameter = isPrimary ? primaryDiameter : secondaryDiameter

        return Button {
            onSelect(node)
        } label: {
            ZStack {
                // Les TRAITS autour du nœud — un halo en pointillés qui dit "il y a plusieurs
                // passages possibles ici", pas juste un cercle plein isolé.
                Circle()
                    .stroke(tint.opacity(0.32), style: StrokeStyle(lineWidth: 5, dash: [2, 12]))
                    .frame(width: diameter + 20, height: diameter + 20)

                Circle().fill(isPrimary ? tint : tint.opacity(0.6)).frame(width: diameter, height: diameter)
                Image(systemName: levelIcon(node))
                    .font(.system(size: isPrimary ? 28 : 20, weight: .semibold))
                    .foregroundStyle(.white)
                if isDone {
                    Circle().strokeBorder(.white, lineWidth: 3).frame(width: diameter, height: diameter)
                }
            }
            .liquidGlass(radius: (diameter + 20) / 2, tint: tint)
            .overlay(alignment: .topTrailing) {
                if isDone {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: isPrimary ? 20 : 16))
                        .foregroundStyle(C.good)
                        .background(Circle().fill(.white))
                        .offset(x: 6, y: -2)
                }
            }
            .overlay(alignment: .bottom) {
                if isPrimary {
                    Text(node.focus.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(C.ink)
                        .fixedSize()
                        .offset(y: diameter / 2 + 30)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Un logo différent par NIVEAU, pas seulement par thème — comme un parcours de langue mêle
    /// plusieurs formats sur la même compétence : le nœud principal porte l'icône du thème, le
    /// second une reprise, le troisième un défi.
    private func levelIcon(_ node: ScalePathView.PathNode) -> String {
        guard node.level != 0 else { return icon }
        return node.level == 1 ? "arrow.triangle.2.circlepath" : "star.fill"
    }
}
