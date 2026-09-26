import Foundation

/// Une tonalité détectée : sa tonique et son mode.
public struct MusicalKey: Equatable, Sendable {
    public let tonicPitchClass: Int
    public let isMajor: Bool

    /// Public — les appelants côté app (le sélecteur de gamme, par exemple) doivent pouvoir
    /// construire une tonalité de leur choix, pas seulement recevoir celles que détecte
    /// `KeyDetector` depuis un morceau.
    public init(tonicPitchClass: Int, isMajor: Bool) {
        self.tonicPitchClass = tonicPitchClass
        self.isMajor = isMajor
    }

    /// Les tonalités à dièses s'écrivent avec des dièses, celles à bémols avec des bémols — la
    /// convention n'est pas arbitraire, elle vient du cercle des quintes. Approximation
    /// suffisante pour l'affichage : les tonalités dont la tonique se trouve du côté "dièse" du
    /// cercle (sol, ré, la, mi, si) préfèrent les dièses ; les autres, les bémols.
    public var prefersFlats: Bool {
        let sharpSideMajorTonics: Set<Int> = [7, 2, 9, 4, 11] // sol, ré, la, mi, si
        let tonicForComparison = isMajor ? tonicPitchClass : (tonicPitchClass + 3) % 12 // relatif majeur
        return !sharpSideMajorTonics.contains(tonicForComparison) && tonicForComparison != 0
    }

    public func name() -> String {
        "\(NoteNaming.name(forPitchClass: tonicPitchClass, preferFlats: prefersFlats)) \(isMajor ? "majeur" : "mineur")"
    }

    /// Intervalles en demi-tons depuis la tonique — le motif qui définit le mode, avant même
    /// de savoir sur quelle hauteur il est posé.
    private var steps: [Int] { isMajor ? [0, 2, 4, 5, 7, 9, 11] : [0, 2, 3, 5, 7, 8, 10] }

    /// Classes de hauteur diatoniques de la tonalité — la gamme majeure ou mineure naturelle
    /// bâtie sur la tonique.
    public var scalePitchClasses: [Int] {
        steps.map { ((tonicPitchClass + $0) % 12 + 12) % 12 }
    }

    /// Les sept degrés de la gamme en hauteurs MIDI ASCENDANTES, à partir d'une tonique de
    /// référence donnée — pratique pour les poser sur une portée sans reconstituer soi-même le
    /// motif de tons et de demi-tons à chaque appelant. `tonicPitch` n'a pas besoin d'être dans
    /// la bonne classe de hauteur : seul son reste modulo 12 compte, le reste ne fait que fixer
    /// l'octave de départ.
    public func scalePitches(startingFrom tonicPitch: Int) -> [Int] {
        steps.map { tonicPitch + $0 }
    }

    /// Nombre d'altérations à l'armure — ce que compte un musicien qui lit une partition,
    /// dérivé ici de la position de la tonique sur le cercle des quintes plutôt qu'appris par
    /// cœur : do majeur (0), et chaque quinte ascendante ajoute un dièse jusqu'à la tonique
    /// opposée, où l'on bascule sur un compte de bémols décroissant.
    public var accidentalCount: Int {
        // Position de la tonique majeure équivalente sur le cercle des quintes, mesurée en
        // nombre de quintes depuis do (do=0, sol=1, ré=2, … en dièses ; fa=1, si♭=2, … en
        // bémols). `7 * fifths mod 12` retombe sur la classe de hauteur : c'est l'opération
        // inverse qu'on résout ici par recherche directe, plus lisible qu'une formule fermée.
        let referenceTonic = isMajor ? tonicPitchClass : (tonicPitchClass + 3) % 12 // relatif majeur
        if prefersFlats {
            let flatOrder = [0, 5, 10, 3, 8, 1, 6] // do, fa, si♭, mi♭, la♭, ré♭, sol♭
            return flatOrder.firstIndex(of: referenceTonic) ?? 0
        } else {
            let sharpOrder = [0, 7, 2, 9, 4, 11, 6] // do, sol, ré, la, mi, si, fa♯
            return sharpOrder.firstIndex(of: referenceTonic) ?? 0
        }
    }
}

/// Détection de tonalité par l'algorithme de Krumhansl-Schmuckler : on compare l'empreinte
/// harmonique du morceau — combien de temps chaque classe de hauteur sonne au total — aux
/// profils empiriques d'écoute mesurés par Krumhansl et Kessler, pour les 24 tonalités
/// possibles, et l'on retient la meilleure corrélation.
///
/// **Pourquoi une méthode statistique plutôt que "compter les altérations".** Compter les
/// dièses/bémols suppose une partition déjà écrite dans la bonne tonalité — ce que le MIDI n'a
/// justement pas, puisqu'il ne code que des hauteurs. La corrélation, elle, se contente de ce
/// qui a réellement sonné : elle capture qu'un morceau qui insiste sur do, mi, sol, si est
/// probablement en do majeur même sans qu'aucune armure n'existe dans le fichier.
public enum KeyDetector {
    // Profils de Krumhansl-Kessler (1990), mesurés en cognition musicale — la force d'ancrage
    // perçue de chaque degré chromatique par rapport à une tonique de référence.
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    /// Détecte la tonalité à partir d'un poids par classe de hauteur (12 valeurs, l'ordre
    /// correspondant à `pitchClass` 0…11). Le poids attendu est une DURÉE cumulée — une ronde
    /// pèse pour plus qu'une croche — et non un simple comptage d'occurrences : une note tenue
    /// longtemps ancre la tonalité bien davantage qu'une note de passage, et un comptage brut
    /// les traiterait à égalité.
    public static func detectKey(pitchClassWeights: [Double]) -> MusicalKey {
        precondition(pitchClassWeights.count == 12, "il faut exactement 12 poids, un par classe de hauteur")

        var best: (score: Double, tonic: Int, isMajor: Bool)?
        for tonic in 0..<12 {
            let majorScore = correlation(pitchClassWeights, rotate(majorProfile, to: tonic))
            let minorScore = correlation(pitchClassWeights, rotate(minorProfile, to: tonic))
            if best == nil || majorScore > best!.score { best = (majorScore, tonic, true) }
            if minorScore > best!.score { best = (minorScore, tonic, false) }
        }
        return MusicalKey(tonicPitchClass: best!.tonic, isMajor: best!.isMajor)
    }

    /// Construit le poids par classe de hauteur directement depuis les notes d'un morceau —
    /// c'est l'entrée la plus courante, pas besoin de le faire à la main pour chaque appelant.
    public static func detectKey(from notes: [MIDINoteEvent]) -> MusicalKey {
        var weights = [Double](repeating: 0, count: 12)
        for note in notes { weights[note.pitchClass] += max(note.durationSeconds, 0.01) }
        return detectKey(pitchClassWeights: weights)
    }

    /// Détecte la tonalité EN VIGUEUR à un instant précis du morceau, pas sur l'ensemble du
    /// fichier — pour un exercice tiré d'UN point précis d'un morceau qui module.
    ///
    /// **Le problème que ça résout.** `detectKey(from:)` fait la moyenne de tout le fichier :
    /// pour un morceau qui change de tonalité en cours de route (la moitié en la majeur, la
    /// moitié en la mineur relatif, par exemple — un vrai "key change" comme le nom du fichier
    /// peut l'indiquer), le résultat global n'est ni l'une ni l'autre, et peut même retomber sur
    /// une tonalité SANS ALTÉRATION alors que le passage réel en a plusieurs — l'armure ne se
    /// dessine plus, et les dièses ou bémols bien réels de ce passage semblent "en trop" à
    /// l'écran. En ne pondérant que les notes dans une fenêtre de quelques secondes autour de
    /// l'instant demandé, chaque exercice reçoit la tonalité qui était RÉELLEMENT en vigueur là
    /// où il a été prélevé.
    public static func detectLocalKey(from notes: [MIDINoteEvent], around time: Double,
                                      windowSeconds: Double = 8.0) -> MusicalKey {
        let windowNotes = notes.filter { abs($0.startSeconds - time) <= windowSeconds }
        // Une fenêtre vide (un extrait isolé, très court) n'a pas assez de matière pour une
        // corrélation fiable — mieux vaut alors la statistique globale que rien du tout.
        guard !windowNotes.isEmpty else { return detectKey(from: notes) }
        return detectKey(from: windowNotes)
    }

    /// Réaligne un profil défini pour une tonique en do sur une autre tonique : la valeur pour
    /// la classe de hauteur `p` sous la tonique `tonic` est celle du profil de référence pour
    /// le degré `p - tonic`.
    private static func rotate(_ profile: [Double], to tonic: Int) -> [Double] {
        (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
    }

    /// Corrélation de Pearson entre deux vecteurs de 12 valeurs.
    private static func correlation(_ a: [Double], _ b: [Double]) -> Double {
        let n = Double(a.count)
        let meanA = a.reduce(0, +) / n
        let meanB = b.reduce(0, +) / n
        var numerator = 0.0, varA = 0.0, varB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA, db = b[i] - meanB
            numerator += da * db
            varA += da * da
            varB += db * db
        }
        guard varA > 0, varB > 0 else { return 0 }
        return numerator / (varA.squareRoot() * varB.squareRoot())
    }
}
