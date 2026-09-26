import XCTest
@testable import CadenceCore

final class ExerciseGeneratorTests: XCTestCase {

    private func note(_ pitch: Int, at start: Double, duration: Double = 0.4) -> MIDINoteEvent {
        MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: duration, track: 0, channel: 0)
    }

    // MARK: - Depuis un morceau

    /// Régression : une mélodie (piste 0) et une basse (piste 1) qui jouent EN MÊME TEMPS ne
    /// doivent jamais produire un "intervalle" entre une note de l'une et une note de l'autre —
    /// voir `HarmonicAnalyzer.melodicLine`. Sans cet isolement, trier toutes les notes par
    /// instant de départ mélangeait les deux mains et produisait des paires qui n'existent pas
    /// musicalement.
    func testIntervalsNeverMixTwoDifferentVoices() {
        let melody = [note(72, at: 0), note(74, at: 1), note(76, at: 2)] // do5-ré5-mi5, piste 0
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
        let notes = [note(96, at: 0), note(103, at: 1)] // très aigu : sol6 à sol7
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

    func testUnrecognizableClusterProducesNoChordExercise() {
        // do-do dièse-ré : cluster chromatique, aucun accord tonal reconnu — ne doit PAS
        // produire un exercice avec une "bonne réponse" qui n'existe pas.
        let notes = [note(60, at: 0), note(61, at: 0), note(62, at: 0)]
        var rng = SeededGenerator(seed: 4)

        let exercises = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
        XCTAssertFalse(exercises.contains { $0.kind == .chordQuality })
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
        let notes = [note(60, at: 0), note(64, at: 1)] // do → mi : tierce majeure, 4 demi-tons
        var rng = SeededGenerator(seed: 31)

        let exercise = ExerciseGenerator.fromImportedMusic(notes: notes, rng: &rng)
            .first { $0.kind == .interval }!

        XCTAssertTrue(exercise.explanation.contains("4"))
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
