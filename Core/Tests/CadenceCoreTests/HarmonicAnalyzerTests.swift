import XCTest
@testable import CadenceCore

final class HarmonicAnalyzerTests: XCTestCase {

    private func note(_ pitch: Int, at start: Double, duration: Double = 0.4) -> MIDINoteEvent {
        MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: duration, track: 0, channel: 0)
    }

    func testClustersSimultaneousNotesIntoOneChord() {
        // Un accord plaqué (les trois notes à 20 ms d'écart, comme une vraie main qui attaque
        // ensemble) doit rester UN cluster, pas trois.
        let notes = [
            note(60, at: 0.00), note(64, at: 0.02), note(67, at: 0.04),
        ]
        let clusters = HarmonicAnalyzer.clusterChords(from: notes)
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters[0].pitchClasses, [0, 4, 7])
    }

    func testSeparatesChordsBeyondTolerance() {
        // Deux accords à une seconde d'écart doivent rester deux clusters distincts, même si
        // chacun est plaqué proprement en interne.
        let notes = [
            note(60, at: 0.00), note(64, at: 0.00), note(67, at: 0.00),
            note(65, at: 1.00), note(69, at: 1.00), note(72, at: 1.00),
        ]
        let clusters = HarmonicAnalyzer.clusterChords(from: notes)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(clusters[0].pitchClasses, [0, 4, 7])
        XCTAssertEqual(clusters[1].pitchClasses, [5, 9, 0])
    }

    func testAnalyzesADiatonicCadenceInCMajor() {
        // I - IV - V - I, l'enchaînement le plus élémentaire de l'harmonie tonale. C'est le cas
        // qui valide le pipeline de bout en bout : détection de tonalité PUIS reconnaissance de
        // chaque accord PUIS rattachement au bon degré.
        let notes =
            [note(60, at: 0), note(64, at: 0), note(67, at: 0)] +          // I   : do-mi-sol
            [note(65, at: 1), note(69, at: 1), note(72, at: 1)] +          // IV  : fa-la-do
            [note(67, at: 2), note(71, at: 2), note(74, at: 2)] +          // V   : sol-si-ré
            [note(60, at: 3), note(64, at: 3), note(67, at: 3)]            // I   : do-mi-sol

        let (key, chords) = HarmonicAnalyzer.analyze(notes: notes)

        XCTAssertEqual(key.tonicPitchClass, 0)
        XCTAssertTrue(key.isMajor)
        XCTAssertEqual(chords.map(\.scaleDegree), [1, 4, 5, 1])
        XCTAssertEqual(chords.map { $0.chord?.quality }, [.major, .major, .major, .major])
    }

    func testMelodicIntervalsFromASimpleLine() {
        let notes = [note(60, at: 0), note(64, at: 0.5), note(67, at: 1.0), note(72, at: 1.5)]
        let intervals = HarmonicAnalyzer.melodicIntervals(from: notes)

        XCTAssertEqual(intervals.count, 3)
        XCTAssertEqual(intervals[0].semitones, 4)   // do → mi : tierce majeure
        XCTAssertEqual(intervals[0].quality, .majorThird)
        XCTAssertEqual(intervals[1].semitones, 3)   // mi → sol : tierce mineure
        XCTAssertEqual(intervals[2].semitones, 5)   // sol → do : quarte juste
        XCTAssertTrue(intervals.allSatisfy(\.isAscending))
    }

    func testDescendingIntervalIsFlaggedButNamedByAbsoluteDistance() {
        let notes = [note(67, at: 0), note(60, at: 0.5)] // sol → do, en descendant
        let intervals = HarmonicAnalyzer.melodicIntervals(from: notes)

        XCTAssertEqual(intervals[0].semitones, -7)
        XCTAssertFalse(intervals[0].isAscending)
        XCTAssertEqual(intervals[0].quality, .perfectFifth)
    }

    func testMelodicIntervalsCanFilterByTrack() {
        let melody = MIDINoteEvent(pitch: 72, velocity: 80, startSeconds: 0, durationSeconds: 0.5, track: 0, channel: 0)
        let melody2 = MIDINoteEvent(pitch: 74, velocity: 80, startSeconds: 0.5, durationSeconds: 0.5, track: 0, channel: 0)
        let bass = MIDINoteEvent(pitch: 36, velocity: 80, startSeconds: 0, durationSeconds: 1.0, track: 1, channel: 0)

        let intervals = HarmonicAnalyzer.melodicIntervals(from: [melody, melody2, bass], track: 0)
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals[0].semitones, 2)
    }

    // MARK: - Repli des mesures répétées (barre de reprise)

    private func note(_ pitch: Int, at start: Double, measure: Int, track: Int = 0) -> MIDINoteEvent {
        MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: 0.4,
                     track: track, channel: 0, measure: measure)
    }

    func testCanonicalMeasureMapFoldsAnExactRepeatOntoItsFirstOccurrence() {
        // Mesures 1 et 2 : contenu original. Mesures 3 et 4 : reprise EXACTE de 1 et 2 — comme un
        // fichier MIDI qui a "déroulé" une barre de reprise plutôt que de la coder comme telle.
        let notes = [
            note(60, at: 0, measure: 1), note(64, at: 0.5, measure: 1),
            note(67, at: 1.0, measure: 2),
            note(60, at: 2.0, measure: 3), note(64, at: 2.5, measure: 3), // = mesure 1
            note(67, at: 3.0, measure: 4),                                 // = mesure 2
        ]

        let map = HarmonicAnalyzer.canonicalMeasureMap(for: notes)

        XCTAssertEqual(map[1], 1)
        XCTAssertEqual(map[2], 2)
        XCTAssertEqual(map[3], 1, "la mesure 3 répète note pour note la mesure 1")
        XCTAssertEqual(map[4], 2, "la mesure 4 répète note pour note la mesure 2")
    }

    func testCanonicalMeasureMapLeavesDifferentContentUntouched() {
        let notes = [
            note(60, at: 0, measure: 1),
            note(62, at: 1.0, measure: 2), // différent de la mesure 1 : pas une reprise
        ]

        let map = HarmonicAnalyzer.canonicalMeasureMap(for: notes)

        XCTAssertEqual(map[1], 1)
        XCTAssertEqual(map[2], 2)
    }

    func testCanonicalMeasureMapComparesAllVoicesNotJustOneTrack() {
        // Même mélodie (piste 0) aux deux mesures, mais un accompagnement DIFFÉRENT (piste 1) —
        // ce n'est pas une vraie reprise, tout le passage doit rester distinct.
        let notes = [
            note(60, at: 0, measure: 1, track: 0), note(36, at: 0, measure: 1, track: 1),
            note(60, at: 1.0, measure: 2, track: 0), note(38, at: 1.0, measure: 2, track: 1),
        ]

        let map = HarmonicAnalyzer.canonicalMeasureMap(for: notes)

        XCTAssertEqual(map[1], 1)
        XCTAssertEqual(map[2], 2, "l'accompagnement diffère : ce n'est pas la même mesure")
    }
}
