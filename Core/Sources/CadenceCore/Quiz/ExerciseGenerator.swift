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
        // Calculée UNE fois pour tout le morceau — voir `HarmonicAnalyzer.canonicalMeasureMap` :
        // un fichier exporté avec une reprise déjà "déroulée" numérote sinon deux fois la même
        // mesure imprimée, la seconde fois sous un numéro qui n'existe nulle part sur la partition.
        let canonicalMeasure = HarmonicAnalyzer.canonicalMeasureMap(for: notes)
        // UNE tonalité par mesure IMPRIMÉE, pas une par note — voir `localKeysByMeasure` : deux
        // notes à peine séparées dans le temps ne doivent jamais recevoir des tonalités
        // différentes sous prétexte que leurs fenêtres de détection, centrées chacune sur SA
        // propre note, glissaient légèrement l'une par rapport à l'autre.
        let localKeys = localKeysByMeasure(notes: notes, canonicalMeasure: canonicalMeasure)
        var exercises = intervalExercises(from: notes, canonicalMeasure: canonicalMeasure, localKeys: localKeys, rng: &rng)
        exercises += chordExercises(from: notes, canonicalMeasure: canonicalMeasure, localKeys: localKeys, rng: &rng)
        exercises.shuffle(using: &rng)
        return exercises
    }

    /// Calcule la tonalité locale UNE FOIS par mesure imprimée (après repli des répétitions —
    /// voir `HarmonicAnalyzer.canonicalMeasureMap`), ancrée sur le début de sa PREMIÈRE
    /// occurrence dans le fichier.
    ///
    /// **Pourquoi pas une détection centrée sur l'instant de chaque note.** Deux notes séparées
    /// de quelques centaines de millisecondes à peine, dans la MÊME mesure, se voyaient parfois
    /// attribuer des tonalités différentes : leurs fenêtres de quelques secondes, centrées
    /// chacune sur sa propre note, ne couvraient pas exactement le même voisinage, et un
    /// déplacement de fenêtre suffisait à faire pencher la corrélation statistique d'un côté ou
    /// de l'autre — un scintillement à l'intérieur d'une seule mesure, pas une simple imprécision
    /// ponctuelle. Ancrer une fenêtre unique par mesure élimine cette instabilité : toutes les
    /// notes d'une même mesure partagent alors exactement la même tonalité affichée.
    private static func localKeysByMeasure(notes: [MIDINoteEvent],
                                           canonicalMeasure: [Int: Int]) -> [Int: MusicalKey] {
        let byCanonical = Dictionary(grouping: notes) { canonicalMeasure[$0.measure] ?? $0.measure }
        var result: [Int: MusicalKey] = [:]
        for (canon, groupNotes) in byCanonical {
            guard let anchor = groupNotes.map(\.startSeconds).min() else { continue }
            result[canon] = KeyDetector.detectLocalKey(from: notes, around: anchor)
        }
        return result
    }

    private static func intervalExercises(from notes: [MIDINoteEvent], canonicalMeasure: [Int: Int],
                                          localKeys: [Int: MusicalKey],
                                          rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        // UNE SEULE voix, pas le fichier entier mélangé — voir `HarmonicAnalyzer.melodicLine`.
        // Sans cet isolement, un morceau à deux mains produisait des "intervalles" entre la
        // dernière note de la mélodie et la note de basse suivante : une paire qui n'existe pas
        // musicalement, sans réponse juste possible.
        let melody = HarmonicAnalyzer.melodicLine(from: notes)
        let coherentIntervals = HarmonicAnalyzer.melodicIntervals(from: melody).filter {
            // Un silence trop long entre deux notes veut dire qu'on a franchi une frontière de
            // phrase, pas qu'on a bougé d'un intervalle : la relation qu'on demanderait de nommer
            // ne serait plus un geste mélodique continu. La frontière de MESURE, elle, n'est pas
            // un critère d'exclusion : deux notes réellement consécutives dans le morceau (aucun
            // silence entre elles) forment un intervalle valide même quand l'une appartient à la
            // mesure imprimée précédente et l'autre à la suivante — un enchaînement rapide en fin
            // de mesure en est un exemple courant. Ce qui rendait ça illisible n'était pas
            // l'intervalle lui-même mais l'affichage : un exercice étiqueté "Mesure 13" tout court
            // alors que sa seconde note vit dans la mesure 14 semblait "inventer" une note absente
            // de la page. La correction porte sur l'étiquette (voir plus bas, `sourceMeasureEnd`
            // et `GeneratedExercise.sourceMeasureLabel`), pas sur l'exclusion de la paire.
            $0.to.startSeconds - $0.from.startSeconds <= 2.0
        }
        return coherentIntervals.map { interval in
            let choices = intervalChoices(correct: interval.quality, rng: &rng)
            let measure = canonicalMeasure[interval.from.measure] ?? interval.from.measure
            let measureEnd = canonicalMeasure[interval.to.measure] ?? interval.to.measure
            // LOCALE, pas globale — voir `GeneratedExercise.displayKey` : un morceau qui module
            // n'a pas une seule tonalité pour tout le fichier, donc pas davantage une seule
            // convention d'écriture pour chaque exercice qui en est tiré. Prise dans `localKeys`
            // (une par mesure, jamais recalculée par note) pour que deux exercices de la MÊME
            // mesure ne puissent jamais afficher deux tonalités différentes. Quand l'intervalle
            // enjambe une frontière, on garde la tonalité de la mesure DE DÉPART : c'est la note
            // qu'on lit en premier sur la portée qui ancre la lecture de l'intervalle.
            let localKey = localKeys[measure] ?? KeyDetector.detectKey(from: notes)
            return GeneratedExercise(
                kind: .interval, prompt: "Quel est cet intervalle ?",
                notes: simpleIntervalDisplayPitches(from: interval.from.pitchClass, quality: interval.quality,
                                                    ascending: interval.isAscending),
                stacked: false,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: interval.quality)!,
                explanation: intervalExplanation(interval.quality),
                sourceMeasure: measure,
                sourceMeasureEnd: measureEnd == measure ? nil : measureEnd,
                displayKey: localKey)
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
        // 60 = do central, et SURTOUT un multiple de 12 : ajouter la classe de hauteur (0-11) à
        // une base qui n'en est pas un multiple aurait décalé la classe de hauteur RÉSULTANTE —
        // c'est exactement le bug corrigé ici. Une base de 55 (sol3, 55 % 12 = 7) donnait une
        // note affichée dont la classe de hauteur était systématiquement décalée de 7 demi-tons
        // par rapport à la vraie note du morceau : un ré (classe 2) devenait un la (classe 9)
        // à l'écran. Avec 60 % 12 == 0, `60 + pitchClass` reproduit EXACTEMENT `pitchClass`.
        let fromDisplay = 60 + pitchClass
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

    private static func chordExercises(from notes: [MIDINoteEvent], canonicalMeasure: [Int: Int],
                                       localKeys: [Int: MusicalKey],
                                       rng: inout some RandomNumberGenerator) -> [GeneratedExercise] {
        HarmonicAnalyzer.clusterChords(from: notes).compactMap { cluster -> GeneratedExercise? in
            guard let chord = ChordIdentifier.identify(pitchClasses: cluster.pitchClasses,
                                                       bassPitchClass: cluster.bassPitchClass)
            else { return nil }

            let pool = ChordQuality.allCases.filter { $0 != chord.quality }.shuffled(using: &rng)
            var choices = Array(pool.prefix(3)) + [chord.quality]
            choices.shuffle(using: &rng)

            let rawMeasure = cluster.notes.first?.measure
            let measure = rawMeasure.map { canonicalMeasure[$0] ?? $0 }
            let localKey = measure.flatMap { localKeys[$0] } ?? KeyDetector.detectKey(from: notes)
            return GeneratedExercise(
                kind: .chordQuality, prompt: "Quelle est la qualité de cet accord ?",
                notes: centeredForDisplay(cluster.notes.map(\.pitch).sorted()), stacked: true,
                choices: choices.map(\.displayName),
                correctIndex: choices.firstIndex(of: chord.quality)!,
                explanation: chordExplanation(chord.quality),
                sourceMeasure: measure,
                displayKey: localKey)
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
                explanation: explanation, displayKey: key)
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
                explanation: explanation, displayKey: key)
        }
    }

    // MARK: - Le parcours d'une gamme : plusieurs ÉTAPES distinctes, pas un seul quiz fourre-tout

    /// Les arrêts du parcours d'une gamme — chacun une compétence à part, qu'un musicien
    /// travaille séparément en pratique : nommer les notes, savoir situer un degré dans
    /// l'échelle, entendre/lire les intervalles qu'elles forment avec la tonique, harmoniser
    /// chaque degré en accord, connaître l'armure, et enfin tout mélanger contre la montre.
    ///
    /// **Pourquoi `noteNames` et `degrees` sont deux thèmes séparés, pas un seul "Notes" mélangé.**
    /// Nommer une note ("do") et situer un degré ("le troisième degré") sont deux réflexes
    /// différents, chacun avec sa propre logique de réponse — les mélanger dans la même série
    /// oblige à changer de logique à chaque question, ce qui empêche justement l'automatisme
    /// qu'une série homogène permet de construire en enchaînant vite.
    public enum ScaleFocus: String, CaseIterable, Sendable {
        case noteNames, degrees, intervals, chords, keySignature, speed

        public var displayName: String {
            switch self {
            case .noteNames: "Notes"
            case .degrees: "Degrés"
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
        case .noteNames:
            return noteSpellingExercises(key: key, rng: &rng).shuffled(using: &rng)
        case .degrees:
            return scaleDegreeExercises(key: key, rng: &rng).shuffled(using: &rng)
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
                explanation: intervalExplanation(quality), displayKey: key)
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
                explanation: chordExplanation(chord.quality), displayKey: key)
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
            explanation: explanation, displayKey: key)
    }
}
