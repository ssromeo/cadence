import SwiftUI
import CadenceCore

enum RootTab: Hashable { case home, quiz, scales }

struct RootView: View {
    @State private var store = AppStore()
    @State private var midi = MIDIConnectionManager()
    @State private var tab: RootTab = .home
    #if DEBUG
    /// Trace du crochet de vérification visuelle — `print()` ne remonte pas de façon fiable
    /// depuis `xcrun simctl launch` (ni via `--stdout`, ni via `log stream`), donc affichée
    /// directement à l'écran pour rester capturable par une simple capture d'écran, exactement
    /// comme le reste de ce crochet.
    @State private var debugTrace: String = ""
    #endif

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
        .environment(midi)
        #if DEBUG
        .overlay(alignment: .top) {
            if !debugTrace.isEmpty {
                Text(debugTrace)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(8)
                    .frame(maxWidth: .infinity)
                    .background(.black.opacity(0.85))
                    .allowsHitTesting(false)
            }
        }
        #endif
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
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                debugTrace = "pas de dossier Documents"; return
            }
            let allFiles = (try? FileManager.default.contentsOfDirectory(at: docs, includingPropertiesForKeys: nil)) ?? []
            guard let file = allFiles.first(where: { $0.pathExtension.lowercased().hasPrefix("mid") }) else {
                debugTrace = "docs=\(docs.path)\nfichiers=\(allFiles.map(\.lastPathComponent))\naucun .mid trouvé"
                return
            }
            guard let data = try? Data(contentsOf: file) else {
                debugTrace = "impossible de lire \(file.path)"; return
            }
            debugTrace = "import de \(file.lastPathComponent), \(data.count) octets…"
            store.importMIDI(from: data, fileName: file.lastPathComponent)
            // "musicpath" : reste sur Accueil et laisse `HomeView` révéler SEUL le parcours dès
            // que l'analyse aboutit (voir son `.onChange(of: store.importState)`) — c'est
            // exactement ce chemin-là qu'on veut vérifier par capture d'écran, pas le raccourci
            // direct vers l'onglet Exercices que prend tout autre mode.
            if mode == "musicpath" {
                var waited = 0
                while store.musicPath == nil {
                    if case .failed(let message) = store.importState {
                        debugTrace = "import échoué : \(message)"; return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                    waited += 1
                    if waited > 100 {
                        debugTrace = "délai dépassé (10s) — importState=\(store.importState)"
                        return
                    }
                }
                debugTrace = ""
                return
            }
            // "musicpath:<thème>" : saute directement DANS un thème précis du parcours d'un
            // morceau importé, sur l'onglet Exercices brut (sans le chrome de `MusicPathView`) —
            // reproduit exactement le chemin "onglet Exercices après avoir choisi un thème",
            // celui que la barre du bas montre une fois qu'on en a quitté un.
            if mode.hasPrefix("musicpath:") {
                let focusRaw = String(mode.dropFirst("musicpath:".count))
                while store.musicPath == nil { try? await Task.sleep(for: .milliseconds(50)) }
                guard let path = store.musicPath,
                      let theme = path.themes.first(where: { $0.focus.rawValue == focusRaw }) else { return }
                store.startImportedMusicFocus(theme)
                tab = .quiz
                return
            }
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
