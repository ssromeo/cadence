import XCTest
@testable import CadenceCore

/// Générateur pseudo-aléatoire déterministe pour les tests — SplitMix64. N'importe quel
/// algorithme reproductible conviendrait ; celui-ci est choisi pour sa simplicité et l'absence
/// de dépendance à autre chose que l'arithmétique entière.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class IntervalQuizGeneratorTests: XCTestCase {

    private func note(_ pitch: Int, at start: Double) -> MIDINoteEvent {
        MIDINoteEvent(pitch: pitch, velocity: 80, startSeconds: start, durationSeconds: 0.4, track: 0, channel: 0)
    }

    func testGeneratesOneQuestionPerInterval() {
        let notes = [note(60, at: 0), note(64, at: 0.5), note(67, at: 1.0), note(72, at: 1.5)]
        var rng = SeededGenerator(seed: 1)

        let quiz = IntervalQuizGenerator.generate(from: notes, rng: &rng)

        XCTAssertEqual(quiz.count, 3) // 4 notes → 3 intervalles successifs
        XCTAssertEqual(quiz[0].correctAnswer, .majorThird)
        XCTAssertEqual(quiz[1].correctAnswer, .minorThird)
        XCTAssertEqual(quiz[2].correctAnswer, .perfectFourth)
    }

    func testChoicesAlwaysContainTheCorrectAnswerOnceAndAreDistinct() {
        let notes = [note(60, at: 0), note(71, at: 0.5)] // majorSeventh, un intervalle large
        var rng = SeededGenerator(seed: 42)

        let quiz = IntervalQuizGenerator.generate(from: notes, choiceCount: 4, rng: &rng)

        let item = quiz[0]
        XCTAssertEqual(item.choices.count, 4)
        XCTAssertEqual(Set(item.choices).count, 4, "les propositions doivent être distinctes")
        XCTAssertEqual(item.choices.filter { $0 == item.correctAnswer }.count, 1)
    }

    func testDistractorsAreCloseToTheCorrectAnswer() {
        // Sur une tierce majeure (4 demi-tons), les leurres doivent être des intervalles
        // voisins — seconde majeure, quarte, tierce mineure — jamais un intervalle éloigné
        // comme la septième majeure, qui n'apprendrait rien à distinguer.
        let notes = [note(60, at: 0), note(64, at: 0.5)]
        var rng = SeededGenerator(seed: 7)

        let quiz = IntervalQuizGenerator.generate(from: notes, choiceCount: 4, rng: &rng)
        let distances = quiz[0].choices.map { abs($0.rawValue - IntervalQuality.majorThird.rawValue) }

        XCTAssertTrue(distances.allSatisfy { $0 <= 2 },
                      "leurres attendus à deux demi-tons au plus : \(quiz[0].choices)")
    }

    func testIsCorrectMatchesTheGeneratedAnswer() {
        let notes = [note(60, at: 0), note(65, at: 0.5)] // quarte juste
        var rng = SeededGenerator(seed: 3)
        let item = IntervalQuizGenerator.generate(from: notes, rng: &rng)[0]

        XCTAssertTrue(item.isCorrect(.perfectFourth))
        XCTAssertFalse(item.isCorrect(.majorThird))
    }

    func testEmptyMelodyProducesNoQuestions() {
        var rng = SeededGenerator(seed: 0)
        XCTAssertEqual(IntervalQuizGenerator.generate(from: [], rng: &rng).count, 0)
        XCTAssertEqual(IntervalQuizGenerator.generate(from: [note(60, at: 0)], rng: &rng).count, 0)
    }
}
