import Foundation

/// Un intervalle mélodique, nommé par sa distance en demi-tons.
///
/// **Limite assumée.** Un intervalle "juste" se nomme aussi d'après la position sur la portée
/// (une tierce reste une tierce qu'elle soit diminuée, mineure, majeure ou augmentée — quatre
/// noms pour éventuellement le même nombre de demi-tons enharmoniques). Reconstruire cette
/// position demanderait de connaître l'armure et l'orthographe exacte des notes, que le MIDI ne
/// porte pas : deux fichiers strictement identiques en son peuvent être écrits différemment sur
/// la portée. Pour un quiz d'ENTRAÎNEMENT DE L'OREILLE — reconnaître ce qu'on entend, pas relire
/// une partition — nommer par le nombre de demi-tons est le bon niveau : c'est exactement ce
/// que l'oreille perçoit, ni plus ni moins.
public enum IntervalQuality: Int, CaseIterable, Sendable, Equatable {
    case unison = 0
    case minorSecond = 1
    case majorSecond = 2
    case minorThird = 3
    case majorThird = 4
    case perfectFourth = 5
    case tritone = 6
    case perfectFifth = 7
    case minorSixth = 8
    case majorSixth = 9
    case minorSeventh = 10
    case majorSeventh = 11
    case octave = 12

    public var shortName: String {
        switch self {
        case .unison: "1"
        case .minorSecond: "2m"
        case .majorSecond: "2M"
        case .minorThird: "3m"
        case .majorThird: "3M"
        case .perfectFourth: "4"
        case .tritone: "4+/5♭"
        case .perfectFifth: "5"
        case .minorSixth: "6m"
        case .majorSixth: "6M"
        case .minorSeventh: "7m"
        case .majorSeventh: "7M"
        case .octave: "8"
        }
    }

    public var displayName: String {
        switch self {
        case .unison: "Unisson"
        case .minorSecond: "Seconde mineure"
        case .majorSecond: "Seconde majeure"
        case .minorThird: "Tierce mineure"
        case .majorThird: "Tierce majeure"
        case .perfectFourth: "Quarte juste"
        case .tritone: "Triton"
        case .perfectFifth: "Quinte juste"
        case .minorSixth: "Sixte mineure"
        case .majorSixth: "Sixte majeure"
        case .minorSeventh: "Septième mineure"
        case .majorSeventh: "Septième majeure"
        case .octave: "Octave"
        }
    }
}

/// Un intervalle entre deux notes réellement jouées, avec le sens du mouvement — monter d'une
/// tierce et en descendre une s'entendent différemment, même si le nombre de demi-tons entre
/// les deux notes est identique en valeur absolue.
public struct MelodicInterval: Equatable, Sendable {
    public let from: MIDINoteEvent
    public let to: MIDINoteEvent
    public let semitones: Int          // signé : positif = monte, négatif = descend
    public let quality: IntervalQuality // toujours calculée sur la valeur absolue, au-delà d'une octave ramenée dans l'octave (compound → simple)
    public let isAscending: Bool
    /// Vrai si l'écart dépasse une octave (une tierce peut ainsi être "composée" : une dixième).
    public let isCompound: Bool

    public init(from: MIDINoteEvent, to: MIDINoteEvent) {
        self.from = from
        self.to = to
        let delta = to.pitch - from.pitch
        self.semitones = delta
        self.isAscending = delta >= 0
        let absolute = abs(delta)
        self.isCompound = absolute > 12
        // Ramené dans l'octave (12 demi-tons) pour le nom : une dixième mineure "sonne" comme
        // une tierce mineure à l'oreille, l'octave supplémentaire n'ajoute rien à reconnaître.
        let simple = absolute % 12
        self.quality = IntervalQuality(rawValue: simple == 0 && absolute > 0 ? 12 : simple) ?? .unison
    }
}
