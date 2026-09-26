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
        .library(name: "CadenceCore", targets: ["CadenceCore"])
    ],
    targets: [
        .target(name: "CadenceCore"),
        .testTarget(name: "CadenceCoreTests", dependencies: ["CadenceCore"])
    ]
)
