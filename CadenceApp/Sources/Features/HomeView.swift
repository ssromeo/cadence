import SwiftUI
import UniformTypeIdentifiers
import CadenceCore

struct HomeView: View {
    @Environment(AppStore.self) private var store
    @State private var showImporter = false
    @Binding var selectedTab: RootTab

    private static let midiTypes: [UTType] = {
        [UTType(filenameExtension: "mid"), UTType(filenameExtension: "midi"), .data]
            .compactMap { $0 }
    }()

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                header
                Spacer(minLength: 8)

                LivingOrb()
                    .frame(width: 260, height: 260)
                    .shadow(color: C.coral.opacity(0.28), radius: 36, y: 18)

                Spacer(minLength: 8)

                statusText
                    .padding(.top, 8)

                Spacer(minLength: 24)

                actionRow
                    .padding(.bottom, 12)

                footNote
            }
            // `maxHeight: .infinity` est ce qui manquait : sans lui, ce `VStack` ne prend que
            // la hauteur de son contenu et se retrouve CENTRÉ par le `ZStack` parent — ce qui
            // pouvait pousser `footNote` juste assez bas pour chevaucher la barre de navigation
            // réservée par `safeAreaInset` dans `RootView`. En s'étirant explicitement sur toute
            // la hauteur disponible, le contenu se répartit sur SON espace propre, jamais sur
            // celui de la barre.
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: Self.midiTypes) { result in
            guard case .success(let url) = result else { return }
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            store.importMIDI(from: data, fileName: url.lastPathComponent)
        }
    }

    // MARK: – En-tête

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(C.coral).frame(width: 10, height: 10)
                Text("cadence").font(.system(size: 22, weight: .heavy, design: .rounded)).foregroundStyle(C.ink)
            }
            Spacer()
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(C.ink)
                .frame(width: 40, height: 40)
                .liquidGlass(radius: 20)
        }
    }

    // MARK: – Statut

    @ViewBuilder
    private var statusText: some View {
        switch store.importState {
        case .empty:
            VStack(spacing: 6) {
                Text("Prêt quand tu l'es").font(.system(size: 15)).foregroundStyle(C.ink2)
                Text("Importe un morceau").font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
                Text("Un fichier MIDI depuis ton appareil, jamais envoyé ailleurs.")
                    .font(.system(size: 14)).foregroundStyle(C.inkFaint)
                    .multilineTextAlignment(.center)
            }
        case .analyzing(let progress):
            VStack(spacing: 14) {
                Text("Analyse en cours…")
                    .font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(C.ink)
                // Barre de progression EXPLICITE plutôt qu'une roue qui tourne sans fin visible :
                // sur un fichier de plusieurs milliers de notes, quelques centaines de
                // millisecondes suffisent à se demander si l'app a figé.
                ProgressView(value: progress)
                    .tint(C.coral)
                    .frame(width: 180)
                    .animation(.easeOut(duration: 0.3), value: progress)
            }
        case .ready(let fileName, let noteCount, let key):
            VStack(spacing: 6) {
                Text(fileName).font(.system(size: 15)).foregroundStyle(C.ink2).lineLimit(1)
                Text(key.name().capitalized)
                    .font(.system(size: 30, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
                Text("\(noteCount) notes détectées")
                    .font(.system(size: 14)).foregroundStyle(C.inkFaint)
            }
        case .failed(let message):
            VStack(spacing: 6) {
                Text("Import impossible").font(.system(size: 22, weight: .semibold, design: .rounded)).foregroundStyle(C.bad)
                Text(message).font(.system(size: 14)).foregroundStyle(C.inkFaint).multilineTextAlignment(.center)
            }
        }
    }

    // MARK: – Actions

    private var actionRow: some View {
        HStack(spacing: 30) {
            GlassIconLabel(systemImage: "waveform", label: "Analyse")

            Button { showImporter = true } label: {
                GlassIconLabel(systemImage: "tray.and.arrow.down.fill", label: "Importer",
                              tint: C.coral, prominent: true)
            }
            .buttonStyle(.plain)

            Button {
                guard case .ready = store.importState, !store.exercises.isEmpty else { return }
                selectedTab = .quiz
            } label: {
                GlassIconLabel(systemImage: "sparkles.rectangle.stack.fill", label: "Exercices")
            }
            .buttonStyle(.plain)
            .opacity(store.exercises.isEmpty ? 0.4 : 1)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.importState)
    }

    private var footNote: some View {
        VStack(spacing: 2) {
            Text(store.exercises.isEmpty ? "Aucun morceau chargé" : "\(store.exercises.count) exercices prêts à réviser")
                .font(.system(size: 13)).foregroundStyle(C.inkFaint)
        }
        .padding(.bottom, 4)
    }
}
