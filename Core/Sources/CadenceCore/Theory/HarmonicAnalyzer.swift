import Foundation

/// Un regroupement de notes jouées "en même temps" — un accord potentiel, avant même de savoir
/// si on sait le nommer.
public struct ChordCluster: Equatable, Sendable {
    public let notes: [MIDINoteEvent]
    public let startSeconds: Double
    public var pitchClasses: Set<Int> { Set(notes.map(\.pitchClass)) }
    public var bassPitchClass: Int { notes.min(by: { $0.pitch < $1.pitch })!.pitchClass }
}

/// Un accord identifié, replacé dans son contexte : à quel instant, et — si une tonalité a été
/// détectée — quel degré de l'échelle il occupe (I, IV, V…).
public struct AnalyzedChord: Equatable, Sendable {
    public let cluster: ChordCluster
    public let chord: IdentifiedChord?
    /// Chiffrage romain (1-indexé : I=1) si l'accord est diatonique dans la tonalité fournie,
    /// `nil` sinon — un accord "emprunté" ou une simple couleur chromatique n'a pas de degré.
    public let scaleDegree: Int?
}

/// Le pipeline complet : d'un fichier MIDI parsé à une analyse harmonique exploitable par les
/// quiz et par la vue "carte des accords".
///
/// Trois étapes, dans cet ordre précis :
/// 1. Regrouper les notes en clusters (candidats accords) par proximité temporelle.
/// 2. Détecter la tonalité sur l'ENSEMBLE du morceau — elle a besoin de voir tout le matériau
///    pour être fiable, contrairement aux accords qui se lisent cluster par cluster.
/// 3. Identifier chaque cluster et le rapporter à la tonalité détectée.
public enum HarmonicAnalyzer {
    /// Fenêtre en secondes sous laquelle deux notes sont considérées "jouées ensemble". Un
    /// pianiste humain n'attaque jamais deux touches d'un accord à la microseconde près ; 60 ms
    /// couvre l'étalement naturel d'une main sans fusionner deux accords réellement successifs
    /// dans un tempo rapide (à 200 bpm, une double-croche dure 75 ms).
    public static let defaultClusterTolerance: Double = 0.06

    public static func clusterChords(from notes: [MIDINoteEvent],
                                     tolerance: Double = defaultClusterTolerance) -> [ChordCluster] {
        guard !notes.isEmpty else { return [] }
        let sorted = notes.sorted { $0.startSeconds < $1.startSeconds }

        var clusters: [ChordCluster] = []
        var current: [MIDINoteEvent] = [sorted[0]]
        var currentStart = sorted[0].startSeconds

        for note in sorted.dropFirst() {
            if note.startSeconds - currentStart <= tolerance {
                current.append(note)
            } else {
                clusters.append(ChordCluster(notes: current, startSeconds: currentStart))
                current = [note]
                currentStart = note.startSeconds
            }
        }
        clusters.append(ChordCluster(notes: current, startSeconds: currentStart))
        return clusters
    }

    /// Analyse complète : tonalité détectée sur tout le morceau, puis chaque cluster rapporté à
    /// elle.
    public static func analyze(notes: [MIDINoteEvent],
                               tolerance: Double = defaultClusterTolerance) -> (key: MusicalKey, chords: [AnalyzedChord]) {
        let key = KeyDetector.detectKey(from: notes)
        let clusters = clusterChords(from: notes, tolerance: tolerance)

        let scaleDegreeByPitchClass: [Int: Int] = Dictionary(
            uniqueKeysWithValues: key.scalePitchClasses.enumerated().map { ($1, $0 + 1) })

        let analyzed = clusters.map { cluster -> AnalyzedChord in
            let identified = ChordIdentifier.identify(pitchClasses: cluster.pitchClasses,
                                                      bassPitchClass: cluster.bassPitchClass)
            let degree = identified.flatMap { scaleDegreeByPitchClass[$0.rootPitchClass] }
            return AnalyzedChord(cluster: cluster, chord: identified, scaleDegree: degree)
        }
        return (key, analyzed)
    }

    /// La ligne mélodique d'une piste : ses notes, triées, converties en intervalles successifs.
    /// C'est la matière première du quiz de reconnaissance d'intervalles.
    public static func melodicIntervals(from notes: [MIDINoteEvent], track: Int? = nil) -> [MelodicInterval] {
        let filtered = track.map { t in notes.filter { $0.track == t } } ?? notes
        let sorted = filtered.sorted { $0.startSeconds < $1.startSeconds }
        guard sorted.count >= 2 else { return [] }
        return zip(sorted, sorted.dropFirst()).map { MelodicInterval(from: $0, to: $1) }
    }

    /// Isole LA voix mélodique d'un morceau à plusieurs voix (typiquement la main droite d'une
    /// partition de piano), pour que `melodicIntervals` ne calcule plus d'intervalle entre deux
    /// notes qui n'ont aucun lien mélodique réel.
    ///
    /// **Le problème que ça résout.** Appelée sans filtre sur un morceau à deux mains, la
    /// fonction ci-dessus trie TOUTES les notes du fichier par instant de départ et calcule un
    /// intervalle entre chaque paire consécutive — y compris entre la dernière note de la
    /// mélodie et la note de basse suivante. Un tel "intervalle" n'a jamais existé dans
    /// l'intention du compositeur : ce ne sont pas deux notes d'une même ligne, juste deux notes
    /// qui se trouvent proches dans le temps. Un exercice construit dessus n'a donc pas de
    /// réponse musicalement valide — exactement le défaut signalé sur un export réel.
    ///
    /// **La méthode.** On regroupe les notes par VOIX (piste + canal MIDI — la manière dont un
    /// export de partition sépare presque toujours les mains), on retient celle dont la hauteur
    /// MOYENNE est la plus élevée (la mélodie se joue, par convention, au-dessus de
    /// l'accompagnement), puis on ne garde qu'UNE note par instant de départ à l'intérieur de
    /// cette voix (la plus aiguë, en cas d'accord ou de doublure d'octave) — pour que le résultat
    /// soit une vraie ligne à une seule note à la fois, jamais un empilement.
    ///
    /// **Le cas à une seule voix MIDI.** Un fichier de PERFORMANCE (capturé au clavier, par
    /// opposition à un export de logiciel de notation) porte souvent les deux mains sur la même
    /// piste et le même canal — il n'y a alors qu'un seul groupe, et rien à départager par hauteur
    /// moyenne. Le traiter comme "la mélodie" sans vérifier ne marche que si ce flux est VRAIMENT
    /// monophonique : sur un vrai fichier de ce genre ("Comptine d'un autre été", capture Rousseau
    /// MIDI), 98 % des notes attaquaient alors qu'une autre hauteur sonnait encore — la main
    /// gauche et la main droite, mélangées sur la même voix, sans aucun moyen fiable de les
    /// reséparer depuis les seuls timestamps. Un exercice tiré de ce flux montrait alors deux
    /// notes prises au hasard entre les deux mains, sans rapport avec la ligne imprimée à
    /// l'endroit indiqué. Voir `hasSubstantialPolyphony` : en dessous du seuil (un instrument
    /// réellement monophonique, un peu de recouvrement dû au legato ou à la pédale), on garde
    /// l'ancien comportement ; au-dessus, on renvoie une ligne mélodique VIDE plutôt qu'une fausse
    /// — les exercices d'intervalle disparaissent pour ce fichier, mais les exercices d'accord
    /// (qui ne dépendent pas de cette séparation) continuent de fonctionner normalement.
    public static func melodicLine(from notes: [MIDINoteEvent]) -> [MIDINoteEvent] {
        struct Voice: Hashable { let track: Int; let channel: Int }
        let byVoice = Dictionary(grouping: notes, by: { Voice(track: $0.track, channel: $0.channel) })

        let melody: [MIDINoteEvent]
        if byVoice.count > 1 {
            guard let picked = byVoice.values.max(by: { averagePitch($0) < averagePitch($1) }) else { return [] }
            melody = picked
        } else {
            guard let onlyVoice = byVoice.values.first, !hasSubstantialPolyphony(onlyVoice) else { return [] }
            melody = onlyVoice
        }

        let byStart = Dictionary(grouping: melody, by: \.startSeconds)
        return byStart.values
            .compactMap { simultaneous in simultaneous.max { $0.pitch < $1.pitch } }
            .sorted { $0.startSeconds < $1.startSeconds }
    }

    /// Vrai quand une fraction significative des notes attaquent NETTEMENT après une autre note,
    /// de hauteur différente, qui sonne pourtant encore — signe que plusieurs voix réelles
    /// (typiquement mélodie et basse) sont mélangées dans ce même flux plutôt que d'y former une
    /// seule ligne.
    ///
    /// **Pourquoi exclure les attaques simultanées.** Un accord plaqué (plusieurs notes qui
    /// attaquent ensemble, à `defaultClusterTolerance` près, comme dans `clusterChords`) est UN
    /// SEUL événement vertical — le jouer au début d'un morceau sinon parfaitement monophonique ne
    /// prouve rien sur un mélange de voix, et compter ces notes-là faisait basculer à tort un
    /// simple "accord puis mélodie" au-dessus du seuil. Seul un chevauchement dont l'attaque
    /// arrive DISTINCTEMENT plus tard (au-delà de la tolérance) trahit une seconde voix
    /// indépendante encore active — typiquement une basse tenue sous une ligne qui continue.
    ///
    /// Le seuil par défaut (20 %) laisse toute la marge voulue au legato ou au pédalage d'un
    /// instrument réellement monophonique, très loin des 98 % mesurés sur le fichier réel qui a
    /// motivé ce correctif.
    private static func hasSubstantialPolyphony(_ notes: [MIDINoteEvent], threshold: Double = 0.2) -> Bool {
        guard notes.count > 1 else { return false }
        let sorted = notes.sorted { $0.startSeconds < $1.startSeconds }

        // Balayage temporel : `active` ne contient que les notes encore sonnantes à l'instant
        // courant, purgées au fur et à mesure — pour rester proche de O(n) plutôt que de comparer
        // chaque note à toutes les autres sur un morceau qui peut compter plusieurs milliers de
        // notes.
        var active: [MIDINoteEvent] = []
        var overlapCount = 0
        for note in sorted {
            active.removeAll { $0.endSeconds <= note.startSeconds }
            let overlapsAnotherVoice = active.contains { earlier in
                earlier.pitch != note.pitch &&
                note.startSeconds - earlier.startSeconds > defaultClusterTolerance
            }
            if overlapsAnotherVoice { overlapCount += 1 }
            active.append(note)
        }
        return Double(overlapCount) / Double(sorted.count) > threshold
    }

    private static func averagePitch(_ notes: [MIDINoteEvent]) -> Double {
        guard !notes.isEmpty else { return -.infinity }
        return Double(notes.reduce(0) { $0 + $1.pitch }) / Double(notes.count)
    }

    /// Replie chaque mesure sur le numéro de sa PREMIÈRE apparition, quand elle fait partie d'un
    /// BLOC d'au moins deux mesures CONSÉCUTIVES, note pour note identiques (toutes voix
    /// confondues), à un bloc déjà vu plus tôt.
    ///
    /// **Le problème que ça résout.** Un morceau écrit avec une barre de reprise (jouer les
    /// mesures 5 à 20, revenir à la 5, rejouer jusqu'à la 20) est souvent EXPORTÉ en MIDI déjà
    /// "déroulé" : les mesures 5-20 apparaissent deux fois de suite dans le fichier. Compter les
    /// mesures depuis le début du fichier, sans savoir qu'une reprise a eu lieu, donne donc à la
    /// second passe des numéros (21, 22…) qui n'existent nulle part dans la partition IMPRIMÉE —
    /// exactement le défaut signalé : "je regarde la mesure 20 [que l'appli affichait en réalité
    /// comme 36] et il n'y a rien de tel". En détectant qu'une mesure reproduit EXACTEMENT une
    /// mesure déjà vue plus tôt, on rapporte toujours le numéro que la partition imprime réellement.
    ///
    /// **Pourquoi exiger un BLOC d'au moins deux mesures, jamais une seule mesure isolée.**
    /// Régression exacte d'un bogue trouvé sur un vrai fichier ("Drowning Love [With Key
    /// Change]") : la version précédente repliait une mesure dès que son contenu, à elle seule,
    /// coïncidait avec une mesure antérieure — sans jamais vérifier qu'une MESURE VOISINE
    /// coïncidait elle aussi. Sur un morceau pop bâti sur un riff répétitif (très courant), il
    /// suffit qu'une mesure isolée reprenne par pur hasard les 2-3 notes d'une mesure antérieure
    /// — sans le moindre lien avec une reprise engravée — pour la faire replier à tort. Deux
    /// symptômes exacts observés : une mesure 15 repliée sur la mesure 13 alors que la mesure 14
    /// voisine, elle, ne correspondait à RIEN d'antérieur (bloc d'UNE SEULE mesure, jamais deux),
    /// produisant ensuite des étiquettes d'exercice absurdes — "Mesure 14 et 13" (numéros dans le
    /// mauvais ordre) ou "Mesure 13 et 16" (saute 14 et 15 sans raison). Une VRAIE reprise
    /// engravée recopie toujours un bloc d'AU MOINS deux mesures — jamais une seule mesure isolée
    /// — donc exiger qu'au moins une mesure voisine (avant OU après) corresponde elle aussi,
    /// terme à terme, à la mesure voisine correspondante du bloc antérieur, élimine cette classe
    /// de faux positifs sans jamais affaiblir la détection d'une reprise réelle : dans un vrai
    /// bloc répété, CHAQUE mesure qui le compose a par construction un voisin qui coïncide lui
    /// aussi.
    ///
    /// **Pourquoi "toutes voix confondues" plutôt que la seule mélodie.** Une reprise rejoue
    /// TOUT — mélodie et accompagnement — donc comparer l'ensemble des notes (peu importe leur
    /// piste) élimine le risque qu'une mélodie répétitive coïncide par hasard sans que ce soit
    /// une vraie reprise.
    public static func canonicalMeasureMap(for notes: [MIDINoteEvent]) -> [Int: Int] {
        guard let maxMeasure = notes.map(\.measure).max() else { return [:] }
        let byMeasure = Dictionary(grouping: notes, by: \.measure)

        func signature(_ measure: Int) -> String {
            (byMeasure[measure] ?? [])
                .sorted { $0.startSeconds < $1.startSeconds }
                .map { "\($0.track).\($0.pitch)" }
                .joined(separator: ",")
        }
        // Calculées UNE fois pour tout le fichier — la confirmation par voisinage ci-dessous en a
        // besoin dans les deux sens (avant ET après), jamais seulement pour la mesure en cours.
        let signatures = Dictionary(uniqueKeysWithValues: (1...maxMeasure).map { ($0, signature($0)) })

        /// Vrai quand `a` et `b` sont deux mesures NON VIDES au contenu rigoureusement identique.
        func signaturesMatch(_ a: Int, _ b: Int) -> Bool {
            guard let sigA = signatures[a], let sigB = signatures[b], !sigA.isEmpty else { return false }
            return sigA == sigB
        }

        var firstOccurrence: [String: Int] = [:]
        var mapping: [Int: Int] = [:]
        for measure in 1...maxMeasure {
            let sig = signatures[measure] ?? ""
            guard !sig.isEmpty else { mapping[measure] = measure; continue }
            // Un candidat de repli existe (`earlier`) — mais on ne l'accepte que si un voisin,
            // avant ou après, confirme que ce n'est pas une coïncidence isolée : voir la
            // documentation ci-dessus.
            if let earlier = firstOccurrence[sig],
               signaturesMatch(measure - 1, earlier - 1) || signaturesMatch(measure + 1, earlier + 1) {
                mapping[measure] = earlier
            } else {
                if firstOccurrence[sig] == nil { firstOccurrence[sig] = measure }
                mapping[measure] = measure
            }
        }
        return mapping
    }
}
