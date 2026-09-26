import Foundation

/// Une note extraite d'un fichier MIDI, replacée dans le temps réel (secondes) et non en
/// ticks — c'est en secondes qu'on regroupe des notes en accord ("jouées en même temps à 40 ms
/// près"), jamais en ticks, dont la durée dépend du tempo au moment où ils sont comptés.
public struct MIDINoteEvent: Equatable, Sendable {
    /// Hauteur MIDI, 0–127. 60 = do central.
    public let pitch: Int
    public let velocity: Int
    public let startSeconds: Double
    public let durationSeconds: Double
    public let track: Int
    public let channel: Int
    /// Numéro de mesure (1-indexé) où cette note commence — ce qui permet de retrouver un
    /// exercice dans la partition imprimée, pas seulement de faire confiance à l'algorithme.
    /// `1` par défaut : les notes construites à la main (tests, gammes) n'ont pas de mesure
    /// réelle à rapporter, seul un fichier importé en calcule une.
    public let measure: Int

    public init(pitch: Int, velocity: Int, startSeconds: Double, durationSeconds: Double,
                track: Int, channel: Int, measure: Int = 1) {
        self.pitch = pitch
        self.velocity = velocity
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.track = track
        self.channel = channel
        self.measure = measure
    }

    public var endSeconds: Double { startSeconds + durationSeconds }
    /// Classe de hauteur, 0–11 (do=0). C'est elle que la théorie manipule : un accord ou une
    /// tonalité ne connaît pas l'octave, seulement la position dans la gamme chromatique.
    public var pitchClass: Int { ((pitch % 12) + 12) % 12 }
}

/// Résultat du parsing : les notes, triées par entrée en jeu, et la résolution temporelle du
/// fichier d'origine — utile pour re-quantifier un rythme sans reparser le binaire.
public struct ParsedMIDI: Sendable {
    public let notes: [MIDINoteEvent]
    public let ticksPerQuarterNote: Int

    public init(notes: [MIDINoteEvent], ticksPerQuarterNote: Int) {
        self.notes = notes.sorted { $0.startSeconds == $1.startSeconds ? $0.pitch < $1.pitch : $0.startSeconds < $1.startSeconds }
        self.ticksPerQuarterNote = ticksPerQuarterNote
    }
}

public enum MIDIParseError: Error, Equatable {
    case notAMIDIFile
    case unsupportedTimeDivision   // SMPTE, pas ticks-par-noire — hors périmètre du MVP
    case truncatedTrack
    case truncatedFile
}

/// Lecteur de fichier MIDI standard (SMF), formats 0 et 1.
///
/// **Pourquoi un parseur maison plutôt qu'une bibliothèque tierce.** Le format SMF est petit,
/// stable depuis 1988, et entièrement documenté ; l'écrire soi-même retire une dépendance dont
/// on ne se sert que pour une poignée d'octets, et garde la conversion tick→secondes — le point
/// le plus facile à mal faire — sous les yeux, à côté des tests qui la vérifient.
public enum MIDIFileParser {
    public static func parse(data: Data) throws -> ParsedMIDI {
        var reader = ByteReader(data: data)

        guard reader.readFourCC() == "MThd" else { throw MIDIParseError.notAMIDIFile }
        let headerLength = try reader.readUInt32()
        guard headerLength >= 6 else { throw MIDIParseError.notAMIDIFile }
        let format = try reader.readUInt16()
        let trackCount = try reader.readUInt16()
        let division = try reader.readUInt16()
        // Le reste d'un en-tête plus long que 6 octets (rare, mais permis par la norme) est à
        // ignorer sans y toucher.
        reader.skip(Int(headerLength) - 6)

        // Bit 15 posé = SMPTE (images/seconde), pas ticks par noire. Les fichiers exportés par
        // un DAW ou un clavier grand public sont presque toujours en ticks par noire ; le SMPTE
        // sert au montage vidéo et sort du périmètre du MVP plutôt que d'être mal converti.
        guard division & 0x8000 == 0 else { throw MIDIParseError.unsupportedTimeDivision }
        let ticksPerQuarterNote = Int(division)
        _ = format // formats 0 et 1 se lisent de la même façon : un flux de pistes MTrk.

        var rawTracks: [[RawEvent]] = []
        for _ in 0..<trackCount {
            rawTracks.append(try readTrack(&reader))
        }

        let tempoMap = buildTempoMap(rawTracks: rawTracks)
        let timeSignatureMap = buildTimeSignatureMap(rawTracks: rawTracks, ticksPerQuarterNote: ticksPerQuarterNote)
        var notes: [MIDINoteEvent] = []

        for (trackIndex, events) in rawTracks.enumerated() {
            // Notes actives par (canal, hauteur) : une pile, car une même touche peut être
            // rejouée avant que le MIDI n'ait envoyé son "note off" — improbable au clavier,
            // fréquent dans un export généré par un logiciel de notation.
            var active: [NoteKey: [(startTick: Int, velocity: Int)]] = [:]

            for event in events {
                switch event.kind {
                case .noteOn(let channel, let pitch, let velocity) where velocity > 0:
                    let key = NoteKey(channel: channel, pitch: pitch)
                    active[key, default: []].append((event.tick, velocity))

                // Une vélocité de 0 sur un "note on" EST un "note off" — convention historique
                // héritée du running status, que beaucoup de logiciels utilisent encore pour
                // éviter d'envoyer un octet de statut différent à chaque coupure de note.
                case .noteOn(let channel, let pitch, 0), .noteOff(let channel, let pitch, _):
                    let key = NoteKey(channel: channel, pitch: pitch)
                    guard var stack = active[key], !stack.isEmpty else { continue }
                    let (startTick, velocity) = stack.removeLast()
                    active[key] = stack
                    let startSeconds = tempoMap.seconds(atTick: startTick, ticksPerQuarterNote: ticksPerQuarterNote)
                    let endSeconds = tempoMap.seconds(atTick: event.tick, ticksPerQuarterNote: ticksPerQuarterNote)
                    let measure = timeSignatureMap.measureNumber(atTick: startTick)
                    notes.append(MIDINoteEvent(pitch: pitch, velocity: velocity,
                                               startSeconds: startSeconds,
                                               durationSeconds: max(0, endSeconds - startSeconds),
                                               track: trackIndex, channel: channel, measure: measure))
                default:
                    continue
                }
            }
        }

        return ParsedMIDI(notes: notes, ticksPerQuarterNote: ticksPerQuarterNote)
    }

    // MARK: - Lecture d'une piste

    private struct NoteKey: Hashable { let channel: Int; let pitch: Int }

    private enum EventKind {
        case noteOn(channel: Int, pitch: Int, velocity: Int)
        case noteOff(channel: Int, pitch: Int, velocity: Int)
        case tempo(microsecondsPerQuarterNote: Int)
        case timeSignature(numerator: Int, denominatorPower: Int)
        case other
    }

    private struct RawEvent { let tick: Int; let kind: EventKind }

    private static func readTrack(_ reader: inout ByteReader) throws -> [RawEvent] {
        guard reader.readFourCC() == "MTrk" else { throw MIDIParseError.truncatedFile }
        let length = try reader.readUInt32()
        let trackEnd = reader.position + Int(length)

        var events: [RawEvent] = []
        var tick = 0
        // Le "running status" : un octet de statut n'est répété que s'il change. Un long
        // passage de notes sur le même canal n'envoie donc son octet de commande qu'une fois.
        var runningStatus: UInt8? = nil

        while reader.position < trackEnd {
            tick += try reader.readVariableLengthQuantity()
            var status = try reader.readByte()

            if status < 0x80 {
                // Ce n'est pas un octet de statut : c'est déjà la première donnée de
                // l'événement, sous running status. On la repose et on réutilise le dernier
                // statut connu.
                guard let last = runningStatus else { throw MIDIParseError.truncatedTrack }
                reader.position -= 1
                status = last
            } else {
                runningStatus = status
            }

            if status == 0xFF {
                // Méta-événement : type, longueur VLQ, données.
                let type = try reader.readByte()
                let len = try reader.readVariableLengthQuantity()
                let payload = try reader.readBytes(len)
                if type == 0x51, payload.count == 3 {
                    let micros = (Int(payload[0]) << 16) | (Int(payload[1]) << 8) | Int(payload[2])
                    events.append(RawEvent(tick: tick, kind: .tempo(microsecondsPerQuarterNote: micros)))
                } else if type == 0x58, payload.count >= 2 {
                    // Signature rythmique : numérateur tel quel, dénominateur codé comme une
                    // PUISSANCE de 2 (2 → /4, 3 → /8…) — c'est la convention SMF, pas une valeur
                    // directement lisible.
                    events.append(RawEvent(tick: tick, kind: .timeSignature(numerator: Int(payload[0]),
                                                                            denominatorPower: Int(payload[1]))))
                } else if type == 0x2F {
                    break // fin de piste
                }
                continue
            }

            if status == 0xF0 || status == 0xF7 {
                // SysEx : longueur VLQ puis données. Hors périmètre théorique — on saute.
                let len = try reader.readVariableLengthQuantity()
                reader.skip(len)
                continue
            }

            let messageType = status & 0xF0
            let channel = Int(status & 0x0F)

            switch messageType {
            case 0x80: // Note off
                let pitch = Int(try reader.readByte())
                let velocity = Int(try reader.readByte())
                events.append(RawEvent(tick: tick, kind: .noteOff(channel: channel, pitch: pitch, velocity: velocity)))
            case 0x90: // Note on
                let pitch = Int(try reader.readByte())
                let velocity = Int(try reader.readByte())
                events.append(RawEvent(tick: tick, kind: .noteOn(channel: channel, pitch: pitch, velocity: velocity)))
            case 0xA0, 0xB0, 0xE0: // aftertouch polyphonique, control change, pitch bend : 2 octets de données
                reader.skip(2)
            case 0xC0, 0xD0: // program change, aftertouch de canal : 1 octet
                reader.skip(1)
            default:
                throw MIDIParseError.truncatedTrack
            }
        }

        reader.position = trackEnd
        return events
    }

    // MARK: - Conversion ticks → secondes

    /// Une piste de tempo peut changer en cours de morceau ; la conversion doit donc intégrer
    /// chaque segment à son propre tempo plutôt que d'appliquer un tempo unique à tout le
    /// fichier — sans quoi un ralenti ou une accélération décalerait toutes les notes qui le
    /// suivent.
    private struct TempoMap {
        /// (tick de début du segment, microsecondes par noire pendant ce segment), triés.
        let changes: [(tick: Int, microsecondsPerQuarterNote: Int)]

        func seconds(atTick target: Int, ticksPerQuarterNote: Int) -> Double {
            var elapsedSeconds = 0.0
            var lastTick = 0
            var currentTempo = 500_000 // 120 BPM par défaut, valeur standard MIDI en l'absence de méta-événement

            for change in changes {
                let segmentEnd = min(change.tick, target)
                if segmentEnd > lastTick {
                    elapsedSeconds += secondsFor(ticks: segmentEnd - lastTick, tempo: currentTempo,
                                                 ticksPerQuarterNote: ticksPerQuarterNote)
                }
                lastTick = max(lastTick, segmentEnd)
                if change.tick <= target { currentTempo = change.microsecondsPerQuarterNote }
                if change.tick >= target { break }
            }
            if target > lastTick {
                elapsedSeconds += secondsFor(ticks: target - lastTick, tempo: currentTempo,
                                             ticksPerQuarterNote: ticksPerQuarterNote)
            }
            return elapsedSeconds
        }

        private func secondsFor(ticks: Int, tempo: Int, ticksPerQuarterNote: Int) -> Double {
            (Double(ticks) / Double(ticksPerQuarterNote)) * (Double(tempo) / 1_000_000)
        }
    }

    /// Rassemble les changements de tempo de TOUTES les pistes. En format 1, ils vivent
    /// normalement sur la piste 0 (la piste "chef d'orchestre"), mais rien dans la norme
    /// n'interdit à un export de les poser ailleurs — les ignorer romprait la synchronisation
    /// sur ces fichiers-là sans qu'aucune erreur ne le signale.
    private static func buildTempoMap(rawTracks: [[RawEvent]]) -> TempoMap {
        var changes: [(tick: Int, microsecondsPerQuarterNote: Int)] = []
        for events in rawTracks {
            for event in events {
                if case .tempo(let micros) = event.kind {
                    changes.append((event.tick, micros))
                }
            }
        }
        changes.sort { $0.tick < $1.tick }
        return TempoMap(changes: changes)
    }

    // MARK: - Numéro de mesure

    /// Convertit un instant en TICKS en numéro de mesure — ce qui permet de retrouver un
    /// exercice généré dans la partition imprimée, plutôt que de devoir faire confiance à
    /// l'algorithme sur parole. Une mesure vaut, en ticks, `ticksParNoire × numérateur × 4 /
    /// dénominateur` — pour 6/8 par exemple, 6 croches valent 3 noires : la moitié d'une mesure
    /// à 6/4 pour le même nombre de temps notés.
    private struct TimeSignatureMap {
        let ticksPerQuarterNote: Int
        /// (tick de début du segment, ticks par mesure pendant ce segment), triés.
        let changes: [(tick: Int, ticksPerMeasure: Int)]

        /// 4/4 par défaut si le fichier ne déclare aucune signature avant le premier événement —
        /// la valeur implicite standard MIDI en l'absence de méta-événement 0x58.
        private var defaultTicksPerMeasure: Int { ticksPerQuarterNote * 4 }

        func measureNumber(atTick target: Int) -> Int {
            var measure = 1
            var lastTick = 0
            var current = defaultTicksPerMeasure

            for change in changes {
                let segmentEnd = min(change.tick, target)
                if segmentEnd > lastTick, current > 0 {
                    measure += (segmentEnd - lastTick) / current
                }
                lastTick = max(lastTick, segmentEnd)
                if change.tick <= target { current = change.ticksPerMeasure }
                if change.tick >= target { break }
            }
            if target > lastTick, current > 0 {
                measure += (target - lastTick) / current
            }
            return measure
        }
    }

    private static func buildTimeSignatureMap(rawTracks: [[RawEvent]], ticksPerQuarterNote: Int) -> TimeSignatureMap {
        var changes: [(tick: Int, ticksPerMeasure: Int)] = []
        for events in rawTracks {
            for event in events {
                if case .timeSignature(let numerator, let denominatorPower) = event.kind {
                    let denominator = 1 << denominatorPower
                    let ticksPerMeasure = ticksPerQuarterNote * numerator * 4 / denominator
                    changes.append((event.tick, ticksPerMeasure))
                }
            }
        }
        changes.sort { $0.tick < $1.tick }
        return TimeSignatureMap(ticksPerQuarterNote: ticksPerQuarterNote, changes: changes)
    }
}

/// Lecteur séquentiel d'octets avec les primitives propres au format SMF : entiers big-endian
/// et quantités de longueur variable (VLQ), où le bit de poids fort de chaque octet dit s'il y
/// en a un suivant.
private struct ByteReader {
    let bytes: [UInt8]
    var position: Int = 0

    init(data: Data) { bytes = [UInt8](data) }

    mutating func readByte() throws -> UInt8 {
        guard position < bytes.count else { throw MIDIParseError.truncatedFile }
        defer { position += 1 }
        return bytes[position]
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard position + count <= bytes.count else { throw MIDIParseError.truncatedFile }
        defer { position += count }
        return Array(bytes[position..<position + count])
    }

    mutating func skip(_ count: Int) { position = min(bytes.count, position + max(0, count)) }

    mutating func readUInt16() throws -> UInt16 {
        let b = try readBytes(2)
        return (UInt16(b[0]) << 8) | UInt16(b[1])
    }

    mutating func readUInt32() throws -> UInt32 {
        let b = try readBytes(4)
        return (UInt32(b[0]) << 24) | (UInt32(b[1]) << 16) | (UInt32(b[2]) << 8) | UInt32(b[3])
    }

    mutating func readFourCC() -> String {
        guard let b = try? readBytes(4) else { return "" }
        return String(bytes: b, encoding: .ascii) ?? ""
    }

    mutating func readVariableLengthQuantity() throws -> Int {
        var value = 0
        for _ in 0..<4 { // une VLQ MIDI tient sur 4 octets au plus
            let byte = try readByte()
            value = (value << 7) | Int(byte & 0x7F)
            if byte & 0x80 == 0 { return value }
        }
        return value
    }
}
