import XCTest
@testable import CadenceCore

final class ExerciseGeneratorTests: XCTestCase {

    private func note(_ pitch: Int, at start: Double, duration: Double = 0.4) -> MIDINoteEvent {
        MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: duration, track: 0, channel: 0)
    }

    // MARK: - Tonalité locale, pas globale (un morceau qui module)

    /// Régression exacte du bogue signalé sur un vrai fichier ("With Key Change") : un morceau
    /// dont la première moitié est nettement côté dièses et la seconde nettement côté bémols ne
    /// doit PAS donner à un exercice tiré du DÉBUT la tonalité détectée sur l'ENSEMBLE du fichier
    /// — cette moyenne globale peut retomber sur une tonalité qui n'a ni les dièses ni les
    /// bémols réellement en vigueur à cet instant précis.
    func testExerciseFromTheFirstHalfOfAModulatingPieceUsesItsOwnLocalKey() {
        func noteAt(_ pitch: Int, start: Double, measure: Int) -> MIDINoteEvent {
            MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: 0.8,
                         track: 0, channel: 0, measure: measure)
        }

        // La majeur (3 dièses) joué longuement au début, mesure 1...
        let firstHalfPitches = [69, 71, 73, 74, 76, 78, 80] // la, si, do#, ré, mi, fa#, sol#
        let firstHalf = firstHalfPitches.enumerated().map { i, p in noteAt(p, start: Double(i) * 0.9, measure: 1) }
        // ...fa majeur (1 bémol) joué tout aussi longuement, bien plus tard, mesure 2 : de quoi
        // tirer une détection GLOBALE loin de "la majeur, 3 dièses" si elle moyennait tout le
        // fichier au lieu de regarder localement autour de chaque exercice.
        let secondHalfPitches = [65, 67, 69, 70, 72, 74, 76] // fa, sol, la, si♭, do, ré, mi
        let secondHalf = secondHalfPitches.enumerated().map { i, p in noteAt(p, start: 20 + Double(i) * 0.9, measure: 2) }

        var rng = SeededGenerator(seed: 60)
        let exercises = ExerciseGenerator.fromImportedMusic(notes: firstHalf + secondHalf, rng: &rng)

        let fromTheStart = exercises.filter { $0.kind == .interval && $0.sourceMeasure == 1 }
        XCTAssertFalse(fromTheStart.isEmpty)
        XCTAssertTrue(fromTheStart.allSatisfy { $0.displayKey.accidentalCount == 3 && !$0.displayKey.prefersFlats },
                      "un exercice tiré du début (la majeur) ne devrait jamais hériter d'une tonalité détectée sur tout le fichier")

        let fromTheEnd = exercises.filter { $0.kind == .interval && $0.sourceMeasure == 2 }
        XCTAssertFalse(fromTheEnd.isEmpty)
        XCTAssertTrue(fromTheEnd.allSatisfy { $0.displayKey.accidentalCount == 1 && $0.displayKey.prefersFlats },
                      "un exercice tiré de la fin (fa majeur) devrait porter SA propre tonalité, pas celle du début")
    }

    /// Régression exacte du second bogue trouvé sur le même vrai fichier, une mesure plus loin :
    /// deux exercices tirés de la MÊME mesure imprimée ne doivent jamais afficher deux tonalités
    /// différentes — même si leurs notes sont séparées de quelques dixièmes de seconde à peine.
    /// Avant ce correctif, la fenêtre de détection locale était centrée sur l'instant de CHAQUE
    /// note individuellement ; un déplacement minime de cette fenêtre entre deux notes voisines
    /// suffisait à faire pencher la corrélation statistique d'une tonalité vers une tonalité
    /// voisine, produisant un scintillement à l'intérieur d'une seule mesure.
    func testAllExercisesFromTheSameMeasureShareTheExactSameKey() {
        func noteAt(_ pitch: Int, start: Double, measure: Int) -> MIDINoteEvent {
            MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: 0.15,
                         track: 0, channel: 0, measure: measure)
        }

        // Une seule mesure, rapide (les notes ne sont séparées que de 0,15 s, comme une croche
        // à tempo réel) — exactement les conditions où l'ancienne fenêtre par note dérivait.
        let pitches = [70, 65, 60, 69, 65, 60, 67, 64, 60, 69, 65, 60] // ré, fa, do, la, fa, do, sol, mi, do…
        let notes = pitches.enumerated().map { i, p in noteAt(p, start: Double(i) * 0.15, measure: 18) }

        var rng = SeededGenerator(seed: 61)
        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        let fromMeasure18 = exercises.filter { $0.kind == .interval && $0.sourceMeasure == 18 }

        XCTAssertGreaterThan(fromMeasure18.count, 1, "il faut au moins deux exercices pour vérifier qu'ils s'accordent")
        let firstKey = fromMeasure18[0].displayKey
        XCTAssertTrue(fromMeasure18.allSatisfy { $0.displayKey == firstKey },
                      "tous les exercices d'UNE MÊME mesure doivent partager exactement la même tonalité")
    }

    /// Régression exacte du bogue "il m'a inventé une armure, y'a pas de bémol" : un passage dont
    /// le contenu mélodique ressemble statistiquement à fa majeur (1 bémol) doit malgré tout
    /// afficher do majeur (0 altération) quand le FICHIER déclare lui-même do majeur à cet
    /// endroit — l'armure écrite prime toujours sur une corrélation statistique, aussi plausible
    /// soit-elle.
    func testDeclaredKeySignatureOverridesStatisticalGuessing() {
        func noteAt(_ pitch: Int, start: Double, declaredKey: MusicalKey?) -> MIDINoteEvent {
            MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: 0.15,
                         track: 0, channel: 0, measure: 18, declaredKey: declaredKey)
        }
        let cMajor = MusicalKey(tonicPitchClass: 0, isMajor: true)
        // Un motif fa-do-la-fa-do-sol-mi-do : très fa-majeur d'allure (beaucoup de fa et de do,
        // aucun si) si on le laissait deviner statistiquement, mais le fichier déclare do majeur.
        let pitches = [77, 72, 81, 77, 72, 79, 76, 72]
        let notes = pitches.enumerated().map { i, p in noteAt(p, start: Double(i) * 0.15, declaredKey: cMajor) }

        var rng = SeededGenerator(seed: 64)
        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        let fromMeasure18 = exercises.filter { $0.kind == .interval && $0.sourceMeasure == 18 }

        XCTAssertFalse(fromMeasure18.isEmpty)
        XCTAssertTrue(fromMeasure18.allSatisfy { $0.displayKey == cMajor },
                      "l'armure déclarée par le fichier doit toujours l'emporter sur une simple estimation statistique")
    }

    // MARK: - Depuis un morceau

    /// Régression : une mélodie (piste 0) et une basse (piste 1) qui jouent EN MÊME TEMPS ne
    /// doivent jamais produire un "intervalle" entre une note de l'une et une note de l'autre —
    /// voir `HarmonicAnalyzer.melodicLine`. Sans cet isolement, trier toutes les notes par
    /// instant de départ mélangeait les deux mains et produisait des paires qui n'existent pas
    /// musicalement.
    func testIntervalsNeverMixTwoDifferentVoices() {
        // Durée étendue à l'écart complet (1s) — des notes réellement ENCHAÎNÉES, sans silence
        // entre elles, la seule condition que `isMusicallyContinuous` laisse désormais passer.
        let melody = [note(72, at: 0, duration: 1), note(74, at: 1, duration: 1), note(76, at: 2)] // do5-ré5-mi5, piste 0
        let bass = [MIDINoteEvent(pitch: 36, velocity: 80, startSeconds: 0.5, durationSeconds: 0.4, track: 1, channel: 0),
                   MIDINoteEvent(pitch: 38, velocity: 80, startSeconds: 1.5, durationSeconds: 0.4, track: 1, channel: 0)]
        var rng = SeededGenerator(seed: 40)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: melody + bass, rng: &rng)
        let intervalCount = exercises.filter { $0.kind == .interval }.count

        // Trois notes de mélodie ⇒ exactement DEUX intervalles consécutifs. Si les notes de basse
        // s'étaient mélangées (les 5 notes triées par instant donneraient 4 paires), ce compte
        // serait plus élevé — la seule façon de le vérifier depuis l'extérieur, puisque
        // `simpleIntervalDisplayPitches` retranspose de toute façon l'affichage.
        XCTAssertEqual(intervalCount, 2, "des notes de basse se sont probablement mélangées à la mélodie")
    }

    /// Régression : une longue pause entre deux notes de la MÊME voix ne doit pas non plus
    /// produire un exercice — ce n'est pas un geste mélodique continu, mais deux phrases
    /// distinctes.
    func testLongSilenceBetweenNotesProducesNoIntervalAcrossIt() {
        let notes = [note(60, at: 0), note(64, at: 10)] // même voix, 10 secondes d'écart
        var rng = SeededGenerator(seed: 41)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        XCTAssertFalse(exercises.contains { $0.kind == .interval })
    }

    /// Un intervalle PEUT relier la dernière note d'une mesure imprimée à la première de la
    /// suivante — c'est une paire réellement consécutive dans le morceau, aucun silence entre les
    /// deux. Ce qui semblait "inventer une note" n'était pas l'intervalle mais son étiquette :
    /// affichée comme une simple "Mesure 13" alors que la seconde note vit déjà dans la mesure 14,
    /// elle ne pouvait être vérifiée sur une seule page de la partition. La correction nomme les
    /// deux mesures plutôt que d'exclure la paire.
    func testIntervalCrossingAMeasureBoundaryLabelsBothMeasures() {
        func noteAt(_ pitch: Int, start: Double, measure: Int) -> MIDINoteEvent {
            MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: 0.13,
                         track: 0, channel: 0, measure: measure)
        }
        // La dernière note de la mesure 13 et la première de la mesure 14 s'enchaînent sans le
        // moindre silence (0,13 s d'écart, comme un vrai passage rapide).
        let notes = [
            noteAt(65, start: 0.0, measure: 13),   // fa4, dernière note de la mesure 13
            noteAt(76, start: 0.13, measure: 14),  // mi5, première note de la mesure 14 : une 7e majeure plus haut
        ]
        var rng = SeededGenerator(seed: 62)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        guard let interval = exercises.first(where: { $0.kind == .interval }) else {
            return XCTFail("deux notes consécutives sans silence doivent produire un exercice d'intervalle, même à cheval sur une frontière de mesure")
        }
        XCTAssertEqual(interval.sourceMeasure, 13)
        XCTAssertEqual(interval.sourceMeasureEnd, 14)
        XCTAssertEqual(interval.sourceMeasureLabel, "Mesure 13 et 14")
    }

    /// Régression exacte du bogue signalé sur un fichier réel ("Comptine d'un autre été", capture
    /// Rousseau MIDI) : quand main droite et main gauche sont mélangées sur la même piste MIDI
    /// avec un fort recouvrement, `fromImportedMusic` ne doit produire AUCUN exercice
    /// d'intervalle (voir `HarmonicAnalyzer.testMelodicLineIsEmptyWhenASingleVoiceMixesTwoHands...`)
    /// — mais les exercices d'accord, qui ne dépendent pas de cette séparation par voix, doivent
    /// rester disponibles : le morceau reste utilisable, seule la famille d'exercices qu'on ne
    /// peut pas garantir fiable disparaît.
    func testImportedMusicWithMixedHandsOnOneTrackProducesNoIntervalButKeepsChords() {
        var notes: [MIDINoteEvent] = []
        for i in 0..<20 {
            let start = Double(i) * 0.35
            notes.append(note(64 + (i % 5), at: start, duration: 0.3))
            if i % 4 == 0 {
                // Un accord de main gauche, plaqué et tenu longtemps sous la ligne rapide.
                notes.append(contentsOf: [
                    MIDINoteEvent(pitch: 40, velocity: 80, startSeconds: start, durationSeconds: 1.3, track: 0, channel: 0),
                    MIDINoteEvent(pitch: 47, velocity: 80, startSeconds: start, durationSeconds: 1.3, track: 0, channel: 0),
                    MIDINoteEvent(pitch: 52, velocity: 80, startSeconds: start, durationSeconds: 1.3, track: 0, channel: 0),
                ])
            }
        }
        var rng = SeededGenerator(seed: 70)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)

        XCTAssertFalse(exercises.contains { $0.kind == .interval },
                       "deux mains mélangées sur une seule piste ne doivent produire aucun exercice d'intervalle")
        XCTAssertTrue(exercises.contains { $0.kind == .chordQuality },
                      "les accords plaqués (main gauche) doivent rester reconnus malgré l'absence de mélodie fiable")
    }

    /// Régression exacte du second bogue trouvé sur "Drowning Love [With Key Change]" (seconde
    /// répétition du couplet) : une mesure jamais repliée (fin d'un couplet répété, unique) suivie
    /// d'une mesure repliée sur un numéro bien plus PETIT (début du couplet suivant, qui recommence
    /// à reprendre le tout premier) ne doit JAMAIS afficher une étiquette à numéros inversés comme
    /// "Mesure 31 et 16" — un seul numéro (celui de départ) doit rester.
    func testIntervalCrossingIntoAnEarlierFoldedMeasureLabelsOnlyTheStart() {
        func noteAt(_ pitch: Int, start: Double, measure: Int) -> MIDINoteEvent {
            MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: 0.13,
                         track: 0, channel: 0, measure: measure)
        }
        // La mesure 31, jamais vue ailleurs (jamais repliée) ; la mesure 32 reprend NOTE POUR NOTE
        // la mesure 16 — comme le début d'un second couplet qui recommence sur le premier — ET sa
        // mesure voisine (33) confirme elle aussi un bloc de deux mesures, pour que le repli soit
        // un vrai repli confirmé, pas une coïncidence isolée qu'on aurait déjà dû rejeter ailleurs.
        let notes = [
            noteAt(65, start: 0.0, measure: 16), noteAt(69, start: 0.13, measure: 17), // bloc "premier couplet"
            noteAt(72, start: 10.0, measure: 31),                                        // unique, jamais repliée
            noteAt(65, start: 10.13, measure: 32), noteAt(69, start: 10.26, measure: 33), // = bloc ci-dessus
        ]
        var rng = SeededGenerator(seed: 65)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        guard let interval = exercises.first(where: { $0.kind == .interval && $0.sourceMeasure == 31 }) else {
            return XCTFail("attendu un exercice d'intervalle partant de la mesure 31")
        }
        XCTAssertNil(interval.sourceMeasureEnd,
                     "jamais une seconde mesure numériquement antérieure à la première")
        XCTAssertEqual(interval.sourceMeasureLabel, "Mesure 31")
    }

    /// Un intervalle contenu dans une seule mesure imprimée ne doit PAS afficher une seconde
    /// mesure — `sourceMeasureEnd` doit rester `nil` et l'étiquette ne montrer qu'un seul numéro.
    func testIntervalWithinOneMeasureLabelsOnlyThatMeasure() {
        let notes = [note(60, at: 0), note(64, at: 0.4)] // do5-mi5, même mesure implicite (1)
        var rng = SeededGenerator(seed: 63)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        guard let interval = exercises.first(where: { $0.kind == .interval }) else {
            return XCTFail("attendu au moins un exercice d'intervalle")
        }
        XCTAssertNil(interval.sourceMeasureEnd)
        XCTAssertEqual(interval.sourceMeasureLabel, "Mesure 1")
    }

    func testGeneratesIntervalAndChordExercisesFromMusic() {
        let notes =
            [note(60, at: 0), note(64, at: 0), note(67, at: 0)] +   // accord de do majeur
            [note(60, at: 1), note(64, at: 1.5), note(67, at: 2)]    // mélodie : deux intervalles
        var rng = SeededGenerator(seed: 1)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)

        XCTAssertTrue(exercises.contains { $0.kind == .chordQuality })
        XCTAssertTrue(exercises.contains { $0.kind == .interval })
    }

    func testChordExerciseShowsNotesStackedNotSequential() {
        let notes = [note(60, at: 0), note(64, at: 0), note(67, at: 0)]
        var rng = SeededGenerator(seed: 2)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        let chordExercise = exercises.first { $0.kind == .chordQuality }

        XCTAssertNotNil(chordExercise)
        XCTAssertTrue(chordExercise?.stacked ?? false)
        XCTAssertEqual(chordExercise?.notes, [60, 64, 67])
    }

    func testChordExerciseChoicesContainTheCorrectQuality() {
        let notes = [note(60, at: 0), note(64, at: 0), note(67, at: 0)] // do majeur
        var rng = SeededGenerator(seed: 3)

        let exercise = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
            .first { $0.kind == .chordQuality }!

        XCTAssertEqual(exercise.choices.count, 4)
        XCTAssertEqual(Set(exercise.choices).count, 4, "les propositions doivent être distinctes")
        XCTAssertEqual(exercise.choices[exercise.correctIndex], ChordQuality.major.displayName)
    }

    /// Régression : un morceau réel enregistré dans un registre extrême (un synthé aigu, par
    /// exemple) ne doit jamais produire un exercice dont les notes affichées débordent au point de
    /// chevaucher le reste de l'écran — voir `centeredForDisplay`.
    func testExtremeRegisterIntervalIsBroughtIntoAComfortableRange() {
        // Durée étendue à l'écart complet — deux notes réellement enchaînées, sans silence noté.
        let notes = [note(96, at: 0, duration: 1), note(103, at: 1)] // très aigu : sol6 à sol7
        var rng = SeededGenerator(seed: 20)

        let exercise = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
            .first { $0.kind == .interval }!

        XCTAssertTrue(exercise.notes.allSatisfy { (40...84).contains($0) },
                      "les notes affichées devraient être ramenées près du do central, pas \(exercise.notes)")
        // L'écart réel (7 demi-tons, une quinte) doit rester intact malgré le recentrage.
        XCTAssertEqual(abs(exercise.notes[1] - exercise.notes[0]), 7)
    }

    func testExtremeRegisterChordIsBroughtIntoAComfortableRange() {
        let notes = [note(96, at: 0), note(100, at: 0), note(103, at: 0)] // do7 majeur, très aigu
        var rng = SeededGenerator(seed: 21)

        let exercise = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
            .first { $0.kind == .chordQuality }!

        XCTAssertTrue(exercise.notes.allSatisfy { (40...84).contains($0) },
                      "les notes affichées devraient être ramenées près du do central, pas \(exercise.notes)")
        // La forme de l'accord (les écarts entre ses notes) doit rester intacte.
        XCTAssertEqual(exercise.notes[1] - exercise.notes[0], 4)
        XCTAssertEqual(exercise.notes[2] - exercise.notes[1], 3)
    }

    /// Régression exacte du bogue signalé sur un vrai fichier ("Drowning Love [With Key
    /// Change]", mesure 9) : deux groupes de notes séparés par un soupir écrit dans la partition
    /// (voir la capture PDF fournie avec le rapport) ne doivent PAS produire un exercice
    /// d'intervalle entre la dernière note du premier groupe et la première du second — même si
    /// l'écart entre elles reste bien en dessous de l'ancien plafond absolu de 2 secondes.
    func testRestBetweenTwoPhrasesProducesNoIntervalAcrossIt() {
        // Reproduit exactement le rapport de silence mesuré sur le fichier réel : une note qui
        // dure 0,135 s, puis un silence de 0,137 s (environ UNE note de plus) avant la suivante —
        // un vrai soupir noté, pas une micro-désynchronisation d'enregistrement.
        let notes = [
            note(71, at: 13.773, duration: 0.135),
            note(71, at: 14.045, duration: 0.135), // 0.137s de silence après la fin de la précédente
        ]
        var rng = SeededGenerator(seed: 90)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)

        XCTAssertFalse(exercises.contains { $0.kind == .interval },
                       "un silence noté entre deux groupes de notes ne doit jamais produire un exercice d'intervalle")
    }

    /// Deux notes séparées d'un tout petit écart, largement sous le silence d'un vrai soupir,
    /// doivent au contraire rester acceptées — un peu de désynchronisation naturelle
    /// d'enregistrement ne doit jamais être confondue avec un vrai temps de silence noté.
    func testTinyRecordingJitterBetweenNotesStillProducesAnInterval() {
        let notes = [
            note(71, at: 13.773, duration: 0.135),
            note(76, at: 13.773 + 0.135 + 0.01, duration: 0.135), // 10 ms de jitter, pas un soupir
        ]
        var rng = SeededGenerator(seed: 91)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)

        XCTAssertTrue(exercises.contains { $0.kind == .interval },
                      "10 ms de désynchronisation ne sont pas un silence noté : l'intervalle doit rester")
    }

    func testUnrecognizableClusterProducesNoChordExercise() {
        // do-do dièse-ré : cluster chromatique, aucun accord tonal reconnu — ne doit PAS
        // produire un exercice avec une "bonne réponse" qui n'existe pas.
        let notes = [note(60, at: 0), note(61, at: 0), note(62, at: 0)]
        var rng = SeededGenerator(seed: 4)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        XCTAssertFalse(exercises.contains { $0.kind == .chordQuality })
    }

    // MARK: - Le parcours d'un morceau importé ("que travailler dans CE fichier ?")

    func testPathRanksThemesByHowMuchTheyAreRepresentedInTheFile() {
        // Un accord de do majeur, plaqué UNE fois : peu de matière pour "Accords". Une mélodie de
        // huit notes qui bouge tout le temps : beaucoup plus de matière pour "Intervalles".
        let chord = [note(60, at: 0), note(64, at: 0), note(67, at: 0)]
        let melody = (0..<8).map { i in note(60 + i, at: 1 + Double(i) * 0.4) }
        var rng = SeededGenerator(seed: 80)

        let path = ExerciseGenerator.pathFromImportedMusic(notes: chord + melody, rng: &rng)

        XCTAssertTrue(path.themes.contains { $0.focus == .intervals })
        XCTAssertTrue(path.themes.contains { $0.focus == .chords })
        let intervalsIndex = path.themes.firstIndex { $0.focus == .intervals }!
        let chordsIndex = path.themes.firstIndex { $0.focus == .chords }!
        XCTAssertLessThan(intervalsIndex, chordsIndex,
                          "la mélodie, bien plus représentée dans ce fichier que l'unique accord, doit passer en premier")
    }

    func testPathAlwaysPutsSpeedLast() {
        let notes = (0..<8).map { i in note(60 + i, at: Double(i) * 0.4) }
        var rng = SeededGenerator(seed: 81)

        let path = ExerciseGenerator.pathFromImportedMusic(notes: notes, rng: &rng)

        XCTAssertEqual(path.themes.last?.focus, .speed, "rapidité, un simple remix des autres thèmes, ne doit jamais passer devant eux")
    }

    func testPathExcludesThemesWithNoContentRatherThanShowingThemEmpty() {
        // Une seule note : aucun intervalle possible (il en faut deux), aucun accord (il faut
        // plusieurs notes simultanées).
        let notes = [note(60, at: 0)]
        var rng = SeededGenerator(seed: 82)

        let path = ExerciseGenerator.pathFromImportedMusic(notes: notes, rng: &rng)

        XCTAssertFalse(path.themes.contains { $0.focus == .intervals })
        XCTAssertFalse(path.themes.contains { $0.focus == .chords })
        XCTAssertTrue(path.themes.allSatisfy { !$0.exercises.isEmpty },
                      "un thème sans exercice ne doit jamais apparaître dans le parcours")
    }

    /// Régression exacte du bogue "Comptine d'un autre été" (voir `HarmonicAnalyzerTests`) : sur
    /// un fichier où deux mains sont mélangées sur une seule voix MIDI, le parcours ne doit
    /// proposer AUCUN thème "Intervalles" — mais "Accords" doit rester disponible.
    func testPathExcludesIntervalsButKeepsChordsWhenHandsAreMixedOnOneTrack() {
        var notes: [MIDINoteEvent] = []
        for i in 0..<20 {
            let start = Double(i) * 0.35
            notes.append(note(64 + (i % 5), at: start, duration: 0.3))
            if i % 4 == 0 {
                notes.append(contentsOf: [
                    MIDINoteEvent(pitch: 40, velocity: 80, startSeconds: start, durationSeconds: 1.3, track: 0, channel: 0),
                    MIDINoteEvent(pitch: 47, velocity: 80, startSeconds: start, durationSeconds: 1.3, track: 0, channel: 0),
                    MIDINoteEvent(pitch: 52, velocity: 80, startSeconds: start, durationSeconds: 1.3, track: 0, channel: 0),
                ])
            }
        }
        var rng = SeededGenerator(seed: 83)

        let path = ExerciseGenerator.pathFromImportedMusic(notes: notes, rng: &rng)

        XCTAssertFalse(path.themes.contains { $0.focus == .intervals })
        XCTAssertTrue(path.themes.contains { $0.focus == .chords })
    }

    func testPathThemesUseTheSongsOwnDetectedKeyForDegreesNotesAndKeySignature() {
        // La majeur (3 dièses) : la, si, do#, ré, mi, fa#, sol# — jouées longuement pour que
        // `KeyDetector` la retrouve sans ambiguïté.
        let pitches = [69, 71, 73, 74, 76, 78, 80]
        let notes = pitches.enumerated().map { i, p in note(p, at: Double(i) * 0.8, duration: 0.75) }
        var rng = SeededGenerator(seed: 84)

        let path = ExerciseGenerator.pathFromImportedMusic(notes: notes, rng: &rng)

        XCTAssertEqual(path.key.accidentalCount, 3)
        XCTAssertFalse(path.key.prefersFlats)
        for theme in path.themes where [.degrees, .noteNames, .keySignature].contains(theme.focus) {
            XCTAssertTrue(theme.exercises.allSatisfy { $0.displayKey == path.key },
                          "\(theme.focus) doit utiliser la tonalité détectée DE CE MORCEAU, pas une autre")
        }
    }

    // MARK: - Depuis une gamme, sans morceau

    func testScaleProducesSevenDegreeExercises() {
        let key = MusicalKey(tonicPitchClass: 4, isMajor: true) // mi majeur
        var rng = SeededGenerator(seed: 5)

        let exercises = ExerciseGenerator.fromScale(key: key, rng: &rng)
        let degreeExercises = exercises.filter { $0.kind == .scaleDegree }

        XCTAssertEqual(degreeExercises.count, 7)
        // Un seul son par exercice de degré : on situe UNE note, pas un intervalle.
        XCTAssertTrue(degreeExercises.allSatisfy { $0.notes.count == 1 })
    }

    func testScaleDegreeChoiceIsCorrectRomanNumeral() {
        let key = MusicalKey(tonicPitchClass: 0, isMajor: true) // do majeur : degrés = pitches 60..71 (blanches)
        var rng = SeededGenerator(seed: 6)

        let exercises = ExerciseGenerator.fromScale(key: key, rng: &rng)
        let tonicExercise = exercises.first { $0.kind == .scaleDegree && $0.notes == [60] }

        XCTAssertNotNil(tonicExercise)
        XCTAssertEqual(tonicExercise?.choices[tonicExercise!.correctIndex], "I")
    }

    func testScaleProducesNoteNamingExercisesInTheRightConvention() {
        let key = MusicalKey(tonicPitchClass: 5, isMajor: true) // fa majeur : bémols
        var rng = SeededGenerator(seed: 7)

        let exercises = ExerciseGenerator.fromScale(key: key, rng: &rng)
        let naming = exercises.filter { $0.kind == .noteSpelling }

        XCTAssertEqual(naming.count, 7)
        // Fa majeur a un si bémol (pitch class 10) dans sa gamme — vérifie que l'orthographe
        // choisie est bien "Si♭" et pas "La♯", pour la convention à bémols de cette tonalité.
        let siBemol = naming.first { $0.notes.first.map { $0 % 12 } == 10 }
        XCTAssertEqual(siBemol?.choices[siBemol!.correctIndex], "Si♭")
    }

    func testKeySignatureExerciseMatchesKnownCircleOfFifths() {
        var rng = SeededGenerator(seed: 8)

        let eMajor = MusicalKey(tonicPitchClass: 4, isMajor: true) // mi majeur : 4 dièses
        let signature = ExerciseGenerator.fromScale(key: eMajor, rng: &rng)
            .first { $0.kind == .keySignature }!
        XCTAssertEqual(signature.choices[signature.correctIndex], "4")

        let bFlatMajor = MusicalKey(tonicPitchClass: 10, isMajor: true) // si♭ majeur : 2 bémols
        let signature2 = ExerciseGenerator.fromScale(key: bFlatMajor, rng: &rng)
            .first { $0.kind == .keySignature }!
        XCTAssertEqual(signature2.choices[signature2.correctIndex], "2")
    }

    /// Régression : do majeur ET la mineur (son relatif) comptent tous deux zéro altération.
    /// L'explication pour "zéro altération" affirmait autrefois que do majeur était "la SEULE
    /// tonalité MAJEURE" sans altération — vrai pour do majeur, mais absurde et trompeur affiché
    /// sur un exercice pris sur la mineur elle-même (une tonalité mineure, pas majeure).
    func testZeroAccidentalExplanationDoesNotClaimTheKeyIsMajorWhenItIsMinor() {
        var rng = SeededGenerator(seed: 9)
        let aMinor = MusicalKey(tonicPitchClass: 9, isMajor: false) // la mineur : 0 altération
        let signature = ExerciseGenerator.fromScale(key: aMinor, rng: &rng)
            .first { $0.kind == .keySignature }!
        XCTAssertEqual(signature.choices[signature.correctIndex], "0")
        XCTAssertFalse(signature.explanation.contains("tonalité majeure"),
                       "l'explication ne doit pas qualifier une gamme mineure de tonalité majeure")
    }

    /// Les gammes mineures ne sont pas un cas particulier bricolé à part : toutes les familles
    /// d'exercices déjà écrites pour le majeur (degrés, notes, intervalles, accords, armure)
    /// doivent fonctionner identiquement pour une tonalité mineure, sans aucun code dédié.
    func testMinorScaleProducesTheSameExerciseFamiliesAsMajor() {
        var rng = SeededGenerator(seed: 10)
        let dMinor = MusicalKey(tonicPitchClass: 2, isMajor: false)

        for focus in ExerciseGenerator.ScaleFocus.allCases {
            let exercises = ExerciseGenerator.scaleExercises(key: dMinor, focus: focus, rng: &rng)
            XCTAssertFalse(exercises.isEmpty, "\(focus) doit produire des exercices pour une gamme mineure aussi")
            XCTAssertTrue(exercises.allSatisfy { $0.displayKey == dMinor })
        }
    }

    // MARK: - Explications

    func testEveryGeneratedExerciseCarriesAnExplanation() {
        var rng = SeededGenerator(seed: 30)
        let notes =
            [note(60, at: 0), note(64, at: 0), note(67, at: 0)] +
            [note(60, at: 1), note(64, at: 1.5), note(67, at: 2)]
        let fromMusic = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        XCTAssertFalse(fromMusic.isEmpty)
        for exercise in fromMusic {
            XCTAssertFalse(exercise.explanation.isEmpty, "\(exercise.kind) devrait porter une explication")
        }

        let key = MusicalKey(tonicPitchClass: 4, isMajor: true)
        for focus in ExerciseGenerator.ScaleFocus.allCases {
            let exercises = ExerciseGenerator.scaleExercises(key: key, focus: focus, rng: &rng)
            for exercise in exercises {
                XCTAssertFalse(exercise.explanation.isEmpty,
                               "\(focus) / \(exercise.kind) devrait porter une explication")
            }
        }
    }

    func testIntervalExplanationNamesTheSemitoneCount() {
        // Durée étendue à l'écart complet — deux notes réellement enchaînées, sans silence noté.
        let notes = [note(60, at: 0, duration: 1), note(64, at: 1)] // do → mi : tierce majeure, 4 demi-tons
        var rng = SeededGenerator(seed: 31)

        let exercise = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
            .first { $0.kind == .interval }!

        XCTAssertTrue(exercise.explanation.contains("4"))
    }

    /// Régression : les notes AFFICHÉES doivent porter la MÊME classe de hauteur (même nom de
    /// note, dièse/bémol compris) que les notes RÉELLEMENT jouées dans le morceau — seule
    /// l'octave peut changer. Un bug précédent utilisait une base de transposition (55) qui
    /// n'était pas un multiple de 12, décalant silencieusement la classe de hauteur affichée :
    /// l'intervalle montré ne correspondait plus à aucune paire de notes du fichier d'origine.
    func testIntervalDisplayPitchesKeepTheSamePitchClassesAsTheRealNotes() {
        // Durée étendue à l'écart complet — deux notes réellement enchaînées, sans silence noté.
        let notes = [note(62, at: 0, duration: 1), note(66, at: 1)] // ré4 → fa♯4 : tierce majeure réelle
        var rng = SeededGenerator(seed: 32)

        let exercise = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
            .first { $0.kind == .interval }!

        XCTAssertEqual(exercise.notes.map { $0 % 12 }, [62 % 12, 66 % 12])
    }

    func testCMajorHasNoAccidentals() {
        let cMajor = MusicalKey(tonicPitchClass: 0, isMajor: true)
        XCTAssertEqual(cMajor.accidentalCount, 0)
    }

    // MARK: - Le parcours d'une gamme, par étape

    func testScaleIntervalFocusProducesSevenExercisesFromTheTonic() {
        let key = MusicalKey(tonicPitchClass: 0, isMajor: true) // do majeur
        var rng = SeededGenerator(seed: 9)

        let exercises = ExerciseGenerator.scaleExercises(key: key, focus: .intervals, rng: &rng)

        XCTAssertEqual(exercises.count, 7)
        XCTAssertTrue(exercises.allSatisfy { $0.kind == .interval && $0.notes.first == 60 })
        // Do à ré : seconde majeure — la première étape du parcours depuis la tonique.
        let toSecond = exercises.first { $0.notes.last == 62 }
        XCTAssertEqual(toSecond?.choices[toSecond!.correctIndex], IntervalQuality.majorSecond.displayName)
    }

    func testScaleChordFocusProducesSevenDiatonicTriads() {
        let key = MusicalKey(tonicPitchClass: 0, isMajor: true) // do majeur : I ii iii IV V vi vii°
        var rng = SeededGenerator(seed: 10)

        let exercises = ExerciseGenerator.scaleExercises(key: key, focus: .chords, rng: &rng)

        XCTAssertEqual(exercises.count, 7)
        XCTAssertTrue(exercises.allSatisfy { $0.kind == .chordQuality && $0.stacked })
        let tonicTriad = exercises.first { $0.notes == [60, 64, 67] } // do-mi-sol
        XCTAssertEqual(tonicTriad?.choices[tonicTriad!.correctIndex], ChordQuality.major.displayName)
        let viiChord = exercises.first { $0.notes == [71, 74, 77] } // si-ré-fa : le vii° diminué
        XCTAssertEqual(viiChord?.choices[viiChord!.correctIndex], ChordQuality.diminished.displayName)
    }

    func testScaleKeySignatureFocusProducesExactlyOneExercise() {
        let key = MusicalKey(tonicPitchClass: 7, isMajor: true) // sol majeur
        var rng = SeededGenerator(seed: 11)

        let exercises = ExerciseGenerator.scaleExercises(key: key, focus: .keySignature, rng: &rng)
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0].choices[exercises[0].correctIndex], "1")
    }

    func testScaleSpeedFocusMixesIntervalsChordsAndNotes() {
        let key = MusicalKey(tonicPitchClass: 4, isMajor: true) // mi majeur
        var rng = SeededGenerator(seed: 12)

        let exercises = ExerciseGenerator.scaleExercises(key: key, focus: .speed, rng: &rng)
        let kinds = Set(exercises.map(\.kind))

        XCTAssertTrue(kinds.contains(.interval))
        XCTAssertTrue(kinds.contains(.chordQuality))
        XCTAssertTrue(kinds.contains(.noteSpelling))
    }
}
