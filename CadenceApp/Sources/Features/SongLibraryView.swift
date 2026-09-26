import SwiftUI
import CadenceCore

/// La bibliothèque des morceaux déjà importés, persistée sur disque (voir
/// `CadenceCore.SongLibraryStore`) — accessible depuis `QuizView` via le bouton "Mes chansons".
/// Sans cet écran, importer un second morceau écrasait purement et simplement le premier : rien
/// ne permettait d'y revenir plus tard sans le réimporter depuis Fichiers. Chaque morceau importé
/// une fois reste maintenant disponible d'un tap, même après avoir quitté et relancé l'app.
///
/// **Pourquoi pas `List`/`.sheet`/`.alert`, les outils système habituels pour ce genre d'écran.**
/// Aucun écran de l'app ne s'appuie sur eux — toute la navigation locale (voir `ScalesView`, dont
/// cet écran reprend exactement le principe) passe par un `@State` local et un `ZStack` dont on
/// bascule l'opacité, avec des cartes `liquidGlass` faites main. Introduire ici un style système
/// aurait détonné au milieu d'une interface entièrement personnalisée.
struct SongLibraryView: View {
    @Environment(AppStore.self) private var store
    var onSelect: (SongLibraryEntry) -> Void
    var onClose: () -> Void

    /// L'entrée dont le nom est en cours d'édition — `nil` tant qu'aucune ligne n'est en mode
    /// renommage. Un seul `@State`, pas un dictionnaire par ligne : une seule ligne à la fois peut
    /// raisonnablement être en train d'être renommée.
    @State private var renamingID: UUID?
    @State private var renameText = ""
    /// Confirmation à DEUX temps avant de supprimer — un premier tap change juste l'icône en
    /// bouton rouge "Supprimer ?", le second confirme. Jamais une suppression sur un seul tap
    /// accidentel : contrairement à un renommage (annulable en retapant), perdre un morceau
    /// importé oblige à le réimporter depuis Fichiers pour le retrouver.
    @State private var pendingDeleteID: UUID?

    private var sortedEntries: [SongLibraryEntry] {
        store.libraryEntries.sorted { $0.importedAt > $1.importedAt }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 8)

            if sortedEntries.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 12) {
                        ForEach(sortedEntries) { entry in
                            row(for: entry)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(sortedEntries.isEmpty ? "Bibliothèque" : "\(sortedEntries.count) morceau\(sortedEntries.count > 1 ? "x" : "")")
                    .font(.system(size: 15)).foregroundStyle(C.ink2)
                Text("Mes chansons")
                    .font(.system(size: 28, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(C.ink)
                    .frame(width: 40, height: 40)
                    .liquidGlass(radius: 20)
            }
            .buttonStyle(.plain)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "music.note.list").font(.system(size: 36)).foregroundStyle(C.inkFaint)
            Text("Aucun morceau importé pour l'instant")
                .font(.system(size: 15)).foregroundStyle(C.ink2)
        }
    }

    private func row(for entry: SongLibraryEntry) -> some View {
        Group {
            if renamingID == entry.id {
                renameField(for: entry)
            } else {
                infoRow(for: entry)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidGlass(radius: 20, tint: .white)
    }

    private func infoRow(for entry: SongLibraryEntry) -> some View {
        HStack(spacing: 4) {
            Button {
                onSelect(entry)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.customName)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(C.ink)
                        .lineLimit(1)
                    Text("\(entry.key.name().capitalized) · \(entry.noteCount) notes")
                        .font(.system(size: 13)).foregroundStyle(C.inkFaint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if pendingDeleteID == entry.id {
                Button {
                    store.deleteSong(id: entry.id)
                    pendingDeleteID = nil
                } label: {
                    Text("Supprimer ?")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(C.bad, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    renameText = entry.customName
                    renamingID = entry.id
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(C.ink2)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                Button {
                    pendingDeleteID = entry.id
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundStyle(C.inkFaint)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func renameField(for entry: SongLibraryEntry) -> some View {
        HStack(spacing: 10) {
            TextField("Nom du morceau", text: $renameText)
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(C.ink)
                .submitLabel(.done)
                .onSubmit { confirmRename(for: entry) }

            Button { confirmRename(for: entry) } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(C.good)
            }
            .buttonStyle(.plain)

            Button { renamingID = nil } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(C.inkFaint)
            }
            .buttonStyle(.plain)
        }
    }

    private func confirmRename(for entry: SongLibraryEntry) {
        store.renameSong(id: entry.id, to: renameText)
        renamingID = nil
    }
}
