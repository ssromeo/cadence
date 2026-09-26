# Cadence

Une app iOS d'apprentissage du piano et du solfège, centrée sur la maîtrise théorique et
auditive plutôt que sur "jouer un morceau" — ce que Simply Piano, Flowkey, Yousician et Skoove
font déjà bien.

## Deux piliers

1. **Importer son propre MIDI** → l'app l'analyse (accords, tonalité, intervalles) et en tire
   des exercices sur mesure. Traitement **100 % local** — un fichier importé n'est jamais envoyé
   nulle part.
2. **Mode cours par gamme** → choisir une tonalité, s'entraîner dessus.

Les deux alimentent le même système de mémorisation à répétition espacée.

## Structure du dépôt

```
Core/         Package Swift pur — parsing MIDI, théorie, génération de quiz.
              Zéro dépendance UI : `cd Core && swift test` suffit, sans simulateur.
CadenceApp/   L'app SwiftUI : import, quiz, design system, shaders Metal.
project.yml   Manifeste xcodegen — source de vérité du projet Xcode.
              `xcodegen generate` le régénère après tout ajout/retrait de fichier.
```

**Pourquoi cette séparation.** La théorie musicale (est-ce un accord de fa majeur ? quelle
tonalité ?) est vérifiable par des tests unitaires ordinaires, indépendamment de SwiftUI. La
faire dépendre de l'UI aurait rendu chaque règle de théorie testable seulement en lançant l'app
à la main.

## État actuel — MVP

Fait, testé (32 tests, `Core`) :
- Lecteur de fichier MIDI standard (SMF, formats 0/1) : notes, vélocités, tempo variable,
  running status.
- Détection d'accords par gabarits de classes de hauteur, renversements compris.
- Détection de tonalité (Krumhansl-Schmuckler).
- Regroupement en accords + rattachement au degré de la tonalité (analyse harmonique).
- Génération d'un quiz de reconnaissance d'intervalles à partir des notes réellement importées.

Fait, dans l'app :
- Écran d'accueil (import de fichier, orbe animé en shader Metal, verre liquide).
- Écran de quiz (écoute d'un intervalle joué par synthèse de tons, choix multiples, score).

**Pas encore fait** — dans l'ordre où le brief d'origine les priorise : dictée musicale, lecture
flash, mode erreur volontaire, harmonisation temps réel, carte harmonique visuelle, transposition
mentale, cycle des quintes interactif, détection clavier MIDI externe, stockage local
(Core Data/SQLite) du système de répétition espacée, diagnostic de points faibles.

## Développer

```bash
cd Core && swift test          # théorie musicale, sans Xcode
xcodegen generate              # après avoir ajouté/retiré un fichier de CadenceApp/ ou Core/
open Cadence.xcodeproj         # lancer l'app dans le simulateur
```

## Licence

[MIT](LICENSE).
