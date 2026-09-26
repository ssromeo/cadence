import Foundation

/// Une question de quiz : deux notes réellement issues du MIDI importé — pas des notes
/// inventées — et un choix de réponses.
///
/// **Pourquoi les notes viennent du morceau importé et non d'une banque générique.** C'est le
/// principe différenciant du pilier 1 : l'utilisateur s'entraîne sur SA musique, pas sur des
/// exemples abstraits sans rapport avec ce qu'il joue. Deux notes prises dans "sa" mélodie
/// portent en plus le rythme et le timbre réels du morceau, que l'app pourra rejouer.
public struct IntervalQuizItem: Equatable, Sendable {
    public let interval: MelodicInterval
    public let correctAnswer: IntervalQuality
    /// Comprend toujours `correctAnswer`, mélangé parmi les leurres.
    public let choices: [IntervalQuality]

    public func isCorrect(_ answer: IntervalQuality) -> Bool { answer == correctAnswer }
}

/// Génère un quiz de reconnaissance d'intervalles à partir d'un morceau importé.
public enum IntervalQuizGenerator {
    /// - Parameters:
    ///   - notes: les notes du morceau (ou d'une piste choisie comme mélodie).
    ///   - choiceCount: nombre total de réponses proposées, bonne réponse comprise.
    ///   - rng: générateur de nombres pseudo-aléatoires — INJECTÉ plutôt que `Int.random`
    ///     implicite, pour que les tests puissent produire un tirage reproductible sans dépendre
    ///     de l'horloge ou d'un état global.
    public static func generate(from notes: [MIDINoteEvent], track: Int? = nil,
                                choiceCount: Int = 4,
                                rng: inout some RandomNumberGenerator) -> [IntervalQuizItem] {
        let intervals = HarmonicAnalyzer.melodicIntervals(from: notes, track: track)
        return intervals.map { interval in
            IntervalQuizItem(interval: interval,
                             correctAnswer: interval.quality,
                             choices: distractors(for: interval.quality, count: choiceCount, rng: &rng))
        }
    }

    /// Choisit `count - 1` réponses fausses PROCHES de la bonne — un demi-ton d'écart plutôt
    /// qu'une octave — puis les mélange avec la bonne réponse.
    ///
    /// **Pourquoi des leurres proches et non aléatoires.** Confondre une tierce majeure et une
    /// tierce mineure est l'erreur pédagogiquement intéressante à travailler : c'est celle
    /// qu'on fait vraiment à l'oreille. Un leurre pris au hasard sur les 13 qualités (une
    /// septième majeure à côté d'un unisson, par exemple) serait trivial à écarter et
    /// n'apprendrait rien.
    private static func distractors(for correct: IntervalQuality, count: Int,
                                    rng: inout some RandomNumberGenerator) -> [IntervalQuality] {
        let all = IntervalQuality.allCases
        let pool = all
            .filter { $0 != correct }
            .sorted { abs($0.rawValue - correct.rawValue) < abs($1.rawValue - correct.rawValue) }

        // On prend le plus près possible mais on garde un peu de hasard parmi les plus proches
        // à égalité de distance, pour ne pas donner toujours EXACTEMENT le même quiz sur le
        // même intervalle.
        var chosen: [IntervalQuality] = []
        var remaining = pool
        while chosen.count < count - 1, !remaining.isEmpty {
            let closestDistance = abs(remaining[0].rawValue - correct.rawValue)
            let tied = remaining.prefix { abs($0.rawValue - correct.rawValue) == closestDistance }
            let pick = tied.randomElement(using: &rng) ?? remaining[0]
            chosen.append(pick)
            remaining.removeAll { $0 == pick }
        }

        var choices = chosen + [correct]
        choices.shuffle(using: &rng)
        return choices
    }
}
