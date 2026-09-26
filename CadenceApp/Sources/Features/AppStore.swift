import Foundation
import CadenceCore

/// État de l'écran d'accueil : rien d'importé, en cours d'analyse, prêt, ou en échec.
///
/// Un enum et non trois booléens indépendants (`isLoading`, `hasError`, `isReady`) — avec des
/// booléens, rien n'empêche `isLoading` et `isReady` d'être vrais ensemble, un état qui n'a
/// aucun sens mais que le compilateur laisserait passer. Ici, un seul cas est vrai à la fois,
/// par construction.
enum ImportState: Equatable {
    case empty
    /// `progress` reste indicatif — le parsing n'a pas d'étapes qu'on puisse mesurer précisément
    /// à l'avance — mais une barre qui AVANCE, même approximativement, rassure davantage qu'un
    /// simple rond qui tourne sans fin visible, surtout sur un gros fichier de plusieurs
    /// milliers de notes.
    case analyzing(progress: Double)
    case ready(fileName: String, noteCount: Int, key: MusicalKey)
    case failed(String)
}

/// D'où viennent les exercices actuellement proposés — le morceau importé, ou UNE ÉTAPE précise
/// du parcours d'une gamme choisie sans morceau du tout (le pilier 2 du projet : pas de MIDI ?
/// on travaille quand même — mais par étapes séparées, pas un unique quiz qui mélange tout).
enum ExerciseSource: Equatable {
    case none
    case importedMusic(fileName: String)
    case scaleFocus(MusicalKey, ExerciseGenerator.ScaleFocus)

    var title: String {
        switch self {
        case .none: ""
        case .importedMusic(let name): name
        case .scaleFocus(let key, let focus): "\(key.name().capitalized) — \(focus.displayName)"
        }
    }
}

/// L'état de toute l'app, au sens le plus simple : ce qui a été importé, les exercices qui en
/// découlent — d'un morceau OU d'une gamme choisie — et la progression dans ces exercices. Un
/// seul magasin, partagé par les écrans via l'environnement, parce qu'Accueil, Exercices et
/// Gammes parlent tous du même état de progression.
@MainActor
@Observable
final class AppStore {
    private(set) var importState: ImportState = .empty
    private(set) var parsedMIDI: ParsedMIDI?

    private(set) var exercises: [GeneratedExercise] = []
    private(set) var source: ExerciseSource = .none
    var currentExerciseIndex = 0
    var lastAnswerWasCorrect: Bool?
    var score = 0

    private var rng = SystemRandomNumberGenerator()
    /// Jeton d'annulation informel : si un second import démarre pendant qu'un premier tourne
    /// encore en tâche de fond, le premier ne doit plus pouvoir écraser l'état avec un résultat
    /// obsolète une fois qu'il termine enfin.
    private var importGeneration = 0

    var currentExercise: GeneratedExercise? {
        exercises.indices.contains(currentExerciseIndex) ? exercises[currentExerciseIndex] : nil
    }

    var isFinished: Bool { !exercises.isEmpty && currentExerciseIndex >= exercises.count }

    /// La tonalité à utiliser pour AFFICHER l'exercice courant (orthographe des notes, nom des
    /// degrés) — celle du morceau importé une fois prêt, ou celle de la gamme choisie. Un seul
    /// point de vérité pour les deux sources, plutôt que de faire deviner à chaque écran laquelle
    /// des deux consulter.
    var displayKey: MusicalKey? {
        switch source {
        case .none: nil
        case .scaleFocus(let key, _): key
        case .importedMusic:
            if case .ready(_, _, let key) = importState { key } else { nil }
        }
    }

    // MARK: - Depuis un morceau importé

    /// Analyse un fichier importé, EN TÂCHE DE FOND.
    ///
    /// Le parsing d'un gros MIDI (plusieurs milliers de notes, comme un morceau complet exporté
    /// depuis un DAW) prend un temps mesurable — pas énorme, mais assez pour geler l'interface
    /// une fraction de seconde perceptible si on le fait sur l'acteur principal. `Task.detached`
    /// exécute le parsing et toute l'analyse harmonique HORS de l'acteur principal ; seul le
    /// résultat final revient sur `MainActor` pour mettre à jour l'état observé par les vues.
    func importMIDI(from data: Data, fileName: String) {
        importGeneration += 1
        let generation = importGeneration
        importState = .analyzing(progress: 0.08)

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let parsed = try MIDIFileParser.parse(data: data)
                await self?.reportProgress(0.55, generation: generation)

                guard !parsed.notes.isEmpty else {
                    await self?.finishImport(.failed("Ce fichier ne contient aucune note lisible."), generation: generation)
                    return
                }

                let key = KeyDetector.detectKey(from: parsed.notes)
                await self?.reportProgress(0.8, generation: generation)

                var localRNG = SystemRandomNumberGenerator()
                let generated = ExerciseGenerator.fromImportedMusic(notes: parsed.notes, rng: &localRNG)

                await self?.applyImportResult(parsed: parsed, key: key, exercises: generated,
                                              fileName: fileName, generation: generation)
            } catch {
                await self?.finishImport(.failed("Ce fichier n'a pas pu être lu comme un MIDI standard."),
                                         generation: generation)
            }
        }
    }

    private func reportProgress(_ value: Double, generation: Int) {
        guard generation == importGeneration else { return }
        importState = .analyzing(progress: value)
    }

    private func finishImport(_ state: ImportState, generation: Int) {
        guard generation == importGeneration else { return }
        importState = state
    }

    private func applyImportResult(parsed: ParsedMIDI, key: MusicalKey, exercises: [GeneratedExercise],
                                   fileName: String, generation: Int) {
        guard generation == importGeneration else { return } // un import plus récent a pris le relais
        parsedMIDI = parsed
        importState = .ready(fileName: fileName, noteCount: parsed.notes.count, key: key)
        beginSession(exercises: exercises, source: .importedMusic(fileName: fileName))
    }

    // MARK: - Depuis une gamme choisie, sans morceau

    /// Le pilier 2 du projet : pas de MIDI à importer ? On choisit une tonalité et on
    /// s'entraîne dessus quand même — mais par ÉTAPE (voir `ScalePathView`), pas un unique quiz
    /// qui mélangerait notes, intervalles et accords sans distinction. Aucune dépendance à
    /// `parsedMIDI` — cette session peut démarrer même si aucun fichier n'a jamais été importé.
    func startScaleFocus(key: MusicalKey, focus: ExerciseGenerator.ScaleFocus) {
        let generated = ExerciseGenerator.scaleExercises(key: key, focus: focus, rng: &rng)
        beginSession(exercises: generated, source: .scaleFocus(key, focus))
    }

    // MARK: - Session d'exercices, commune aux deux sources

    private func beginSession(exercises: [GeneratedExercise], source: ExerciseSource) {
        self.exercises = exercises
        self.source = source
        currentExerciseIndex = 0
        score = 0
        lastAnswerWasCorrect = nil
    }

    func answer(_ choiceIndex: Int) {
        guard let exercise = currentExercise else { return }
        let correct = exercise.isCorrect(choiceIndex)
        lastAnswerWasCorrect = correct
        if correct { score += 1 }
    }

    /// Répondre en tapant directement sur un clavier plutôt qu'en choisissant parmi le QCM — voir
    /// `PianoOctavePicker`. La bonne réponse n'est plus l'INDEX d'un choix parmi quatre, mais la
    /// classe de hauteur réellement demandée : on la retrouve dans la première note de
    /// l'exercice, celle que l'exercice de nommage affiche toujours seule.
    func answerPianoTap(pitchClass: Int) {
        guard let exercise = currentExercise, let pitch = exercise.notes.first else { return }
        let correct = pitchClass == (((pitch % 12) + 12) % 12)
        lastAnswerWasCorrect = correct
        if correct { score += 1 }
    }

    func advanceToNextExercise() {
        currentExerciseIndex += 1
        lastAnswerWasCorrect = nil
    }

    func restartSession() {
        switch source {
        case .none: return
        case .importedMusic:
            guard let parsedMIDI else { return }
            let generated = ExerciseGenerator.fromImportedMusic(notes: parsedMIDI.notes, rng: &rng)
            beginSession(exercises: generated, source: source)
        case .scaleFocus(let key, let focus):
            startScaleFocus(key: key, focus: focus)
        }
    }
}
