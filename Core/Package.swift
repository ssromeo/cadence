// swift-tools-version:5.10
import PackageDescription

/// CadenceCore — toute la théorie musicale de l'app, en Swift pur.
///
/// Aucune dépendance à SwiftUI, UIKit ou Core Data ici, et c'est la règle qui compte le plus
/// dans ce dossier : le parsing MIDI, la détection d'accords et de tonalité, la génération de
/// quiz doivent pouvoir tourner dans `swift test`, sans simulateur, sans Xcode ouvert. C'est ce
/// qui permet de vérifier "est-ce que Do-Mi-Sol est bien reconnu comme un accord de Do majeur"
/// en une seconde de terminal plutôt qu'en lançant l'app et en importer un fichier à la main.
///
/// L'app (SwiftUI, stockage local, détection MIDI temps réel) est un consommateur de ce paquet,
/// jamais l'inverse.
let package = Package(
    name: "CadenceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "CadenceCore", targets: ["CadenceCore"]),
        // Un exécutable, pas juste une bibliothèque de plus : `cadence-debug` s'installe et se
        // lance depuis le terminal (`swift run cadence-debug <fichier.mid>`), pour la même raison
        // que `CadenceCoreTests` existe déjà — voir `Sources/cadence-debug/main.swift`.
        .executable(name: "cadence-debug", targets: ["cadence-debug"])
    ],
    targets: [
        .target(name: "CadenceCore"),
        .executableTarget(name: "cadence-debug", dependencies: ["CadenceCore"]),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"])
    ]
)
