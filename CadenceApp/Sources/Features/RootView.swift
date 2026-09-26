import SwiftUI
import CadenceCore

enum RootTab: Hashable { case home, quiz, scales }

struct RootView: View {
    @State private var store = AppStore()
    @State private var tab: RootTab = .home

    var body: some View {
        // LES TROIS ÉCRANS RESTENT MONTÉS EN PERMANENCE — seule leur opacité bascule. La version
        // précédente les faisait apparaître/disparaître via un `switch`, ce qui les détruit et
        // les reconstruit à chaque passage : `HomeView` en particulier héberge `LivingOrb`, un
        // shader Metal animé image par image, dont le pipeline doit se recompiler/se relier à
        // chaque reconstruction — c'est CE coût, pas l'animation elle-même, qui rendait le
        // changement d'onglet saccadé. En gardant les trois vues vivantes et en ne faisant varier
        // que leur opacité (plus `allowsHitTesting` pour qu'une vue invisible n'intercepte plus
        // les touchers), plus aucune reconstruction n'a jamais lieu après le premier lancement.
        ZStack {
            HomeView(selectedTab: $tab)
                .opacity(tab == .home ? 1 : 0)
                .allowsHitTesting(tab == .home)
            QuizView()
                .opacity(tab == .quiz ? 1 : 0)
                .allowsHitTesting(tab == .quiz)
            ScalesView()
                .opacity(tab == .scales ? 1 : 0)
                .allowsHitTesting(tab == .scales)
        }
        .animation(.easeInOut(duration: 0.2), value: tab)
        .environment(store)
        // Crochet de VÉRIFICATION VISUELLE uniquement — jamais construit en release. Il importe
        // automatiquement un fichier déposé dans Documents et bascule sur les exercices, pour
        // capturer des captures d'écran déterministes sans avoir à simuler des appuis.
        #if DEBUG
        .task {
            guard let mode = ProcessInfo.processInfo.environment["CADENCE_PREVIEW_QUIZ"] else { return }
            if mode == "scales" {
                tab = .scales
                return
            }
            // Saute directement dans UNE étape précise du parcours d'une gamme, sans avoir à
            // simuler les appuis qui y mènent — utile pour vérifier un type d'exercice précis
            // (mi majeur, choisi arbitrairement, sert juste de tonalité de test). Un suffixe
            // ":right" ou ":wrong" répond en plus À LA PLACE d'un appui, pour vérifier l'état
            // "déjà répondu" (la couleur de la barre de progression, notamment) par capture
            // d'écran plutôt qu'en simulant un tap dont les coordonnées ne sont pas fiables sur
            // un simulateur dont la fenêtre peut bouger.
            if mode.hasPrefix("focus:") {
                let rest = String(mode.dropFirst(6))
                let parts = rest.split(separator: ":", maxSplits: 1)
                guard let focus = ExerciseGenerator.ScaleFocus(rawValue: String(parts[0])) else { return }
                store.startScaleFocus(key: MusicalKey(tonicPitchClass: 4, isMajor: true), focus: focus)
                if parts.count > 1, let exercise = store.currentExercise {
                    if parts[1] == "right" {
                        store.answer(exercise.correctIndex)
                    } else if parts[1] == "wrong" {
                        store.answer((exercise.correctIndex + 1) % exercise.choices.count)
                    }
                }
                tab = .quiz
                return
            }
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
                  let file = try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil).first(where: { $0.pathExtension.lowercased().hasPrefix("mid") }),
                  let data = try? Data(contentsOf: file) else { return }
            store.importMIDI(from: data, fileName: file.lastPathComponent)
            while !store.isFinished, store.exercises.isEmpty { try? await Task.sleep(for: .milliseconds(50)) }
            tab = .quiz
        }
        #endif
        // RÉSERVÉE, pas superposée. La barre vivait dans un `ZStack(alignment: .bottom)`, donc
        // rien n'empêchait le contenu de continuer SOUS elle. Un `safeAreaInset` retire
        // mécaniquement sa hauteur de l'espace disponible pour le contenu : aucun écran, présent
        // ou futur, ne peut plus se faire manger par la barre.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            navBar.padding(.bottom, 8)
        }
    }

    /// Barre du bas, façon Liquid Glass : icône AU-DESSUS du libellé, les trois toujours
    /// visibles — plus d'accordéon qui n'affichait le texte que sur l'onglet actif. Celui-ci se
    /// distingue par la couleur (bleu système) et une pastille neutre derrière lui, jamais par
    /// une mise en page qui change de forme d'un onglet à l'autre.
    private var navBar: some View {
        // LARGEUR EXPLICITE par onglet, jamais `.frame(maxWidth: .infinity)` sur des voisins
        // dans ce `HStack` — même règle que partout ailleurs dans le projet (voir
        // `QuizView.choiceGrid`) : plusieurs `Button{Text}` flexibles voisins se sont déjà
        // affichés vides sur ce SDK.
        let barWidth = UIScreen.main.bounds.width - 48
        let tabWidth = (barWidth - 12) / 3
        return HStack(spacing: 6) {
            navItem(.home, icon: "house", label: "Accueil", width: tabWidth)
            navItem(.quiz, icon: "sparkles.rectangle.stack", label: "Exercices", width: tabWidth)
            navItem(.scales, icon: "tuningfork", label: "Gammes", width: tabWidth)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .liquidGlass(radius: 30, tint: .white)
    }

    private func navItem(_ target: RootTab, icon: String, label: String, width: CGFloat) -> some View {
        let isActive = tab == target
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = target }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon).font(.system(size: 20, weight: isActive ? .semibold : .regular))
                Text(label).font(.system(size: 11, weight: isActive ? .semibold : .medium))
            }
            .foregroundStyle(isActive ? C.navActive : C.ink2)
            .frame(width: width)
            .padding(.vertical, 10)
            .background {
                if isActive {
                    Capsule().fill(C.line)
                        .transition(.opacity)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
