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
                notes: simpleIntervalDisplayPitches(from: interval.from.pitchClass, quality: interval.quality,
                                                    ascending: interval.isAscending),
                stacked: false,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: interval.quality)!,
                explanation: intervalExplanation(interval.quality))
        }
    }

    /// Reconstruit la paire de hauteurs à AFFICHER depuis la seule qualité SIMPLE de l'intervalle
    /// — jamais depuis l'écart réel entre les deux notes du morceau.
    ///
    /// **Pourquoi.** `MelodicInterval.quality` ramène toujours un intervalle composé (une dixième,
    /// une dix-septième…) à sa forme simple, dans l'octave — c'est CETTE forme simple qu'on
    /// propose comme réponse ("tierce mineure", jamais "dixième mineure"). Afficher l'écart RÉEL
    /// entre les deux notes, qui peut dépasser deux octaves dans un morceau enregistré normalement
    /// (une basse et une mélodie éloignées, par exemple), montrerait une portée bien plus large que
    /// ce que le nom de la réponse suggère — et déborderait de l'écran par la même occasion.
    /// Repartir de la seule classe de hauteur de la note de départ, posée dans une octave
    /// confortable, garantit que l'écart affiché correspond exactement, toujours, à la qualité
    /// demandée.
    private static func simpleIntervalDisplayPitches(from pitchClass: Int, quality: IntervalQuality,
                                                     ascending: Bool) -> [Int] {
        let fromDisplay = 55 + pitchClass // ré3 à ré4 selon la classe : toujours près de la portée
        let toDisplay = ascending ? fromDisplay + quality.rawValue : fromDisplay - quality.rawValue
        return [fromDisplay, toDisplay]
    }

    /// La méthode plutôt que le nom appris par cœur : COMPTER les demi-tons est ce qui reste
    /// utilisable sur une portée qu'on n'a jamais vue, contrairement à reconnaître une forme au
    /// premier coup d'œil.
    private static func intervalExplanation(_ quality: IntervalQuality) -> String {
        "Compte les demi-tons entre les deux notes : il y en a \(quality.rawValue), " +
        "ce qui correspond à \(article(for: quality)) \(quality.displayName.lowercased())."
    }

    /// "un" seulement devant unisson et triton (masculins) ; tous les autres noms d'intervalle
    /// français — seconde, tierce, quarte, quinte, sixte, septième, octave — sont féminins.
    private static func article(for quality: IntervalQuality) -> String {
        switch quality {
        case .unison, .tritone: "un"
        default: "une"
        }
    }

    /// Décale tout un groupe de hauteurs d'un nombre ENTIER d'octaves, pour que la plus grave
    /// tombe près d'une zone confortable autour de la portée — sans jamais changer l'écart entre
    /// les notes, donc ni l'accord ni l'intervalle qu'elles forment, seulement leur registre
    /// D'AFFICHAGE.
    ///
    /// **Pourquoi c'est nécessaire.** Ces hauteurs viennent d'un morceau RÉEL, pas d'une gamme
    /// choisie à la main — rien ne garantit qu'elles tombent près du do central. Une mélodie
    /// enregistrée deux octaves au-dessus (un synthé aigu, par exemple) produirait une portée
    /// couverte de lignes supplémentaires au point de chevaucher le texte de la question
    /// au-dessus. Décaler par octaves ENTIÈRES préserve exactement la qualité de l'intervalle ou
    /// de l'accord (elle ne dépend que de l'écart en demi-tons, invariant par octave) — seul le
    /// registre affiché change.
    private static func centeredForDisplay(_ pitches: [Int]) -> [Int] {
        guard let lowest = pitches.min() else { return pitches }
        let comfortableLow = 55 // sol3 : sous la portée de peu, la plupart des notes réelles n'ont alors besoin que d'une ou deux lignes supplémentaires au plus
        let octaves = Int((Double(comfortableLow - lowest) / 12).rounded())
        return pitches.map { $0 + octaves * 12 }
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
                notes: centeredForDisplay(cluster.notes.map(\.pitch).sorted()), stacked: true,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: chord.quality)!,
                explanation: chordExplanation(chord.quality))
        }
    }

    /// La STRUCTURE de l'accord — quelles tierces s'empilent — plutôt qu'un simple rappel de son
    /// nom : c'est cette structure qu'on reconnaît sur une portée, le nom vient après.
    private static func chordExplanation(_ quality: ChordQuality) -> String {
        switch quality {
        case .major: "Une tierce majeure (4 demi-tons) puis une tierce mineure (3 demi-tons) au-dessus de la fondamentale : l'accord est majeur."
        case .minor: "Une tierce mineure (3 demi-tons) puis une tierce majeure (4 demi-tons) au-dessus de la fondamentale : l'accord est mineur."
        case .diminished: "Deux tierces mineures empilées (3 puis 3 demi-tons) : la quinte se retrouve diminuée."
        case .augmented: "Deux tierces majeures empilées (4 puis 4 demi-tons) : la quinte se retrouve augmentée."
        case .sus2: "Une seconde majeure remplace la tierce : ni majeur ni mineur, l'accord reste \"suspendu\"."
        case .sus4: "Une quarte juste remplace la tierce : ni majeur ni mineur, l'accord reste \"suspendu\"."
        case .dominantSeventh: "Un accord majeur, plus une septième mineure au-dessus de la fondamentale."
        case .majorSeventh: "Un accord majeur, plus une septième majeure au-dessus de la fondamentale."
        case .minorSeventh: "Un accord mineur, plus une septième mineure au-dessus de la fondamentale."
        case .diminishedSeventh: "Un accord diminué, plus une septième diminuée : chaque étage est une tierce mineure."
        case .halfDiminishedSeventh: "Un accord diminué, mais avec une septième mineure plutôt que diminuée au sommet."
        case .minorMajorSeventh: "Un accord mineur, plus une septième MAJEURE au-dessus de la fondamentale."
        case .augmentedSeventh: "Un accord augmenté, plus une septième mineure au-dessus de la fondamentale."
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
            let tonicName = NoteNaming.name(forPitchClass: key.tonicPitchClass, preferFlats: key.prefersFlats)
            let explanation = degree == 0
                ? "C'est la tonique elle-même — le point de départ de la gamme, degré \(romanNumerals[0])."
                : "En partant de la tonique (\(tonicName)) et en montant note par note dans la gamme, " +
                  "c'est la \(degree + 1)ᵉ note : le degré \(romanNumerals[degree])."
            return GeneratedExercise(
                kind: .scaleDegree, prompt: "Quel degré de \(key.name()) est cette note ?",
                notes: [pitch], stacked: false,
                choices: indices.map { romanNumerals[$0] },
                correctIndex: indices.firstIndex(of: degree)!,
                explanation: explanation)
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
            let word = key.prefersFlats ? "bémols" : "dièses"
            let explanation = "\(key.name().capitalized) s'écrit avec des \(word) : cette hauteur se nomme donc " +
                "\(correctName), jamais avec l'autre convention, même si le son au piano serait identique."
            return GeneratedExercise(
                kind: .noteSpelling, prompt: "Quel est le nom de cette note ?",
                notes: [pitch], stacked: false,
                choices: choices, correctIndex: choices.firstIndex(of: correctName)!,
                explanation: explanation)
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
                correctIndex: choices.firstIndex(of: quality)!,
                explanation: intervalExplanation(quality))
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
                correctIndex: choices.firstIndex(of: chord.quality)!,
                explanation: chordExplanation(chord.quality))
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
        let explanation = correct == 0
            ? "\(key.name().capitalized) est la seule tonalité majeure sans aucune altération : do majeur."
            : "Sur le cercle des quintes, \(key.name()) est la \(correct)ᵉ tonalité côté \(word)s en partant de do majeur — elle en compte donc \(correct)."
        return GeneratedExercise(
            kind: .keySignature,
            prompt: "Combien d'altérations (\(word)s) dans \(key.name()) ?",
            choices: choices, correctIndex: choices.firstIndex(of: String(correct))!,
            explanation: explanation)
    }
}
