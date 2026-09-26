import XCTest
@testable import CadenceCore

final class MIDIFileParserTests: XCTestCase {

    func testParsesThreeNotesInOrder() throws {
        // Do-Mi-Sol (accord de do majeur arpégé), une noire chacune à 120 bpm.
        let data = MIDIFixture.singleTrack(notes: [
            .init(pitch: 60, startTick: 0, durationTick: 480),
            .init(pitch: 64, startTick: 480, durationTick: 480),
            .init(pitch: 67, startTick: 960, durationTick: 480),
        ])

        let parsed = try MIDIFileParser.parse(data: data)

        XCTAssertEqual(parsed.notes.map(\.pitch), [60, 64, 67])
        XCTAssertEqual(parsed.ticksPerQuarterNote, 480)
    }

    func testConvertsTicksToSecondsAt120BPM() throws {
        // À 120 bpm, une noire (480 ticks) dure exactement 0,5 s — le calcul le plus simple à
        // vérifier de tête, donc le bon candidat pour un premier test de conversion.
        let data = MIDIFixture.singleTrack(microsecondsPerQuarterNote: 500_000, notes: [
            .init(pitch: 60, startTick: 0, durationTick: 480),
            .init(pitch: 62, startTick: 480, durationTick: 240),
        ])

        let parsed = try MIDIFileParser.parse(data: data)

        XCTAssertEqual(parsed.notes[0].startSeconds, 0.0, accuracy: 1e-9)
        XCTAssertEqual(parsed.notes[0].durationSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(parsed.notes[1].startSeconds, 0.5, accuracy: 1e-9)
        XCTAssertEqual(parsed.notes[1].durationSeconds, 0.25, accuracy: 1e-9)
    }

    func testHonoursMidTrackTempoChange() throws {
        // Une croche à 120 bpm dure 0,25 s ; une seconde note démarre juste après un changement
        // de tempo à 60 bpm, où la même distance en ticks doit durer deux fois plus longtemps.
        var events: [MIDIFixture.NoteSpec] = []
        events.append(.init(pitch: 60, startTick: 0, durationTick: 240))    // 0,25 s à 120 bpm

        // On ne peut pas insérer le changement de tempo via NoteSpec ; on construit donc le
        // fichier à la main pour ce test précis plutôt que d'étendre la fixture générique pour
        // un seul cas — la fixture reste simple pour tous les autres tests.
        let ticksPerQuarterNote = 480
        var trackData: [UInt8] = []
        func vlq(_ v: Int) -> [UInt8] {
            var buf = [UInt8](); var x = v
            buf.append(UInt8(x & 0x7F)); x >>= 7
            while x > 0 { buf.append(UInt8((x & 0x7F) | 0x80)); x >>= 7 }
            return buf.reversed()
        }
        // t=0 : tempo 120 bpm, note 60 on
        trackData += vlq(0) + [0xFF, 0x51, 0x03, 0x07, 0xA1, 0x20] // 500 000 µs/noire
        trackData += vlq(0) + [0x90, 60, 80]
        // t=240 (0,25s) : note 60 off, tempo passe à 60 bpm
        trackData += vlq(240) + [0x80, 60, 64]
        trackData += vlq(0) + [0xFF, 0x51, 0x03, 0x0F, 0x42, 0x40] // 1 000 000 µs/noire
        // t=240+480 ticks à 60 bpm = +1,0 s : note 62 on puis off aussitôt après
        trackData += vlq(480) + [0x90, 62, 80]
        trackData += vlq(1) + [0x80, 62, 64]
        trackData += vlq(0) + [0xFF, 0x2F, 0x00]

        var data = Data()
        data.append(Data("MThd".utf8))
        data.append(Data([0, 0, 0, 6]))
        data.append(Data([0, 0]))
        data.append(Data([0, 1]))
        data.append(Data([UInt8(ticksPerQuarterNote >> 8), UInt8(ticksPerQuarterNote & 0xFF)]))
        data.append(Data("MTrk".utf8))
        let len = UInt32(trackData.count)
        data.append(Data([UInt8(len >> 24), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)]))
        data.append(Data(trackData))

        let parsed = try MIDIFileParser.parse(data: data)

        XCTAssertEqual(parsed.notes[0].startSeconds, 0.0, accuracy: 1e-9)
        XCTAssertEqual(parsed.notes[0].durationSeconds, 0.25, accuracy: 1e-9)
        // La seconde note démarre à 0,25 s (fin de la première) + 1,0 s de tempo lent = 1,25 s.
        XCTAssertEqual(parsed.notes[1].startSeconds, 1.25, accuracy: 1e-6)
    }

    func testRejectsNonMIDIData() {
        let garbage = Data("pas un fichier MIDI".utf8)
        XCTAssertThrowsError(try MIDIFileParser.parse(data: garbage)) { error in
            XCTAssertEqual(error as? MIDIParseError, .notAMIDIFile)
        }
    }

    func testHandlesRunningStatus() throws {
        // Trois notes consécutives sur le même canal : le second et le troisième "note on" ne
        // répètent pas l'octet de statut 0x90, comme le ferait un vrai export DAW. Construit à
        // la main car `MIDIFixture` répète toujours le statut par simplicité.
        let ticksPerQuarterNote = 480
        var trackData: [UInt8] = []
        trackData += [0x00, 0x90, 60, 80]       // note on, statut explicite
        trackData += [0x00, 64, 80]              // note on IMPLICITE (running status)
        trackData += [0x00, 67, 80]              // idem
        trackData += [0x78, 0x80, 60, 0]         // note off do, 120 ticks plus tard
        trackData += [0x00, 0x80, 64, 0]
        trackData += [0x00, 0x80, 67, 0]
        trackData += [0x00, 0xFF, 0x2F, 0x00]

        var data = Data()
        data.append(Data("MThd".utf8))
        data.append(Data([0, 0, 0, 6]))
        data.append(Data([0, 0]))
        data.append(Data([0, 1]))
        data.append(Data([UInt8(ticksPerQuarterNote >> 8), UInt8(ticksPerQuarterNote & 0xFF)]))
        data.append(Data("MTrk".utf8))
        let len = UInt32(trackData.count)
        data.append(Data([UInt8(len >> 24), UInt8((len >> 16) & 0xFF), UInt8((len >> 8) & 0xFF), UInt8(len & 0xFF)]))
        data.append(Data(trackData))

        let parsed = try MIDIFileParser.parse(data: data)

        XCTAssertEqual(Set(parsed.notes.map(\.pitch)), [60, 64, 67])
        XCTAssertEqual(parsed.notes.count, 3)
    }
}
