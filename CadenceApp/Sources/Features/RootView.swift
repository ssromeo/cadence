import SwiftUI

enum RootTab: Hashable { case home, quiz, scales }

struct RootView: View {
    @State private var store = AppStore()
    @State private var tab: RootTab = .home

    var body: some View {
        Group {
            switch tab {
            case .home:
                HomeView(selectedTab: $tab)
                    .transition(.opacity)
            case .quiz:
                QuizView()
                    .transition(.opacity)
            case .scales:
                ScalesView()
                    .transition(.opacity)
            }
        }
        // PAS de `.animation(value: tab)` ici en plus du `withAnimation` posé sur chaque bouton
        // de `navItem` — les deux ensemble faisaient tourner DEUX animations concurrentes sur le
        // même changement d'état (l'une déclenchée implicitement par ce modificateur, l'autre
        // explicitement par `withAnimation`), qui se marchaient dessus : la transition sautait
        // ou clignotait au lieu de fondre proprement. Une SEULE source d'animation par
        // changement d'onglet, posée au point où `tab` change réellement — jamais les deux à
        // la fois — et le fondu (`.opacity` seul, pas de `.scale`) reste net dans tous les cas.
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

    /// Barre du bas, en pilule — trois destinations : l'accueil (importer), les exercices
    /// générés, et les gammes (le pilier "pas de MIDI"). La courante se distingue par une
    /// pastille plus sombre, pas par un simple changement de couleur d'icône — plus facile à
    /// repérer en un coup d'œil, sans avoir à lire le libellé.
    private var navBar: some View {
        HStack(spacing: 4) {
            navItem(.home, icon: "house.fill", label: "Accueil")
            navItem(.quiz, icon: "sparkles.rectangle.stack.fill", label: "Exercices")
            navItem(.scales, icon: "tuningfork", label: "Gammes")
        }
        .padding(6)
        .liquidGlass(radius: 30)
    }

    private func navItem(_ target: RootTab, icon: String, label: String) -> some View {
        let isActive = tab == target
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { tab = target }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 15, weight: .semibold))
                if isActive {
                    Text(label).font(.system(size: 15, weight: .semibold))
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
            }
            .foregroundStyle(C.ink)
            .padding(.horizontal, isActive ? 18 : 14)
            .padding(.vertical, 14)
            .background {
                if isActive { Capsule().fill(C.creamDeep) }
            }
        }
        .buttonStyle(.plain)
    }
}
