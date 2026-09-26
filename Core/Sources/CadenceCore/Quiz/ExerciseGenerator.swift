import Foundation

/// Fabrique les deux familles d'exercices de l'app, à partir des DEUX sources d'entrée que le
/// projet distingue depuis son brief d'origine : un morceau importé, ou une tonalité choisie
/// sans morceau du tout.
///
/// **Pourquoi les deux passent par la même sortie (`[GeneratedExercise]`).** Peu importe d'où
/// vient un exercice, l'écran qui le joue est unique — voir `GeneratedExercise`. Ce fichier ne
/// s'occupe que de la fabrication ; il ne sait rien de SwiftUI, ni de comment ces exercices
/// seront affichés.
public enum ExerciseGenerator {

    // MARK: - Depuis un morceau importé

    /// Mélange d'exercices d'intervalles et d'accords, tirés des notes RÉELLEMENT jouées dans le
    /// morceau — le principe différenciant du pilier 1 : on s'entraîne sur SA musique.
    public static func fromImportedMusic(notes: [MIDINoteEvent],
                                         rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        var exercises = intervalExercises(from: notes, rng: &rng)
        exercises += chordExercises(from: notes, rng: &rng)
        exercises.shuffle(using: &rng)
        return exercises
    }

    private static func intervalExercises(from notes: [MIDINoteEvent],
                                          rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        HarmonicAnalyzer.melodicIntervals(from: notes).map { interval in
            let choices = intervalChoices(correct: interval.quality, rng: &rng)
            return GeneratedExercise(
                kind: .interval, prompt: "Quel est cet intervalle ?",
                notes: [interval.from.pitch, interval.to.pitch], stacked: false,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: interval.quality)!)
        }
    }

    /// Leurres PROCHES de la bonne réponse, jamais tirés au hasard sur les treize qualités —
    /// voir `IntervalQuizGenerator`, dont cette fonction reprend le principe : confondre une
    /// tierce majeure et une tierce mineure est l'erreur qu'on veut vraiment travailler.
    private static func intervalChoices(correct: IntervalQuality,
                                        rng: inout some RandomNumberGenerator) -> [IntervalQuality] {
        let pool = IntervalQuality.allCases
            .filter { $0 != correct }
            .sorted { abs($0.rawValue - correct.rawValue) < abs($1.rawValue - correct.rawValue) }
        var chosen: [IntervalQuality] = []
        var remaining = pool
        while chosen.count < 3, !remaining.isEmpty {
            let closest = abs(remaining[0].rawValue - correct.rawValue)
            let tied = remaining.prefix { abs($0.rawValue - correct.rawValue) == closest }
            let pick = tied.randomElement(using: &rng) ?? remaining[0]
            chosen.append(pick)
            remaining.removeAll { $0 == pick }
        }
        var choices = chosen + [correct]
        choices.shuffle(using: &rng)
        return choices
    }

    private static func chordExercises(from notes: [MIDINoteEvent],
                                       rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        HarmonicAnalyzer.clusterChords(from: notes).compactMap { cluster -> GeneratedExercise? in
            guard let chord = ChordIdentifier.identify(pitchClasses: cluster.pitchClasses,
                                                       bassPitchClass: cluster.bassPitchClass)
            else { return nil }

            let pool = ChordQuality.allCases.filter { $0 != chord.quality }.shuffled(using: &rng)
            var choices = Array(pool.prefix(3)) + [chord.quality]
            choices.shuffle(using: &rng)

            return GeneratedExercise(
                kind: .chordQuality, prompt: "Quelle est la qualité de cet accord ?",
                notes: cluster.notes.map(\.pitch).sorted(), stacked: true,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: chord.quality)!)
        }
    }

    // MARK: - Depuis une tonalité choisie, sans morceau

    /// Trois angles sur la MÊME gamme — pas un seul type d'exercice répété sept fois. Reconnaître
    /// une note, la situer dans l'échelle, et connaître l'armure sont trois compétences
    /// distinctes qu'un musicien mobilise séparément en lisant une partition.
    public static func fromScale(key: MusicalKey, rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        var exercises = scaleDegreeExercises(key: key, rng: &rng)
        exercises += noteSpellingExercises(key: key, rng: &rng)
        exercises.append(keySignatureExercise(key: key, rng: &rng))
        exercises.shuffle(using: &rng)
        return exercises
    }

    private static let romanNumerals = ["I", "II", "III", "IV", "V", "VI", "VII"]

    private static func scaleDegreeExercises(key: MusicalKey,
                                             rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        let tonicPitch = 60 + key.tonicPitchClass
        let pitches = key.scalePitches(startingFrom: tonicPitch)
        return pitches.enumerated().map { degree, pitch in
            var distractors = Array(0..<7).filter { $0 != degree }
            distractors.shuffle(using: &rng)
            var indices = Array(distractors.prefix(3)) + [degree]
            indices.shuffle(using: &rng)
            return GeneratedExercise(
                kind: .scaleDegree, prompt: "Quel degré de \(key.name()) est cette note ?",
                notes: [pitch], stacked: false,
                choices: indices.map { romanNumerals[$0] },
                correctIndex: indices.firstIndex(of: degree)!)
        }
    }

    private static func noteSpellingExercises(key: MusicalKey,
                                              rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        let tonicPitch = 60 + key.tonicPitchClass
        let pitches = key.scalePitches(startingFrom: tonicPitch)
        // Les douze noms possibles dans LA MÊME convention (dièses ou bémols) que la tonalité
        // choisie — mélanger les deux conventions dans les propositions ferait deviner la
        // réponse par l'orthographe plutôt que par la position, ce qui n'est pas ce qu'on teste.
        let allNames = (0..<12).map { NoteNaming.name(forPitchClass: $0, preferFlats: key.prefersFlats) }

        return pitches.map { pitch in
            let correctName = NoteNaming.name(forPitchClass: pitch, preferFlats: key.prefersFlats)
            var distractors = allNames.filter { $0 != correctName }
            distractors.shuffle(using: &rng)
            var choices = Array(distractors.prefix(3)) + [correctName]
            choices.shuffle(using: &rng)
            return GeneratedExercise(
                kind: .noteSpelling, prompt: "Quel est le nom de cette note ?",
                notes: [pitch], stacked: false,
                choices: choices, correctIndex: choices.firstIndex(of: correctName)!)
        }
    }

    // MARK: - Le parcours d'une gamme : plusieurs ÉTAPES distinctes, pas un seul quiz fourre-tout

    /// Les arrêts du parcours d'une gamme — chacun une compétence à part, qu'un musicien
    /// travaille séparément en pratique : reconnaître les notes, entendre/lire les intervalles
    /// qu'elles forment avec la tonique, harmoniser chaque degré en accord, connaître l'armure,
    /// et enfin tout mélanger contre la montre.
    public enum ScaleFocus: String, CaseIterable, Sendable {
        case notes, intervals, chords, keySignature, speed

        public var displayName: String {
            switch self {
            case .notes: "Notes"
            case .intervals: "Intervalles"
            case .chords: "Accords"
            case .keySignature: "Armure"
            case .speed: "Rapidité"
            }
        }
    }

    /// Fabrique la série d'exercices d'UNE étape du parcours — c'est cette fonction que le
    /// sélecteur de gamme appelle une fois l'utilisateur engagé sur un arrêt précis, jamais
    /// `fromScale(key:rng:)` qui mélangeait tout sans distinction d'étape.
    public static func scaleExercises(key: MusicalKey, focus: ScaleFocus,
                                      rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        switch focus {
        case .notes:
            var exercises = scaleDegreeExercises(key: key, rng: &rng) + noteSpellingExercises(key: key, rng: &rng)
            exercises.shuffle(using: &rng)
            return exercises
        case .intervals:
            return scaleIntervalExercises(key: key, rng: &rng)
        case .chords:
            return scaleChordExercises(key: key, rng: &rng)
        case .keySignature:
            return [keySignatureExercise(key: key, rng: &rng)]
        case .speed:
            // Le mélange le plus large qu'on ait — TOUT ce que la gamme peut travailler, dans le
            // même tas, précisément parce que le point de la vitesse est de ne jamais savoir à
            // l'avance quel type de question arrive.
            var exercises = scaleIntervalExercises(key: key, rng: &rng)
            exercises += scaleChordExercises(key: key, rng: &rng)
            exercises += noteSpellingExercises(key: key, rng: &rng)
            exercises.shuffle(using: &rng)
            return exercises
        }
    }

    /// Un intervalle depuis la TONIQUE vers chacun des six autres degrés, puis l'octave — la
    /// progression la plus naturelle pour apprendre à reconnaître "à quelle distance de chez moi"
    /// se trouve chaque note de la gamme, plutôt que des paires prises au hasard.
    private static func scaleIntervalExercises(key: MusicalKey,
                                               rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        let tonicPitch = 60 + key.tonicPitchClass
        let pitches = key.scalePitches(startingFrom: tonicPitch) + [tonicPitch + 12]
        return (1...7).map { degree in
            let to = pitches[degree]
            let quality = intervalQuality(from: tonicPitch, to: to)
            let choices = intervalChoices(correct: quality, rng: &rng)
            return GeneratedExercise(
                kind: .interval, prompt: "Quel est cet intervalle depuis la tonique ?",
                notes: [tonicPitch, to], stacked: false,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: quality)!)
        }
    }

    private static func intervalQuality(from: Int, to: Int) -> IntervalQuality {
        let absolute = abs(to - from)
        let simple = absolute % 12
        return IntervalQuality(rawValue: simple == 0 && absolute > 0 ? 12 : simple) ?? .unison
    }

    /// Un accord empilé en tierces sur CHAQUE degré de la gamme — les sept accords diatoniques,
    /// I à VII, que toute harmonisation de cette tonalité utilise. Construits en empilant deux
    /// tierces à l'intérieur même de la gamme (pas de la chromatique), leur qualité découle
    /// mécaniquement du motif de tons/demi-tons — jamais choisie à la main.
    private static func scaleChordExercises(key: MusicalKey,
                                            rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        let tonicPitch = 60 + key.tonicPitchClass
        let degreePitches = key.scalePitches(startingFrom: tonicPitch)
        let extended = degreePitches + degreePitches.map { $0 + 12 } // pour empiler au-delà du VIIe degré
        return (0..<7).compactMap { degree -> GeneratedExercise? in
            let triad = [extended[degree], extended[degree + 2], extended[degree + 4]]
            let pitchClasses = Set(triad.map { (($0 % 12) + 12) % 12 })
            let rootPitchClass = ((triad[0] % 12) + 12) % 12
            guard let chord = ChordIdentifier.identify(pitchClasses: pitchClasses, bassPitchClass: rootPitchClass)
            else { return nil }

            let pool = ChordQuality.allCases.filter { $0 != chord.quality }.shuffled(using: &rng)
            var choices = Array(pool.prefix(3)) + [chord.quality]
            choices.shuffle(using: &rng)

            return GeneratedExercise(
                kind: .chordQuality,
                prompt: "Quelle est la qualité de l'accord construit sur le \(romanNumerals[degree]) degré ?",
                notes: triad, stacked: true,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: chord.quality)!)
        }
    }

    private static func keySignatureExercise(key: MusicalKey,
                                             rng: inout some RandomNumberGenerator) -> GeneratedExercise {
        let correct = key.accidentalCount
        var distractors = Set((0...7).filter { $0 != correct })
        // Les deux voisins immédiats d'abord — c'est là que l'hésitation réelle se joue, pas
        // entre zéro et sept altérations.
        var pool = [correct - 1, correct + 1].filter { (0...7).contains($0) && $0 != correct }
        pool.shuffle(using: &rng)
        var chosen = Set(pool.prefix(2))
        distractors.subtract(chosen)
        while chosen.count < 3, let extra = distractors.randomElement(using: &rng) {
            chosen.insert(extra)
            distractors.remove(extra)
        }
        var choices = (Array(chosen) + [correct]).map(String.init)
        choices.shuffle(using: &rng)
        let word = key.prefersFlats ? "bémol" : "dièse"
        return GeneratedExercise(
            kind: .keySignature,
            prompt: "Combien d'altérations (\(word)s) dans \(key.name()) ?",
            choices: choices, correctIndex: choices.firstIndex(of: String(correct))!)
    }
}
