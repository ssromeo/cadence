import Foundation

/// Le type de compétence qu'un exercice travaille — sert à filtrer, à afficher une icône, à
/// terme à nourrir un diagnostic de points faibles par catégorie plutôt que par exercice isolé.
public enum ExerciseKind: String, Sendable, CaseIterable {
    case interval        // reconnaître un intervalle mélodique
    case chordQuality    // reconnaître la qualité d'un accord
    case scaleDegree     // situer une note dans la gamme
    case noteSpelling    // nommer une note
    case keySignature    // compter les altérations d'une armure

    public var displayName: String {
        switch self {
        case .interval: "Intervalles"
        case .chordQuality: "Accords"
        case .scaleDegree: "Degrés"
        case .noteSpelling: "Notes"
        case .keySignature: "Armures"
        }
    }
}

/// Un exercice, sous une forme UNIQUE et générique — quel que soit le type de compétence qu'il
/// travaille.
///
/// **Pourquoi une seule structure plutôt qu'un type par exercice.** `IntervalQuizItem` existait
/// déjà avant cette structure et fonctionnait très bien pour LUI SEUL — mais chaque nouveau type
/// d'exercice (accords, degrés, armures…) aurait demandé sa propre vue SwiftUI pour l'afficher,
/// son propre code de sélection de réponse, sa propre logique de score. `GeneratedExercise`
/// réduit tout exercice à ce qu'une interface a réellement besoin de savoir pour l'afficher : un
/// énoncé, éventuellement des notes à montrer sur une portée, des choix de réponse en texte, et
/// laquelle est la bonne. Un seul écran sait alors jouer n'IMPORTE quel exercice, présent ou
/// futur, sans jamais être modifié pour un nouveau type.
public struct GeneratedExercise: Identifiable, Sendable {
    public let id: UUID
    public let kind: ExerciseKind
    public let prompt: String
    /// Hauteurs MIDI à afficher sur une portée — vide si l'exercice n'a pas de représentation
    /// notée (une question purement théorique, comme "combien d'altérations ?").
    public let notes: [Int]
    /// Si `notes` contient plusieurs hauteurs, les affiche-t-on empilées (un accord, joué en
    /// même temps) ou l'une après l'autre (une mélodie, un intervalle) ?
    public let stacked: Bool
    public let choices: [String]
    public let correctIndex: Int

    public init(kind: ExerciseKind, prompt: String, notes: [Int] = [], stacked: Bool = false,
                choices: [String], correctIndex: Int) {
        self.id = UUID()
        self.kind = kind
        self.prompt = prompt
        self.notes = notes
        self.stacked = stacked
        self.choices = choices
        self.correctIndex = correctIndex
    }

    public func isCorrect(_ choiceIndex: Int) -> Bool { choiceIndex == correctIndex }
}
