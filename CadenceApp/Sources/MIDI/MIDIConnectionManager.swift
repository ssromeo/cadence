import Foundation
import CoreMIDI

/// Détecte un clavier MIDI branché en filaire (câble MIDI-vers-Lightning, ou un clavier
/// USB-MIDI via l'adaptateur Lightning-vers-USB d'Apple) — la première brique d'entrée MIDI
/// matérielle de l'app, jusqu'ici entièrement passive (importer un fichier, jamais jouer en
/// direct sur un vrai clavier). Reste volontairement minimal pour l'instant : détecter la
/// connexion et écouter les notes jouées, sans encore les relier à un exercice — cette écoute
/// sert de fondation pour ce qui vient après (jouer la réponse sur un vrai clavier, repérer une
/// fausse note en direct), pas encore le produit fini.
///
/// **CoreMIDI ne fonctionne PAS dans le Simulateur iOS.** Apple ne l'a jamais implémenté au-delà
/// d'une coquille qui compile mais ne voit jamais aucune source, quel que soit le câble branché
/// sur le Mac hôte. `isConnected` restera donc toujours `false` en Simulateur — c'est le
/// comportement ATTENDU, pas un signe de bogue — et ce code n'est réellement vérifiable que sur un
/// vrai iPhone avec un clavier branché.
@MainActor
@Observable
final class MIDIConnectionManager {
    private(set) var isConnected = false
    private(set) var connectedDeviceName: String?
    /// La dernière note reçue depuis le clavier — seulement un retour visuel ("ça marche
    /// vraiment"), pas encore consommée par un exercice. `nil` tant qu'aucune note n'a encore été
    /// jouée depuis la connexion.
    private(set) var lastNoteOn: (pitch: Int, velocity: Int)?

    // `nonisolated(unsafe)` — pas par négligence : `deinit` s'exécute TOUJOURS hors de l'acteur
    // principal en Swift, même pour une classe `@MainActor`, donc libérer ces deux entiers
    // opaques (jamais des pointeurs Swift, voir plus bas) dans `deinit` a besoin d'y accéder sans
    // isolement. Sûr ici précisément parce que rien d'autre ne les touche plus une fois `deinit`
    // atteint — le seul autre accès, dans `setUp`/`refreshConnectedSources`, reste sur l'acteur
    // principal comme le reste de la classe.
    nonisolated(unsafe) private var client = MIDIClientRef()
    nonisolated(unsafe) private var inputPort = MIDIPortRef()

    init() {
        setUp()
    }

    deinit {
        // `MIDIPortRef`/`MIDIClientRef` sont des entiers opaques (`UInt32`), jamais des pointeurs
        // Swift — 0 est la valeur "jamais créé" documentée par CoreMIDI, pas une adresse à tester.
        if inputPort != 0 { MIDIPortDispose(inputPort) }
        if client != 0 { MIDIClientDispose(client) }
    }

    private func setUp() {
        // Le bloc de notification tourne sur le fil interne de CoreMIDI, jamais le fil principal —
        // `Task { @MainActor in ... }` revient explicitement sur l'acteur principal avant de
        // toucher `isConnected`/`connectedDeviceName`, exactement comme `AppStore` le fait déjà
        // pour ses propres tâches de fond.
        let status = MIDIClientCreateWithBlock("Cadence" as CFString, &client) { [weak self] _ in
            Task { @MainActor in self?.refreshConnectedSources() }
        }
        guard status == noErr else { return }

        MIDIInputPortCreateWithBlock(client, "Entrée Cadence" as CFString, &inputPort) { [weak self] packetList, _ in
            let notes = Self.noteOnEvents(in: packetList)
            guard let last = notes.last else { return }
            Task { @MainActor in self?.lastNoteOn = last }
        }

        refreshConnectedSources()
    }

    /// Réénumère les sources MIDI disponibles et se connecte à TOUTES — un clavier peut exposer
    /// plusieurs ports, et rien ne dit lequel l'utilisateur jouera. Appelée à la création, puis à
    /// chaque changement de configuration (branchement/débranchement) via le bloc de notification.
    private func refreshConnectedSources() {
        let count = MIDIGetNumberOfSources()
        guard count > 0 else {
            isConnected = false
            connectedDeviceName = nil
            return
        }
        var firstName: String?
        for index in 0..<count {
            let source = MIDIGetSource(index)
            MIDIPortConnectSource(inputPort, source, nil)
            if firstName == nil { firstName = Self.displayName(of: source) }
        }
        isConnected = true
        connectedDeviceName = firstName
    }

    private static func displayName(of object: MIDIObjectRef) -> String? {
        var unmanagedName: Unmanaged<CFString>?
        let status = MIDIObjectGetStringProperty(object, kMIDIPropertyDisplayName, &unmanagedName)
        guard status == noErr, let unmanagedName else { return nil }
        return unmanagedName.takeRetainedValue() as String
    }

    /// Extrait les "note on" (vélocité > 0, voir `MIDIFileParser` pour la même convention côté
    /// fichier : une vélocité de 0 sur un "note on" EST un "note off") d'un paquet MIDI brut reçu
    /// du port d'entrée. Un `MIDIPacketList` empile des paquets de longueur VARIABLE — jamais
    /// recopier un `MIDIPacket` par valeur puis avancer dessus avec `MIDIPacketNext` : son adresse
    /// ne pointerait plus dans le tampon d'origine, et le paquet "suivant" serait lu n'importe où.
    /// Une seule conversion en pointeur MUTABLE au départ, jamais recopiée depuis, résout ça.
    nonisolated private static func noteOnEvents(in packetList: UnsafePointer<MIDIPacketList>) -> [(pitch: Int, velocity: Int)] {
        var events: [(pitch: Int, velocity: Int)] = []
        let mutableList = UnsafeMutablePointer(mutating: packetList)
        var packetPtr = withUnsafeMutablePointer(to: &mutableList.pointee.packet) { $0 }
        let count = Int(packetList.pointee.numPackets)

        for _ in 0..<count {
            let packet = packetPtr.pointee
            let length = Int(packet.length)
            let bytes: [UInt8] = withUnsafeBytes(of: packet.data) { raw in Array(raw.prefix(length)) }

            var i = 0
            while i < bytes.count {
                let status = bytes[i]
                if status & 0xF0 == 0x90, i + 2 < bytes.count {
                    let pitch = Int(bytes[i + 1])
                    let velocity = Int(bytes[i + 2])
                    if velocity > 0 { events.append((pitch, velocity)) }
                    i += 3
                } else if status & 0xF0 == 0x80 {
                    i += 3 // note off, 3 octets, sans intérêt ici
                } else {
                    i += 1
                }
            }
            packetPtr = UnsafeMutablePointer(mutating: MIDIPacketNext(packetPtr))
        }
        return events
    }
}
