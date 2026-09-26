import SwiftUI
import CadenceCore

/// L'écran d'exercice — UNIQUE, quel que soit le type d'exercice tiré au sort. Un intervalle,
/// un accord, un degré de gamme, le nom d'une note ou le nombre d'altérations d'une armure se
/// jouent tous de la même façon : une question, éventuellement une portée, quatre choix, une
/// correction. Voir `GeneratedExercise` côté Core pour le raisonnement complet — c'est cette
/// abstraction qui évite d'avoir à écrire un écran par type d'exercice.
struct QuizView: View {
    @Environment(AppStore.self) private var store
    @State private var selected: Int?

    var body: some View {
        ZStack {
            AppBackground()

            if store.exercises.isEmpty {
                emptyState
            } else if store.isFinished {
                ScoreView(score: store.score, total: store.exercises.count) {
                    store.restartSession()
                    selected = nil
                }
            } else if let exercise = store.currentExercise {
                content(for: exercise)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "pianokeys").font(.system(size: 40)).foregroundStyle(C.inkFaint)
            Text("Importe un morceau ou choisis une gamme")
                .font(.system(size: 17, weight: .medium)).foregroundStyle(C.ink2)
        }
    }

    private func content(for exercise: GeneratedExercise) -> some View {
        VStack(spacing: 0) {
            progressBar
                .padding(.top, 8)

            Spacer(minLength: 20)

            VStack(spacing: 18) {
                Text(exercise.prompt)
                    .font(.system(size: 15)).foregroundStyle(C.ink2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)

                // Certains exercices (l'armure, par exemple) ne portent aucune note à afficher —
                // la question se suffit à elle-même. Les autres montrent LA PORTÉE, pas l'oreille :
                // voir `StaffView`, lire est une compétence à part, distincte de l'audition.
                if !exercise.notes.isEmpty, let key = store.displayKey {
                    StaffView(pitches: exercise.notes, key: key, stacked: exercise.stacked,
                             width: contentWidth, height: 120)
                        .padding(.horizontal, 8)
                        .liquidGlass(radius: 20)
                }

                if let selected {
                    let correct = exercise.isCorrect(selected)
                    Text(correct ? "Bonne réponse — \(exercise.choices[exercise.correctIndex])"
                                  : "C'était \(exercise.choices[exercise.correctIndex])")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(correct ? C.good : C.bad)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }

            Spacer(minLength: 20)

            choiceGrid(for: exercise)

            if selected != nil {
                nextButton
                    .padding(.top, 14)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 24)
        .onChange(of: store.currentExerciseIndex) { _, _ in selected = nil }
    }

    /// Largeur utile de l'écran, une fois retirée la marge horizontale de 24 pt appliquée deux
    /// fois par ce `VStack`. Un iPhone est le seul appareil visé (voir `TARGETED_DEVICE_FAMILY`
    /// dans `project.yml`), donc `UIScreen.main` est fiable : une seule fenêtre, pas de
    /// redimensionnement à gérer comme sur iPad.
    private var contentWidth: CGFloat { UIScreen.main.bounds.width - 48 }

    // MARK: – Progression

    private var progressBar: some View {
        HStack(spacing: 5) {
            ForEach(store.exercises.indices, id: \.self) { i in
                Capsule()
                    .fill(i < store.currentExerciseIndex ? C.coral
                          : i == store.currentExerciseIndex ? C.ink.opacity(0.5) : C.line)
                    .frame(height: 5)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.currentExerciseIndex)
    }

    // MARK: – Choix

    /// Grille à deux colonnes, montée à la main en `HStack`/`VStack`, chaque bouton à une
    /// LARGEUR CALCULÉE — jamais `.frame(maxWidth: .infinity)`.
    ///
    /// **Le bug que ce détour évite.** Deux boutons posés côte à côte dans un `HStack`, chacun
    /// avec un `Text` en `.frame(maxWidth: .infinity)`, affichent tous les deux une capsule
    /// VIDE — l'emplacement est bien réservé, à la bonne taille, mais aucun glyphe n'est peint.
    /// Un seul bouton de la paire, isolé, affiche son texte sans problème ; c'est la négociation
    /// de largeur entre deux voisins également flexibles qui casse le rendu du `Text`. En donnant
    /// à chaque bouton une largeur EXPLICITE, calculée depuis la largeur d'écran plutôt que
    /// négociée entre voisins, le texte s'affiche systématiquement. Règle permanente du projet :
    /// à appliquer à TOUTE nouvelle rangée de boutons multiples.
    private func choiceGrid(for exercise: GeneratedExercise) -> some View {
        let buttonWidth = (contentWidth - 12) / 2
        let pairs = stride(from: 0, to: exercise.choices.count, by: 2).map { i in
            (i, exercise.choices[i], i + 1 < exercise.choices.count ? i + 1 : nil)
        }
        return VStack(spacing: 12) {
            ForEach(pairs, id: \.0) { firstIndex, firstText, secondIndex in
                HStack(spacing: 12) {
                    choiceButton(index: firstIndex, text: firstText, exercise: exercise, width: buttonWidth)
                    if let secondIndex {
                        choiceButton(index: secondIndex, text: exercise.choices[secondIndex],
                                    exercise: exercise, width: buttonWidth)
                    }
                }
            }
        }
    }

    private func choiceButton(index: Int, text: String, exercise: GeneratedExercise,
                              width: CGFloat) -> some View {
        let isSelected = selected == index
        let isCorrectChoice = index == exercise.correctIndex
        // Une fois répondu, la bonne réponse se révèle même si elle n'a pas été cliquée — c'est
        // ce qui transforme une erreur en apprentissage plutôt qu'en simple sanction.
        let revealCorrect = selected != nil && isCorrectChoice
        let revealWrong = selected != nil && isSelected && !isCorrectChoice

        return Button {
            guard selected == nil else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { selected = index }
            store.answer(index)
        } label: {
            Text(text)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(C.ink)
                .frame(width: width)
                .padding(.vertical, 16)
                .liquidGlass(radius: 18, tint: revealCorrect ? C.good : revealWrong ? C.bad : .white)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(revealCorrect ? C.good : revealWrong ? C.bad : .clear, lineWidth: 2)
                }
        }
        .buttonStyle(.plain)
        .disabled(selected != nil)
    }

    private var nextButton: some View {
        Button {
            withAnimation(.easeOut(duration: 0.25)) { store.advanceToNextExercise() }
        } label: {
            Text(store.currentExerciseIndex == store.exercises.count - 1 ? "Voir le score" : "Question suivante")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: contentWidth)
                .padding(.vertical, 16)
                .background(C.ink, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct ScoreView: View {
    let score: Int
    let total: Int
    let onRestart: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            LivingOrb().clipShape(Circle()).frame(width: 140, height: 140)
            Text("\(score) / \(total)")
                .font(.system(size: 44, weight: .heavy, design: .rounded)).foregroundStyle(C.ink)
            Text(score == total ? "Sans faute sur cette série."
                                 : "Ces mêmes notions reviendront, dans un autre ordre.")
                .font(.system(size: 15)).foregroundStyle(C.ink2)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button(action: onRestart) {
                Text("Recommencer").font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(C.ink)
                    .padding(.horizontal, 28).padding(.vertical, 14)
                    .liquidGlass(radius: 24, tint: C.apricot)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
    }
}
