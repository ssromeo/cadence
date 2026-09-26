import Foundation

/// Noms de note et signature de tonalité.
///
/// Une classe de hauteur (0–11) n'a pas de nom propre — do dièse et ré bémol sont la même
/// touche — le nom dépend du CONTEXTE : la tonalité en cours, ou une convention par défaut à
/// falloir de mieux. C'est pourquoi la fonction ci-dessous prend un paramètre `preferFlats` au
/// lieu de renvoyer un nom fixe : l'appelant qui connaît la tonalité (dièse ou bémol) doit
/// pouvoir l'orthographier juste.
public enum NoteNaming {
    private static let sharpNames = ["Do", "Do♯", "Ré", "Ré♯", "Mi", "Fa", "Fa♯", "Sol", "Sol♯", "La", "La♯", "Si"]
    private static let flatNames  = ["Do", "Ré♭", "Ré", "Mi♭", "Mi", "Fa", "Sol♭", "Sol", "La♭", "La", "Si♭", "Si"]

    public static func name(forPitchClass pc: Int, preferFlats: Bool = false) -> String {
        let normalized = ((pc % 12) + 12) % 12
        return preferFlats ? flatNames[normalized] : sharpNames[normalized]
    }

    /// Nom complet avec octave, à partir d'une hauteur MIDI (60 = "Do4").
    public static func name(forMIDIPitch pitch: Int, preferFlats: Bool = false) -> String {
        let octave = pitch / 12 - 1
        return "\(name(forPitchClass: pitch, preferFlats: preferFlats))\(octave)"
    }
}
