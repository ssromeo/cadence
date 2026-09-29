import Foundation
import CadenceCore

/// `cadence-debug` — l'outil qui a servi à trouver et vérifier trois bogues réels sur des
/// fichiers MIDI du monde réel (voir les tests de régression qui les citent nommément dans
/// `CadenceCoreTests` : melodicLine sur "Comptine d'un autre été", canonicalMeasureMap et le
/// filtre de silence sur "Drowning Love [With Key Change]"). Gardé dans le dépôt, pas jeté après
/// coup, précisément pour que le PROCHAIN bogue de ce genre — "telle mesure affiche n'importe
/// quoi" — se diagnostique en une commande de terminal plutôt qu'en reconstruisant cet outil
/// depuis zéro.
///
/// **Usage.**
/// ```
/// swift run cadence-debug <fichier.mid>                  # vue d'ensemble + mesures 1...20
/// swift run cadence-debug <fichier.mid> 8 18              # une plage de mesures précise
/// swift run cadence-debug <fichier.mid> --check            # audit automatique, tout le fichier
/// ```
///
/// **Pourquoi un exécutable du PAQUET plutôt qu'un script à part.** `import CadenceCore` donne un
/// accès DIRECT aux mêmes types et fonctions que l'app — `MIDIFileParser`, `HarmonicAnalyzer`,
/// `ExerciseGenerator` — sans jamais avoir à dupliquer la moindre logique dans un script parallèle
/// qui finirait par diverger. Voir `Package.swift` : c'est un `.executableTarget` du même paquet,
/// pas un projet séparé.
let args = CommandLine.arguments
guard args.count > 1 else {
    print("""
    usage:
      swift run cadence-debug <fichier.mid>                vue d'ensemble + mesures 1...20
      swift run cadence-debug <fichier.mid> <lo> <hi>       une plage de mesures précise
      swift run cadence-debug <fichier.mid> --check         audit automatique de tout le fichier
    """)
    exit(1)
}

let path = args[1]
let url = URL(fileURLWithPath: path)
let data: Data
do {
    data = try Data(contentsOf: url)
} catch {
    print("Impossible de lire \(path) : \(error)")
    exit(1)
}

let parsed: ParsedMIDI
do {
    parsed = try MIDIFileParser.parse(data: data)
} catch {
    print("Ce n'est pas un fichier MIDI standard lisible : \(error)")
    exit(1)
}

let maxMeasure = parsed.notes.map(\.measure).max() ?? 0

if args.contains("--check") {
    runAudit(parsed: parsed, path: path, maxMeasure: maxMeasure)
} else {
    let lo = args.count > 3 ? Int(args[2]) ?? 1 : 1
    let hi = args.count > 3 ? Int(args[3]) ?? maxMeasure : min(20, maxMeasure)
    runDump(parsed: parsed, path: path, lo: lo, hi: hi)
}

// MARK: - Vue d'ensemble détaillée d'une plage de mesures

func runDump(parsed: ParsedMIDI, path: String, lo: Int, hi: Int) {
    print("=== \(path) ===")
    print("ticksPerQuarterNote: \(parsed.ticksPerQuarterNote), total notes: \(parsed.notes.count), mesures 1...\(parsed.notes.map(\.measure).max() ?? 0)")

    struct VoiceKey: Hashable { let track: Int; let channel: Int }
    let voices = Dictionary(grouping: parsed.notes) { VoiceKey(track: $0.track, channel: $0.channel) }
    print("\n--- voix (track, channel) ---")
    for (key, notes) in voices.sorted(by: { $0.value.count > $1.value.count }) {
        let avg = Double(notes.reduce(0) { $0 + $1.pitch }) / Double(notes.count)
        print("   track=\(key.track) channel=\(key.channel): \(notes.count) notes, avgPitch=\(String(format: "%.1f", avg))")
    }

    let canon = HarmonicAnalyzer.canonicalMeasureMap(for: parsed.notes)
    print("\n--- mapping canonique \(lo)...\(hi) (repli d'une mesure sur une reprise antérieure) ---")
    for m in lo...hi where canon[m] != nil {
        let folded = canon[m] != m ? "  <- repliée" : ""
        print("   raw \(m) -> canon \(canon[m]!)\(folded)")
    }

    let byMeasure = Dictionary(grouping: parsed.notes, by: \.measure)
    print("\n--- notes brutes par mesure \(lo)...\(hi) ---")
    for m in lo...hi {
        let notes = (byMeasure[m] ?? []).sorted { $0.startSeconds < $1.startSeconds }
        guard !notes.isEmpty else { continue }
        print("mesure \(m) (canon \(canon[m] ?? m)): \(notes.count) notes")
        for n in notes {
            let dk = n.declaredKey.map { "\($0.name()) (\($0.accidentalCount)\($0.prefersFlats ? "b" : "#"))" } ?? "nil"
            print("   t=\(fmt(n.startSeconds))-\(fmt(n.endSeconds)) pitch=\(n.pitch) track=\(n.track) ch=\(n.channel) declaredKey=\(dk)")
        }
    }

    let melody = HarmonicAnalyzer.melodicLine(from: parsed.notes)
    print("\n--- melodicLine() : \(melody.count) notes au total (0 si aucune voix fiable) ---")
    for n in melody.filter({ lo...hi ~= $0.measure }).sorted(by: { $0.startSeconds < $1.startSeconds }) {
        print("   t=\(fmt(n.startSeconds)) pitch=\(n.pitch) rawM=\(n.measure) canonM=\(canon[n.measure] ?? n.measure)")
    }

    var rng = SystemRandomNumberGenerator()
    let musicPath = ExerciseGenerator.pathFromImportedMusic(notes: parsed.notes, rng: &rng)
    print("\n--- ExerciseGenerator.pathFromImportedMusic ---")
    print("clé globale détectée: \(musicPath.key.name())")
    for theme in musicPath.themes {
        print("   \(theme.focus.displayName): \(theme.exercises.count) exercices")
    }
    if let intervalTheme = musicPath.themes.first(where: { $0.focus == .intervals }) {
        print("\n--- exercices .interval touchant les mesures \(lo)...\(hi) ---")
        for ex in intervalTheme.exercises {
            let touchesRange = (ex.sourceMeasure.map { lo...hi ~= $0 } ?? false)
                || (ex.sourceMeasureEnd.map { lo...hi ~= $0 } ?? false)
            guard touchesRange else { continue }
            print("   \(ex.sourceMeasureLabel ?? "?")  notes=\(ex.notes)  \(ex.displayKey.name())  réponse=\(ex.choices[ex.correctIndex])")
        }
    }
}

// MARK: - Audit automatique : les invariants qu'on ne veut plus jamais casser en silence

/// Rejoue, sur TOUT le fichier, les vérifications qui ont permis de trouver chacun des trois
/// bogues réels documentés dans `CadenceCoreTests` — sans avoir à relire manuellement des
/// centaines de lignes de dump à chaque nouveau fichier suspect.
func runAudit(parsed: ParsedMIDI, path: String, maxMeasure: Int) {
    print("=== audit : \(path) (\(parsed.notes.count) notes, \(maxMeasure) mesures) ===\n")
    var problems = 0

    // 1. Aucune étiquette d'intervalle à numéros de mesure INVERSÉS — voir
    //    `ExerciseGenerator.endMeasureLabel`, le correctif exact du bogue "Mesure 31 et 16".
    var rng = SystemRandomNumberGenerator()
    let musicPath = ExerciseGenerator.pathFromImportedMusic(notes: parsed.notes, rng: &rng)
    if let intervalTheme = musicPath.themes.first(where: { $0.focus == .intervals }) {
        for ex in intervalTheme.exercises {
            guard let start = ex.sourceMeasure, let end = ex.sourceMeasureEnd, end <= start else { continue }
            problems += 1
            print("❌ étiquette de mesure incohérente : \"\(ex.sourceMeasureLabel ?? "?")\" (fin ≤ début)")
        }
    }

    // 2. Aucun repli de mesure ISOLÉ (une seule mesure, sans qu'un voisin ne confirme) — l'audit
    //    ne peut pas revérifier ça depuis l'extérieur de `canonicalMeasureMap` (la logique de
    //    confirmation est privée, à dessein), mais peut au moins lister TOUS les replis pour
    //    qu'un humain les parcoure d'un coup d'œil plutôt que mesure par mesure.
    let canon = HarmonicAnalyzer.canonicalMeasureMap(for: parsed.notes)
    let folds = canon.filter { $0.key != $0.value }.sorted { $0.key < $1.key }
    print("\n\(folds.count) mesure(s) repliée(s) sur une reprise antérieure :")
    for (raw, target) in folds.prefix(40) { print("   \(raw) -> \(target)") }
    if folds.count > 40 { print("   … (\(folds.count - 40) de plus)") }

    // 3. `melodicLine()` vide sur un fichier NON TRIVIAL (plus de quelques notes) signale
    //    presque toujours des mains mélangées sur une seule voix — voir le bogue "Comptine
    //    d'un autre été" : pas une erreur en soi, mais un signal à vérifier.
    let melody = HarmonicAnalyzer.melodicLine(from: parsed.notes)
    if melody.isEmpty, parsed.notes.count > 8 {
        print("\n⚠️  melodicLine() est VIDE malgré \(parsed.notes.count) notes — voix mélangées sur une " +
              "seule piste/canal ? Aucun exercice d'intervalle ne sera généré pour ce fichier.")
    }

    print("\n=== \(problems == 0 ? "✅ aucun problème détecté" : "❌ \(problems) problème(s) détecté(s)") ===")
}

private func fmt(_ t: Double) -> String { String(format: "%.3f", t) }
