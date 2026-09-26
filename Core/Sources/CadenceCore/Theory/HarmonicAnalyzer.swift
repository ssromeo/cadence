import Foundation

/// Un regroupement de notes jouées "en même temps" — un accord potentiel, avant même de savoir
/// si on sait le nommer.
public struct ChordCluster: Equatable, Sendable {
    public let notes: [MIDINoteEvent]
    public let startSeconds: Double
    public var pitchClasses: Set<Int> { Set(notes.map(\.pitchClass)) }
    public var bassPitchClass: Int { notes.min(by: { $0.pitch < $1.pitch })!.pitchClass }
}

/// Un accord identifié, replacé dans son contexte : à quel instant, et — si une tonalité a été
/// détectée — quel degré de l'échelle il occupe (I, IV, V…).
public struct AnalyzedChord: Equatable, Sendable {
    public let cluster: ChordCluster
    public let chord: IdentifiedChord?
    /// Chiffrage romain (1-indexé : I=1) si l'accord est diatonique dans la tonalité fournie,
    /// `nil` sinon — un accord "emprunté" ou une simple couleur chromatique n'a pas de degré.
    public let scaleDegree: Int?
}

/// Le pipeline complet : d'un fichier MIDI parsé à une analyse harmonique exploitable par les
/// quiz et par la vue "carte des accords".
///
/// Trois étapes, dans cet ordre précis :
/// 1. Regrouper les notes en clusters (candidats accords) par proximité temporelle.
/// 2. Détecter la tonalité sur l'ENSEMBLE du morceau — elle a besoin de voir tout le matériau
///    pour être fiable, contrairement aux accords qui se lisent cluster par cluster.
/// 3. Identifier chaque cluster et le rapporter à la tonalité détectée.
public enum HarmonicAnalyzer {
    /// Fenêtre en secondes sous laquelle deux notes sont considérées "jouées ensemble". Un
    /// pianiste humain n'attaque jamais deux touches d'un accord à la microseconde près ; 60 ms
    /// couvre l'étalement naturel d'une main sans fusionner deux accords réellement successifs
    /// dans un tempo rapide (à 200 bpm, une double-croche dure 75 ms).
    public static let defaultClusterTolerance: Double = 0.06

    public static func clusterChords(from notes: [MIDINoteEvent],
                                     tolerance: Double = defaultClusterTolerance) -> [ChordCluster] {
        guard !notes.isEmpty else { return [] }
        let sorted = notes.sorted { $0.startSeconds < $1.startSeconds }

        var clusters: [ChordCluster] = []
        var current: [MIDINoteEvent] = [sorted[0]]
        var currentStart = sorted[0].startSeconds

        for note in sorted.dropFirst() {
            if note.startSeconds - currentStart <= tolerance {
                current.append(note)
            } else {
                clusters.append(ChordCluster(notes: current, startSeconds: currentStart))
                current = [note]
                currentStart = note.startSeconds
            }
        }
        clusters.append(ChordCluster(notes: current, startSeconds: currentStart))
        return clusters
    }

    /// Analyse complète : tonalité détectée sur tout le morceau, puis chaque cluster rapporté à
    /// elle.
    public static func analyze(notes: [MIDINoteEvent],
                               tolerance: Double = defaultClusterTolerance) -> (key: MusicalKey, chords: [AnalyzedChord]) {
        let key = KeyDetector.detectKey(from: notes)
        let clusters = clusterChords(from: notes, tolerance: tolerance)

        let scaleDegreeByPitchClass: [Int: Int] = Dictionary(
            uniqueKeysWithValues: key.scalePitchClasses.enumerated().map { ($1, $0 + 1) })

        let analyzed = clusters.map { cluster -> AnalyzedChord in
            let identified = ChordIdentifier.identify(pitchClasses: cluster.pitchClasses,
                                                      bassPitchClass: cluster.bassPitchClass)
            let degree = identified.flatMap { scaleDegreeByPitchClass[$0.rootPitchClass] }
            return AnalyzedChord(cluster: cluster, chord: identified, scaleDegree: degree)
        }
        return (key, analyzed)
    }

    /// La ligne mélodique d'une piste : ses notes, triées, converties en intervalles successifs.
    /// C'est la matière première du quiz de reconnaissance d'intervalles.
    public static func melodicIntervals(from notes: [MIDINoteEvent], track: Int? = nil) -> [MelodicInterval] {
        let filtered = track.map { t in notes.filter { $0.track == t } } ?? notes
        let sorted = filtered.sorted { $0.startSeconds < $1.startSeconds }
        guard sorted.count >= 2 else { return [] }
        return zip(sorted, sorted.dropFirst()).map { MelodicInterval(from: $0, to: $1) }
    }
}
