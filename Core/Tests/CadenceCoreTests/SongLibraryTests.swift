import XCTest
@testable import CadenceCore

/// `SongLibraryStore` touche vraiment le disque — les tests utilisent chacun un dossier
/// temporaire JETABLE (jamais le vrai dossier de l'app), nettoyé après coup, pour ne jamais
/// dépendre de l'état laissé par un test précédent ni polluer quoi que ce soit de réel.
final class SongLibraryTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SongLibraryTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }

    func testAddedSongIsPersistedAndReloadable() {
        let store = SongLibraryStore(directory: tempDirectory)
        let key = MusicalKey(tonicPitchClass: 4, isMajor: true)
        let midiBytes = Data([0x4D, 0x54, 0x68, 0x64]) // peu importe le contenu réel ici

        let entry = store.addSong(midiData: midiBytes, originalFileName: "Ma Chanson.mid",
                                  noteCount: 42, key: key)

        XCTAssertEqual(entry.customName, "Ma Chanson", "le nom par défaut vient du nom de fichier, sans son extension")

        // Un SECOND store, sur le MÊME dossier — simule un relancement de l'app : rien ne doit se
        // perdre entre les deux, tout doit relire depuis le disque.
        let reloaded = SongLibraryStore(directory: tempDirectory)
        let entries = reloaded.loadEntries()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].id, entry.id)
        XCTAssertEqual(entries[0].noteCount, 42)
        XCTAssertEqual(entries[0].key, key)
        XCTAssertEqual(reloaded.midiData(for: entry.id), midiBytes,
                       "le fichier MIDI d'origine doit être relisible tel quel, pas seulement ses métadonnées")
    }

    func testRenameChangesCustomNameButNeverTheOriginalFileName() {
        let store = SongLibraryStore(directory: tempDirectory)
        let entry = store.addSong(midiData: Data(), originalFileName: "song.mid", noteCount: 1,
                                  key: MusicalKey(tonicPitchClass: 0, isMajor: true))

        store.rename(id: entry.id, to: "Ma reprise du dimanche")

        let reloaded = store.loadEntries().first!
        XCTAssertEqual(reloaded.customName, "Ma reprise du dimanche")
        XCTAssertEqual(reloaded.originalFileName, "song.mid", "le nom de fichier d'origine ne doit jamais changer")
    }

    /// Un nom vide (ou seulement des espaces) ne doit RIEN changer — un morceau sans nom du tout
    /// serait pire qu'un renommage refusé.
    func testRenameToBlankNameIsIgnored() {
        let store = SongLibraryStore(directory: tempDirectory)
        let entry = store.addSong(midiData: Data(), originalFileName: "song.mid", noteCount: 1,
                                  key: MusicalKey(tonicPitchClass: 0, isMajor: true))

        store.rename(id: entry.id, to: "   ")

        XCTAssertEqual(store.loadEntries().first!.customName, "song")
    }

    func testDeleteRemovesBothTheEntryAndItsMIDIFile() {
        let store = SongLibraryStore(directory: tempDirectory)
        let entry = store.addSong(midiData: Data([1, 2, 3]), originalFileName: "song.mid", noteCount: 1,
                                  key: MusicalKey(tonicPitchClass: 0, isMajor: true))

        store.delete(id: entry.id)

        XCTAssertTrue(store.loadEntries().isEmpty)
        XCTAssertNil(store.midiData(for: entry.id), "le fichier MIDI doit disparaître avec son entrée, pas traîner sur le disque")
    }

    func testMultipleSongsAreAllPreservedIndependently() {
        let store = SongLibraryStore(directory: tempDirectory)
        let first = store.addSong(midiData: Data([1]), originalFileName: "a.mid", noteCount: 10,
                                  key: MusicalKey(tonicPitchClass: 0, isMajor: true))
        let second = store.addSong(midiData: Data([2]), originalFileName: "b.mid", noteCount: 20,
                                   key: MusicalKey(tonicPitchClass: 7, isMajor: true))

        store.rename(id: first.id, to: "Premier")

        let entries = store.loadEntries()
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.first { $0.id == first.id }?.customName, "Premier")
        XCTAssertEqual(entries.first { $0.id == second.id }?.customName, "b")
        XCTAssertEqual(store.midiData(for: first.id), Data([1]))
        XCTAssertEqual(store.midiData(for: second.id), Data([2]))
    }
}
