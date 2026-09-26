import SwiftUI
import CadenceCore

/// Le parcours d'UNE gamme : cinq arrêts, chacun une compétence à part — pas un unique quiz qui
/// mélangerait notes, intervalles et accords sans qu'on sache lequel on travaille. Inspiré des
/// parcours en chemin sinueux qu'on trouve dans les applications d'apprentissage de langues :
/// une suite d'étapes qu'on débloque en avançant, plutôt qu'une liste plate.
///
/// **Pourquoi cinq nœuds fixes plutôt qu'un chemin généré.** Le nombre et l'ordre des étapes ne
/// varient jamais d'une gamme à l'autre — seul leur CONTENU change (`ExerciseGenerator.scaleExercises`
/// s'en charge). Un parcours dont la forme est stable est plus facile à retenir visuellement
/// qu'un chemin recalculé à chaque fois.
struct ScalePathView: View {
    let key: MusicalKey
    let onBack: () -> Void

    @Environment(AppStore.self) private var store
    @State private var activeFocus: ExerciseGenerator.ScaleFocus?
    @State private var completed: Set<ExerciseGenerator.ScaleFocus> = []

    private static let order: [ExerciseGenerator.ScaleFocus] = [.notes, .intervals, .chords, .keySignature, .speed]

    var body: some View {
        ZStack(alignment: .top) {
            if let focus = activeFocus {
                QuizView()
                    // Le retour au parcours marque l'étape terminée — c'est le SEUL signal fiable
                    // qu'on ait : `store.isFinished` ne devient vrai qu'après la dernière bonne
                    // ou mauvaise réponse, jamais en cours de route.
                    .onChange(of: store.isFinished) { _, finished in
                        if finished { completed.insert(focus) }
                    }
                    .transition(.opacity)
            } else {
                pathScroll
                    .transition(.opacity)
            }

            backButton {
                if activeFocus != nil {
                    withAnimation(.easeInOut(duration: 0.2)) { activeFocus = nil }
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

                ForEach(Array(Self.order.enumerated()), id: \.1) { index, focus in
                    node(focus, index: index)
                }

                Spacer(minLength: 40)
            }
            .padding(.top, 76)
            .padding(.bottom, 40)
        }
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Parcours").font(.system(size: 15)).foregroundStyle(C.ink2)
            Text(key.name().capitalized)
                .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
        }
        .padding(.bottom, 24)
    }

    /// Un nœud sur deux décalé à gauche ou à droite — le zigzag classique d'un parcours, obtenu
    /// avec un simple `Spacer` de part et d'autre plutôt qu'un positionnement absolu mesuré : pas
    /// de `GeometryReader` ici, seulement une alternance déterministe sur l'index.
    private func node(_ focus: ExerciseGenerator.ScaleFocus, index: Int) -> some View {
        let isEven = index % 2 == 0
        return HStack(spacing: 0) {
            if !isEven { Spacer() }
            nodeButton(focus)
            if isEven { Spacer() }
        }
        .padding(.horizontal, 56)
        .padding(.vertical, 14)
    }

    private func nodeButton(_ focus: ExerciseGenerator.ScaleFocus) -> some View {
        let tint = color(for: focus)
        let isDone = completed.contains(focus)

        return Button {
            store.startScaleFocus(key: key, focus: focus)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { activeFocus = focus }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle().fill(tint).frame(width: 72, height: 72)
                    Image(systemName: icon(for: focus))
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                    if isDone {
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                            .frame(width: 72, height: 72)
                    }
                }
                .liquidGlass(radius: 36, tint: tint)
                .overlay(alignment: .topTrailing) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(C.good)
                            .background(Circle().fill(.white))
                            .offset(x: 4, y: -4)
                    }
                }

                Text(focus.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(C.ink)
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
