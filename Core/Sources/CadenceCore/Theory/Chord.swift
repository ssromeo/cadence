import Foundation

/// La qualité d'un accord — son type, indépendamment de la fondamentale.
public enum ChordQuality: String, CaseIterable, Sendable, Equatable {
    case major, minor, diminished, augmented
    case sus2, sus4
    case dominantSeventh, majorSeventh, minorSeventh
    case diminishedSeventh, halfDiminishedSeventh, minorMajorSeventh, augmentedSeventh

    public var displayName: String {
        switch self {
        case .major: "majeur"
        case .minor: "mineur"
        case .diminished: "diminué"
        case .augmented: "augmenté"
        case .sus2: "sus2"
        case .sus4: "sus4"
        case .dominantSeventh: "septième de dominante"
        case .majorSeventh: "septième majeure"
        case .minorSeventh: "septième mineure"
        case .diminishedSeventh: "septième diminuée"
        case .halfDiminishedSeventh: "demi-diminué"
        case .minorMajorSeventh: "mineur septième majeure"
        case .augmentedSeventh: "septième augmentée"
        }
    }

    /// Triades avant accords de septième, dans un ordre de familiarité décroissante. Utilisé
    /// pour départager une ambiguïté résiduelle — voir `ChordIdentifier`.
    fileprivate var priority: Int {
        switch self {
        case .major: 0
        case .minor: 1
        case .sus4: 2
        case .sus2: 3
        case .diminished: 4
        case .augmented: 5
        case .dominantSeventh: 6
        case .majorSeventh: 7
        case .minorSeventh: 8
        case .halfDiminishedSeventh: 9
        case .diminishedSeventh: 10
        case .minorMajorSeventh: 11
        case .augmentedSeventh: 12
        }
    }
}

/// Un accord reconnu : sa fondamentale théorique, sa qualité, et la note qui sonne le plus
/// grave — les deux ne coïncident QUE si l'accord est à l'état fondamental. Un do majeur joué
/// mi-sol-do a la même fondamentale (do) mais une basse différente (mi) : c'est un renversement,
/// pas un accord différent.
public struct IdentifiedChord: Equatable, Sendable {
    public let rootPitchClass: Int
    public let quality: ChordQuality
    public let bassPitchClass: Int
    /// 0 = état fondamental, 1 = premier renversement, 2 = second renversement, etc.
    public let inversion: Int
    public let pitchClasses: Set<Int>

    public var isRootPosition: Bool { inversion == 0 }

    public func name(preferFlats: Bool = false) -> String {
        "\(NoteNaming.name(forPitchClass: rootPitchClass, preferFlats: preferFlats)) \(quality.displayName)"
    }
}

/// Reconnaissance d'accords par comparaison d'ensembles de classes de hauteur — la méthode
/// "pitch class set" : on ignore l'octave et la répétition, on ne garde que QUELS degrés
/// chromatiques sonnent ensemble, et on compare ce sac à des gabarits connus.
public enum ChordIdentifier {
    private struct Template { let quality: ChordQuality; let intervals: [Int] }

    /// Intervalles depuis la fondamentale, fondamentale comprise (0). L'ordre de la liste ne
    /// compte pas pour la comparaison — seul l'ENSEMBLE compte — mais il sert de repère de
    /// lecture : triades d'abord, accords de septième ensuite.
    private static let templates: [Template] = [
        .init(quality: .major, intervals: [0, 4, 7]),
        .init(quality: .minor, intervals: [0, 3, 7]),
        .init(quality: .diminished, intervals: [0, 3, 6]),
        .init(quality: .augmented, intervals: [0, 4, 8]),
        .init(quality: .sus2, intervals: [0, 2, 7]),
        .init(quality: .sus4, intervals: [0, 5, 7]),
        .init(quality: .dominantSeventh, intervals: [0, 4, 7, 10]),
        .init(quality: .majorSeventh, intervals: [0, 4, 7, 11]),
        .init(quality: .minorSeventh, intervals: [0, 3, 7, 10]),
        .init(quality: .minorMajorSeventh, intervals: [0, 3, 7, 11]),
        .init(quality: .diminishedSeventh, intervals: [0, 3, 6, 9]),
        .init(quality: .halfDiminishedSeventh, intervals: [0, 3, 6, 10]),
        .init(quality: .augmentedSeventh, intervals: [0, 4, 8, 10]),
    ]

    /// Tente d'identifier un accord dans un ensemble de classes de hauteur.
    ///
    /// **La méthode : tester CHAQUE note comme fondamentale candidate**, et non partir d'une
    /// note "évidente" (la plus grave, par exemple) — c'est précisément ce qui permet de
    /// reconnaître un accord renversé : mi-sol-do n'a pas do comme note la plus grave, mais en
    /// essayant mi, puis sol, puis do comme fondamentale hypothétique, celle qui donne un
    /// gabarit exact (do : {0,4,7} relatif) est trouvée sans traitement spécial pour les
    /// renversements.
    public static func identify(pitchClasses: Set<Int>, bassPitchClass: Int) -> IdentifiedChord? {
        guard pitchClasses.count >= 3 else { return nil } // deux notes ne forment pas un accord identifiable sans ambiguïté

        var candidates: [(template: Template, root: Int)] = []
        for root in pitchClasses {
            let relative = Set(pitchClasses.map { normalize($0 - root) })
            for template in templates where Set(template.intervals) == relative {
                candidates.append((template, root))
            }
        }
        guard !candidates.isEmpty else { return nil }

        // Ambiguïté possible seulement en théorie (deux gabarits différents ne partagent jamais
        // exactement le même ensemble relatif) ; le tri par priorité est une garde, pas un cas
        // qui se produit avec les gabarits ci-dessus.
        let best = candidates.min { $0.template.quality.priority < $1.template.quality.priority }!

        let bassInterval = normalize(bassPitchClass - best.root)
        let sortedIntervals = best.template.intervals.sorted()
        let inversion = sortedIntervals.firstIndex(of: bassInterval) ?? 0

        return IdentifiedChord(rootPitchClass: best.root, quality: best.template.quality,
                               bassPitchClass: bassPitchClass, inversion: inversion,
                               pitchClasses: pitchClasses)
    }

    private static func normalize(_ pc: Int) -> Int { ((pc % 12) + 12) % 12 }
}
