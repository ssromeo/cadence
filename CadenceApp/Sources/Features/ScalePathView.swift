import SwiftUI
import CadenceCore

/// Le parcours d'UNE gamme, dans l'esprit d'un parcours d'apprentissage de langues : plusieurs
/// THÈMES (notes, intervalles, accords, armure, rapidité), et sous chacun PLUSIEURS niveaux —
/// pas un unique nœud par thème. Le gros cercle avec l'icône ouvre le thème ; les petites étoiles
/// qui suivent sont d'autres passages sur la MÊME compétence, un peu plus loin sur le chemin —
/// exactement le principe d'une unité qui contient plusieurs leçons avant la suivante.
///
/// **Pourquoi le contenu de chaque niveau n'est pas figé à l'avance.** `ExerciseGenerator`
/// tire un jeu d'exercices différent à chaque appel (mélange aléatoire) — rejouer un niveau
/// déjà terminé propose donc naturellement une autre série, jamais du par-cœur sur le même jeu
/// de questions.
struct ScalePathView: View {
    let key: MusicalKey
    let onBack: () -> Void

    @Environment(AppStore.self) private var store
    @State private var activeNode: PathNode?
    @State private var completed: Set<String> = []

    private struct PathNode: Identifiable, Hashable {
        let focus: ExerciseGenerator.ScaleFocus
        let level: Int // 0 = le nœud principal du thème, 1... = les niveaux suivants
        var id: String { "\(focus.rawValue)-\(level)" }
        var isThemeStart: Bool { level == 0 }
    }

    private static let levelsPerTheme = 3
    private static let themeOrder: [ExerciseGenerator.ScaleFocus] = [.notes, .intervals, .chords, .keySignature, .speed]
    private static let allNodes: [PathNode] = themeOrder.flatMap { focus in
        (0..<levelsPerTheme).map { PathNode(focus: focus, level: $0) }
    }

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

                ForEach(Array(Self.allNodes.enumerated()), id: \.1.id) { index, node in
                    if node.isThemeStart {
                        themeBanner(node.focus)
                    }
                    pathRow(node, index: index)
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 76)
            // Généreux à dessein : la barre du bas FLOTTE (elle vit dans le `safeAreaInset` de
            // `RootView`, pas dans le flux normal), donc rien n'empêche mécaniquement le dernier
            // nœud du chemin de défiler jusque sous elle si on lui laisse trop peu de marge — un
            // calcul au plus juste s'était déjà révélé insuffisant à l'usage.
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
    /// posée juste avant son nœud principal, dans la couleur de ce thème.
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

    /// Un nœud sur deux décalé à gauche ou à droite — le zigzag classique d'un parcours, obtenu
    /// avec un simple `Spacer` de part et d'autre plutôt qu'un positionnement absolu mesuré : pas
    /// de `GeometryReader` ici, seulement une alternance déterministe sur l'index GLOBAL (le
    /// zigzag continue d'un thème à l'autre, il ne redémarre pas à chaque bannière).
    private func pathRow(_ node: PathNode, index: Int) -> some View {
        let isEven = index % 2 == 0
        return HStack(spacing: 0) {
            if !isEven { Spacer() }
            nodeButton(node)
            if isEven { Spacer() }
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 12)
    }

    private func nodeButton(_ node: PathNode) -> some View {
        let tint = color(for: node.focus)
        let isDone = completed.contains(node.id)
        let isPrimary = node.level == 0
        let diameter: CGFloat = isPrimary ? 72 : 56

        return Button {
            store.startScaleFocus(key: key, focus: node.focus)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { activeNode = node }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(isPrimary ? tint : tint.opacity(0.55)).frame(width: diameter, height: diameter)
                    Image(systemName: isPrimary ? icon(for: node.focus) : "star.fill")
                        .font(.system(size: isPrimary ? 26 : 18, weight: .semibold))
                        .foregroundStyle(.white)
                    if isDone {
                        Circle().strokeBorder(.white, lineWidth: 3).frame(width: diameter, height: diameter)
                    }
                }
                .liquidGlass(radius: diameter / 2, tint: tint)
                .overlay(alignment: .topTrailing) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: isPrimary ? 20 : 16))
                            .foregroundStyle(C.good)
                            .background(Circle().fill(.white))
                            .offset(x: 4, y: -4)
                    }
                }

                // Seul le nœud principal porte le libellé — les niveaux suivants d'un même
                // thème se reconnaissent déjà à leur couleur et à leur proximité du gros nœud,
                // pas besoin de répéter "Notes" trois fois de suite.
                if isPrimary {
                    Text(node.focus.displayName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(C.ink)
                }
            }
        }
        .buttonStyle(.plain)
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

    private func icon(for focus: ExerciseGenerator.ScaleFocus) -> String {
        switch focus {
        case .notes: "music.note"
        case .intervals: "arrow.up.arrow.down"
        case .chords: "square.stack.3d.up.fill"
        case .keySignature: "flag.fill"
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
