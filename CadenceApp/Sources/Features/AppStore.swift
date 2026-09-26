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

    /// La bibliothèque des morceaux déjà importés, persistée sur disque — voir
    /// `SongLibraryStore`. Rechargée à chaque changement (import, renommage, suppression) plutôt
    /// que lue à la demande : les vues qui l'affichent (voir `SongLibraryView`) doivent réagir à
    /// l'observation `@Observable` normale de l'app, pas interroger le disque elles-mêmes.
    private let songLibrary = SongLibraryStore(directory: SongLibraryStore.defaultDirectory())
    private(set) var libraryEntries: [SongLibraryEntry] = []

    private(set) var exercises: [GeneratedExercise] = []
    private(set) var source: ExerciseSource = .none
    var currentExerciseIndex = 0
    var lastAnswerWasCorrect: Bool?
    var score = 0
    /// Une entrée par question déjà répondue, dans l'ordre — ce que la barre de progression
    /// affiche : verte pour une bonne réponse, rouge pour une mauvaise, jamais une seule couleur
    /// neutre qui ne dirait rien du résultat.
    private(set) var answerHistory: [Bool] = []

    private var rng = SystemRandomNumberGenerator()
    /// Jeton d'annulation informel : si un second import démarre pendant qu'un premier tourne
    /// encore en tâche de fond, le premier ne doit plus pouvoir écraser l'état avec un résultat
    /// obsolète une fois qu'il termine enfin.
    private var importGeneration = 0

    init() {
        libraryEntries = songLibrary.loadEntries()
    }

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
            await self?.reportProgress(0.4, generation: generation)
            do {
                let result = try Self.analyze(data: data)
                await self?.reportProgress(0.8, generation: generation)
                await self?.applyImportResult(parsed: result.parsed, key: result.key, exercises: result.exercises,
                                              fileName: fileName, midiData: data, generation: generation)
            } catch AnalysisError.noNotes {
                await self?.finishImport(.failed("Ce fichier ne contient aucune note lisible."), generation: generation)
            } catch {
                await self?.finishImport(.failed("Ce fichier n'a pas pu être lu comme un MIDI standard."),
                                         generation: generation)
            }
        }
    }

    /// Recharge un morceau déjà dans la bibliothèque (voir `SongLibraryView`) — le MIDI d'origine
    /// est reparsé et régénéré exactement comme un import frais, mais SANS créer une seconde
    /// entrée dans la bibliothèque : c'est le même morceau qu'on rouvre, pas un nouveau.
    func loadSongFromLibrary(_ entry: SongLibraryEntry) {
        guard let data = songLibrary.midiData(for: entry.id) else { return }
        importGeneration += 1
        let generation = importGeneration
        importState = .analyzing(progress: 0.2)

        Task.detached(priority: .userInitiated) { [weak self] in
            guard let result = try? Self.analyze(data: data) else {
                await self?.finishImport(.failed("Ce morceau n'a pas pu être relu depuis la bibliothèque."),
                                         generation: generation)
                return
            }
            await self?.finishLoadingLibrarySong(parsed: result.parsed, exercises: result.exercises,
                                                 entry: entry, generation: generation)
        }
    }

    private enum AnalysisError: Error { case noNotes }

    /// Le travail de fond commun à un import frais et à un rechargement depuis la bibliothèque :
    /// parser, détecter la tonalité, générer les exercices. Ce que chaque appelant fait ENSUITE du
    /// résultat diffère (persister ou non une nouvelle entrée), donc seule cette partie commune,
    /// coûteuse, est factorisée — et volontairement `static`/hors acteur : elle ne touche à aucun
    /// état de l'app, seulement `Task.detached` peut donc l'exécuter hors du fil principal.
    nonisolated private static func analyze(data: Data) throws -> (parsed: ParsedMIDI, key: MusicalKey, exercises: [GeneratedExercise]) {
        let parsed = try MIDIFileParser.parse(data: data)
        guard !parsed.notes.isEmpty else { throw AnalysisError.noNotes }
        let key = KeyDetector.detectKey(from: parsed.notes)
        var localRNG = SystemRandomNumberGenerator()
        let exercises = ExerciseGenerator.fromImportedMusic(notes: parsed.notes, rng: &localRNG)
        return (parsed, key, exercises)
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
                                   fileName: String, midiData: Data, generation: Int) {
        guard generation == importGeneration else { return } // un import plus récent a pris le relais
        parsedMIDI = parsed
        let entry = songLibrary.addSong(midiData: midiData, originalFileName: fileName,
                                        noteCount: parsed.notes.count, key: key)
        libraryEntries = songLibrary.loadEntries()
        importState = .ready(fileName: entry.customName, noteCount: parsed.notes.count, key: key)
        beginSession(exercises: exercises, source: .importedMusic(fileName: entry.customName))
    }

    private func finishLoadingLibrarySong(parsed: ParsedMIDI, exercises: [GeneratedExercise],
                                          entry: SongLibraryEntry, generation: Int) {
        guard generation == importGeneration else { return }
        parsedMIDI = parsed
        importState = .ready(fileName: entry.customName, noteCount: parsed.notes.count, key: entry.key)
        beginSession(exercises: exercises, source: .importedMusic(fileName: entry.customName))
    }

    /// Renommer/supprimer touchent la bibliothèque PUIS rafraîchissent `libraryEntries` — jamais
    /// l'inverse — pour que la liste observée par `SongLibraryView` reflète toujours exactement ce
    /// qui est sur disque, sans jamais pouvoir en diverger.
    func renameSong(id: UUID, to newName: String) {
        songLibrary.rename(id: id, to: newName)
        libraryEntries = songLibrary.loadEntries()
        // Le morceau qu'on est peut-être en train de réviser porte encore l'ANCIEN nom dans
        // `importState`/`source` tant qu'on ne les met pas à jour ici — un renommage qui
        // n'apparaîtrait qu'après avoir quitté puis rouvert l'exercice serait déroutant.
        if case .ready(_, let noteCount, let key) = importState,
           case .importedMusic = source,
           let renamed = libraryEntries.first(where: { $0.id == id }) {
            importState = .ready(fileName: renamed.customName, noteCount: noteCount, key: key)
            source = .importedMusic(fileName: renamed.customName)
        }
    }

    func deleteSong(id: UUID) {
        songLibrary.delete(id: id)
        libraryEntries = songLibrary.loadEntries()
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
        answerHistory = []
    }

    func answer(_ choiceIndex: Int) {
        guard let exercise = currentExercise else { return }
        let correct = exercise.isCorrect(choiceIndex)
        record(correct)
    }

    /// Répondre en tapant directement sur un clavier plutôt qu'en choisissant parmi le QCM — voir
    /// `PianoOctavePicker`. La bonne réponse n'est plus l'INDEX d'un choix parmi quatre, mais la
    /// classe de hauteur réellement demandée : on la retrouve dans la première note de
    /// l'exercice, celle que l'exercice de nommage affiche toujours seule.
    func answerPianoTap(pitchClass: Int) {
        guard let exercise = currentExercise, let pitch = exercise.notes.first else { return }
        let correct = pitchClass == (((pitch % 12) + 12) % 12)
        record(correct)
    }

    private func record(_ correct: Bool) {
        lastAnswerWasCorrect = correct
        if correct { score += 1 }
        // Une entrée par INDEX de question, jamais deux — les boutons se désactivent après une
        // réponse, mais en cas d'appel répété on écrase plutôt que d'empiler une seconde entrée
        // qui décalerait toutes les couleurs suivantes de la barre.
        if answerHistory.count > currentExerciseIndex {
            answerHistory[currentExerciseIndex] = correct
        } else {
            answerHistory.append(correct)
        }
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
