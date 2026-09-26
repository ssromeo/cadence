import Foundation

/// Une altération, telle qu'elle se dessine à côté d'une note — jamais un bécarre pour l'instant :
/// sans mémoire de mesure (quelle altération a déjà été jouée avant, dans le même compas), on ne
/// peut pas savoir si un bécarre est nécessaire. Cette nuance attendra la vraie gravure de
/// partition ; ici chaque note porte son altération de façon indépendante, ce qui est correct
/// tant qu'on affiche des notes isolées ou deux notes prises hors contexte, comme dans un quiz.
public enum Accidental: Sendable, Equatable {
    case natural, sharp, flat

    public var symbol: String {
        switch self {
        case .natural: ""
        case .sharp: "♯"
        case .flat: "♭"
        }
    }
}

/// L'orthographe d'une hauteur MIDI sur une portée : sa lettre, son octave, et l'altération qui
/// la sépare de la lettre naturelle.
public struct NoteSpelling: Equatable, Sendable {
    /// 0 = do, 1 = ré, 2 = mi, 3 = fa, 4 = sol, 5 = la, 6 = si.
    public let letterStep: Int
    /// Octave en notation scientifique : do central (MIDI 60) est en octave 4.
    public let octave: Int
    public let accidental: Accidental

    public init(letterStep: Int, octave: Int, accidental: Accidental) {
        self.letterStep = letterStep
        self.octave = octave
        self.accidental = accidental
    }

    /// Position diatonique continue — comparable entre deux notes quelle que soit leur octave.
    /// C'est elle qui donne l'écart vertical sur une portée : chaque unité vaut un demi-espace
    /// de portée (une ligne, ou l'espace entre deux lignes).
    public var diatonicIndex: Int { letterStep + octave * 7 }
}

/// Décide comment ÉCRIRE une hauteur MIDI — sa lettre et son altération.
///
/// **Le MIDI ne code pas l'orthographe.** Do dièse et ré bémol sont exactement la même touche,
/// la même hauteur — mais pas la même place sur la portée : do dièse se dessine sur la
/// ligne/l'espace du DO, ré bémol sur celle du RÉ. Il faut donc TRANCHER, et la seule
/// information disponible pour le faire sans partition d'origine est la tonalité détectée :
/// une tonalité à dièses épelle en dièses, une tonalité à bémols épelle en bémols. Ce n'est pas
/// exact à 100 % des cas réels (une partition originale s'écarte parfois de cette règle pour
/// suivre la direction mélodique), mais c'est la convention qui couvre l'immense majorité des
/// notes d'un morceau tonal.
public enum NotationSpelling {
    private static let sharpSpelling: [(letter: Int, accidental: Accidental)] = [
        (0, .natural), (0, .sharp), (1, .natural), (1, .sharp), (2, .natural), (3, .natural),
        (3, .sharp), (4, .natural), (4, .sharp), (5, .natural), (5, .sharp), (6, .natural),
    ]
    private static let flatSpelling: [(letter: Int, accidental: Accidental)] = [
        (0, .natural), (1, .flat), (1, .natural), (2, .flat), (2, .natural), (3, .natural),
        (4, .flat), (4, .natural), (5, .flat), (5, .natural), (6, .flat), (6, .natural),
    ]

    public static func spell(pitch: Int, preferFlats: Bool) -> NoteSpelling {
        let pitchClass = ((pitch % 12) + 12) % 12
        let octave = pitch / 12 - 1
        let entry = (preferFlats ? flatSpelling : sharpSpelling)[pitchClass]
        return NoteSpelling(letterStep: entry.letter, octave: octave, accidental: entry.accidental)
    }
}
