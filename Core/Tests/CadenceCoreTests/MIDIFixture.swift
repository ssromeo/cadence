import Foundation

/// Construit un fichier MIDI standard minimal, en mémoire, pour les tests.
///
/// **Pourquoi fabriquer les octets plutôt que joindre un vrai fichier `.mid` au dépôt.** Un
/// fichier binaire dans les fixtures est illisible en revue de code — personne ne peut voir
/// "ah, ce test attend do-mi-sol" en ouvrant un `.mid` — et il masque exactement ce que le test
/// vérifie. Cette fabrique rend visibles, dans le code Swift du test lui-même, les notes, leurs
/// dates et le tempo utilisés, donc un futur lecteur voit d'un coup d'œil ce qui est testé et
/// pourquoi le résultat attendu est celui-là.
enum MIDIFixture {
    struct NoteSpec {
        let pitch: Int
        let startTick: Int
        let durationTick: Int
        let velocity: Int
        let channel: Int
        let track: Int

        init(pitch: Int, startTick: Int, durationTick: Int, velocity: Int = 80,
             channel: Int = 0, track: Int = 0) {
            self.pitch = pitch
            self.startTick = startTick
            self.durationTick = durationTick
            self.velocity = velocity
            self.channel = channel
            self.track = track
        }
    }

    /// Fichier à une seule piste (format 0), avec un unique changement de tempo au début.
    static func singleTrack(ticksPerQuarterNote: Int = 480,
                            microsecondsPerQuarterNote: Int = 500_000,
                            notes: [NoteSpec]) -> Data {
        var events: [(tick: Int, order: Int, bytes: [UInt8])] = []
        events.append((0, -1, [0xFF, 0x51, 0x03,
                               UInt8((microsecondsPerQuarterNote >> 16) & 0xFF),
                               UInt8((microsecondsPerQuarterNote >> 8) & 0xFF),
                               UInt8(microsecondsPerQuarterNote & 0xFF)]))
        for (i, note) in notes.enumerated() {
            events.append((note.startTick, i * 2, [0x90 | UInt8(note.channel), UInt8(note.pitch), UInt8(note.velocity)]))
            // La coupure est un "note on" vélocité 0 pour une moitié des notes, un vrai
            // "note off" pour l'autre : le parseur doit accepter les deux conventions.
            let useNoteOnZero = i % 2 == 0
            let offBytes: [UInt8] = useNoteOnZero
                ? [0x90 | UInt8(note.channel), UInt8(note.pitch), 0]
                : [0x80 | UInt8(note.channel), UInt8(note.pitch), 64]
            events.append((note.startTick + note.durationTick, i * 2 + 1, offBytes))
        }
        events.sort { $0.tick == $1.tick ? $0.order < $1.order : $0.tick < $1.tick }

        var trackData: [UInt8] = []
        var lastTick = 0
        for event in events {
            trackData += variableLengthQuantity(event.tick - lastTick)
            trackData += event.bytes
            lastTick = event.tick
        }
        trackData += variableLengthQuantity(0) + [0xFF, 0x2F, 0x00] // fin de piste

        var data = Data()
        data.append(fourCC("MThd"))
        data.append(uint32(6))
        data.append(uint16(0))  // format 0
        data.append(uint16(1))  // une seule piste
        data.append(uint16(UInt16(ticksPerQuarterNote)))
        data.append(fourCC("MTrk"))
        data.append(uint32(UInt32(trackData.count)))
        data.append(Data(trackData))
        return data
    }

    private static func fourCC(_ s: String) -> Data { Data(s.utf8) }
    private static func uint16(_ v: UInt16) -> Data { Data([UInt8(v >> 8), UInt8(v & 0xFF)]) }
    private static func uint32(_ v: UInt32) -> Data {
        Data([UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }

    private static func variableLengthQuantity(_ value: Int) -> [UInt8] {
        precondition(value >= 0)
        var buffer = [UInt8]()
        var v = value
        buffer.append(UInt8(v & 0x7F))
        v >>= 7
        while v > 0 {
            buffer.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        return buffer.reversed()
    }
}
