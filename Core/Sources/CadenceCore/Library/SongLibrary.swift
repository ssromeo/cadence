import Foundation

/// Les métadonnées d'UN morceau importé, persistées sur disque — pas les exercices eux-mêmes
/// (voir `SongLibraryStore` pour pourquoi), seulement de quoi les régénérer et les présenter dans
/// une liste : un nom personnalisable, la date d'import, et la tonalité/le nombre de notes déjà
/// connus sans avoir à reparser le fichier juste pour peupler un menu.
public struct SongLibraryEntry: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    /// Le nom affiché — modifiable par l'utilisateur (voir `SongLibraryStore.rename`).
    /// `originalFileName`, lui, ne change jamais : c'est la trace de ce que le fichier s'appelait
    /// réellement, utile si jamais il faut un jour distinguer deux imports du même nom personnalisé.
    public var customName: String
    public let originalFileName: String
    public let importedAt: Date
    public let noteCount: Int
    private let keyTonicPitchClass: Int
    private let keyIsMajor: Bool

    public var key: MusicalKey { MusicalKey(tonicPitchClass: keyTonicPitchClass, isMajor: keyIsMajor) }

    public init(id: UUID = UUID(), customName: String, originalFileName: String, importedAt: Date = Date(),
               noteCount: Int, key: MusicalKey) {
        self.id = id
        self.customName = customName
        self.originalFileName = originalFileName
        self.importedAt = importedAt
        self.noteCount = noteCount
        self.keyTonicPitchClass = key.tonicPitchClass
        self.keyIsMajor = key.isMajor
    }
}

/// Persiste la bibliothèque des morceaux déjà importés — un manifeste JSON pour les métadonnées,
/// et le fichier MIDI brut de chacun à côté sur disque.
///
/// **Pourquoi garder le MIDI brut plutôt que les `GeneratedExercise` déjà générés.** Trois
/// raisons : (1) `GeneratedExercise` n'a aucune raison d'être `Codable` — c'est une sortie
/// jetable, régénérée à chaque session, pas un format de fichier à maintenir en compatibilité
/// dans le temps ; (2) le générateur d'exercices s'est déjà amélioré plusieurs fois dans ce projet
/// (armure déclarée, mesures canoniques, tonalité locale…) — figer les exercices au moment de
/// l'import aurait aussi figé leurs bugs, alors que garder le MIDI d'origine permet à un vieux
/// morceau importé de profiter de chaque futur correctif, comme s'il venait d'être réimporté ;
/// (3) c'est une quantité de données bien plus petite et stable à faire évoluer qu'un format de
/// sérialisation pour un type interne qui change encore.
public final class SongLibraryStore: Sendable {
    private let directory: URL
    private let manifestURL: URL

    public init(directory: URL) {
        self.directory = directory
        self.manifestURL = directory.appendingPathComponent("manifest.json")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Le dossier par défaut, dans le bac à sable de l'app — `Documents/SongLibrary`, pour que
    /// les fichiers MIDI importés restent visibles (et exportables) via le partage de fichiers de
    /// l'app, au même titre que tout ce qu'`UIFileSharingEnabled` expose déjà.
    public static func defaultDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("SongLibrary", isDirectory: true)
    }

    public func loadEntries() -> [SongLibraryEntry] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([SongLibraryEntry].self, from: data)) ?? []
    }

    private func saveEntries(_ entries: [SongLibraryEntry]) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(entries) else { return }
        try? data.write(to: manifestURL, options: .atomic)
    }

    private func midiFileURL(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).mid")
    }

    /// Ajoute un morceau tout juste importé à la bibliothèque — le nom par défaut vient du nom de
    /// fichier (sans son extension), immédiatement modifiable ensuite via `rename`.
    @discardableResult
    public func addSong(midiData: Data, originalFileName: String, noteCount: Int, key: MusicalKey) -> SongLibraryEntry {
        let entry = SongLibraryEntry(customName: Self.defaultName(from: originalFileName),
                                     originalFileName: originalFileName, noteCount: noteCount, key: key)
        try? midiData.write(to: midiFileURL(for: entry.id), options: .atomic)
        var entries = loadEntries()
        entries.append(entry)
        saveEntries(entries)
        return entry
    }

    /// Ne fait rien si le nom, une fois débarrassé de ses espaces superflus, est vide — un
    /// morceau sans nom du tout serait pire qu'un renommage refusé.
    public func rename(id: UUID, to newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var entries = loadEntries()
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].customName = trimmed
        saveEntries(entries)
    }

    public func delete(id: UUID) {
        var entries = loadEntries()
        entries.removeAll { $0.id == id }
        saveEntries(entries)
        try? FileManager.default.removeItem(at: midiFileURL(for: id))
    }

    public func midiData(for id: UUID) -> Data? {
        try? Data(contentsOf: midiFileURL(for: id))
    }

    private static func defaultName(from fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }
}
