import SwiftUI
import CadenceCore

/// Une portée de cinq lignes, en clé de sol, avec une à plusieurs notes — LIRE la musique plutôt
/// que l'entendre.
///
/// **Deux dispositions.** `stacked: false` (par défaut) étale les notes dans le temps — une
/// mélodie, un intervalle : chaque hauteur a sa propre position horizontale. `stacked: true` les
/// pose toutes au même instant — un accord : même position horizontale, hauteurs différentes.
/// Aucune de ces dispositions n'est un cas particulier de l'autre ; les mélanger dans une seule
/// fonction aurait produit un paramètre "x" qui ne veut rien dire pour un accord et un paramètre
/// "empilé" qui ne veut rien dire pour une mélodie.
///
/// **Pourquoi la lecture plutôt que l'écoute.** Reconnaître un intervalle ou un accord sur la
/// portée est une compétence à part entière, distincte de l'entraînement auditif — l'un des
/// manques les plus nets des applications qui se contentent de faire "jouer un morceau". Le
/// quiz auditif garde sa place ailleurs (la dictée musicale prévue au plan de route) ; celui-ci
/// s'adresse à l'œil.
///
/// **Taille passée en paramètre, pas mesurée en interne.** Une première version lisait sa taille
/// via un `GeometryReader` posé directement à l'intérieur de `.glassEffect()` — et cette
/// combinaison ment sur la largeur réelle (mesurée à plus de 22 000 points sur un écran qui en
/// fait 370 : un défaut de ce SDK dans ce cas précis, pas une erreur de calcul de cette vue).
/// En recevant sa taille de l'appelant, mesurée AVANT tout passage par le verre, la vue n'a plus
/// jamais à faire confiance à une mesure prise depuis l'intérieur d'un effet qui la fausse.
struct StaffView: View {
    let pitches: [Int]
    let key: MusicalKey
    var stacked: Bool = false
    var width: CGFloat
    var height: CGFloat = 120

    private let lineSpacing: CGFloat = 13

    /// Confort d'appel pour le cas le plus courant — deux notes, l'une après l'autre.
    init(first: Int, second: Int, key: MusicalKey, width: CGFloat, height: CGFloat = 120) {
        self.pitches = [first, second]
        self.key = key
        self.stacked = false
        self.width = width
        self.height = height
    }

    init(pitches: [Int], key: MusicalKey, stacked: Bool = false, width: CGFloat, height: CGFloat = 120) {
        self.pitches = pitches
        self.key = key
        self.stacked = stacked
        self.width = width
        self.height = height
    }

    var body: some View {
        let midY = height / 2
        let topLineY = midY - 2 * lineSpacing
        let staffWidth = width * 0.82
        let staffLeft = (width - staffWidth) / 2

        ZStack {
            // Les cinq lignes.
            ForEach(0..<5, id: \.self) { i in
                Rectangle()
                    .fill(C.ink.opacity(0.7))
                    .frame(width: staffWidth, height: 1.3)
                    .position(x: width / 2, y: topLineY + CGFloat(i) * lineSpacing)
            }

            // Barres de mesure, au début et à la fin — c'est ELLES qui font "une mesure"
            // plutôt qu'une simple portée sans repère.
            barline(x: staffLeft, topLineY: topLineY)
            barline(x: staffLeft + staffWidth, topLineY: topLineY)

            // Clé de sol. Glyphe Unicode plutôt qu'un tracé vectoriel maison : le rendu système
            // (via la police de repli musicale d'iOS) est fidèle, et un tracé à la main de cette
            // forme précise n'apporterait rien de plus pour beaucoup d'effort.
            Text("𝄞")
                .font(.system(size: lineSpacing * 6.2))
                .foregroundStyle(C.ink)
                .position(x: staffLeft + lineSpacing * 1.4, y: midY + lineSpacing * 0.4)

            ForEach(Array(noteLayout(staffLeft: staffLeft, staffWidth: staffWidth).enumerated()),
                   id: \.offset) { _, placement in
                note(pitch: placement.pitch, x: placement.x, topLineY: topLineY)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Disposition horizontale

    private struct NotePlacement { let pitch: Int; let x: CGFloat }

    /// Où poser chaque note sur l'axe horizontal — c'est tout ce qui distingue les deux modes,
    /// le rendu d'UNE note (`note(pitch:x:topLineY:)`) ne sachant rien de l'un ou l'autre.
    private func noteLayout(staffLeft: CGFloat, staffWidth: CGFloat) -> [NotePlacement] {
        guard !pitches.isEmpty else { return [] }

        if stacked {
            // Toutes au centre du compas. Une seconde collision (deux notes sur des positions
            // de portée adjacentes, comme do-ré) recouvrirait deux têtes si on les superposait
            // telles quelles ; la convention de gravure les décale l'une de l'autre — voir le
            // calcul du décalage plus bas, à même le rendu de la note.
            let x = staffLeft + staffWidth * 0.55
            return pitches.map { NotePlacement(pitch: $0, x: x) }
        } else if pitches.count == 1 {
            let x = staffLeft + staffWidth * 0.55
            return [NotePlacement(pitch: pitches[0], x: x)]
        } else {
            // Réparties dans le tiers médian du compas — pas jusqu'aux barres de mesure, qui
            // doivent rester visuellement détachées des notes qu'elles encadrent.
            let span = staffWidth * 0.56
            let start = staffLeft + staffWidth * 0.30
            return pitches.enumerated().map { i, pitch in
                let t = pitches.count > 1 ? CGFloat(i) / CGFloat(pitches.count - 1) : 0
                return NotePlacement(pitch: pitch, x: start + t * span)
            }
        }
    }

    private func barline(x: CGFloat, topLineY: CGFloat) -> some View {
        Rectangle().fill(C.ink.opacity(0.7)).frame(width: 1.5, height: lineSpacing * 4)
            .position(x: x, y: topLineY + lineSpacing * 2)
    }

    /// Position d'une hauteur, en "demi-espaces de portée" comptés depuis la ligne du HAUT.
    /// 0 = la ligne du haut (fa5), 8 = la ligne du bas (mi4) ; chaque unité vaut un demi-espace,
    /// ligne ou espace confondus — c'est le pas naturel d'une portée, une lettre après l'autre.
    private static let topLineReferenceIndex = NoteSpelling(letterStep: 3, octave: 5, accidental: .natural).diatonicIndex // fa5

    private func staffPosition(for spelling: NoteSpelling) -> Int {
        Self.topLineReferenceIndex - spelling.diatonicIndex
    }

    /// Vrai si une AUTRE note de l'accord occupe la position de portée immédiatement voisine —
    /// le cas où deux têtes se toucheraient si on les alignait sur le même axe. Sert uniquement
    /// en mode empilé : une mélodie n'a pas ce problème, ses notes ne partagent pas leur x.
    private func hasAdjacentStackedNeighbor(position: Int, pitch: Int) -> Bool {
        guard stacked else { return false }
        return pitches.contains { other in
            guard other != pitch else { return false }
            let otherSpelling = NotationSpelling.spell(pitch: other, preferFlats: key.prefersFlats)
            return abs(staffPosition(for: otherSpelling) - position) == 1
        }
    }

    @ViewBuilder
    private func note(pitch: Int, x: CGFloat, topLineY: CGFloat) -> some View {
        let spelling = NotationSpelling.spell(pitch: pitch, preferFlats: key.prefersFlats)
        let position = staffPosition(for: spelling)
        let y = topLineY + CGFloat(position) * (lineSpacing / 2)
        // Hampe vers le bas pour une tête haute sur la portée (au-dessus de la ligne médiane),
        // vers le haut sinon — la convention normale de gravure : la hampe pointe toujours vers
        // le centre de la portée, jamais vers l'extérieur.
        let stemUp = position > 4
        // Décalage de collision : la note la plus GRAVE des deux voisines directes se pousse à
        // droite, l'autre reste en place — c'est la convention (la hampe de la note du dessous
        // passerait sinon en travers de la tête du dessus).
        let collides = hasAdjacentStackedNeighbor(position: position, pitch: pitch)
        let offsetRight = collides && pitches.filter {
            let s = NotationSpelling.spell(pitch: $0, preferFlats: key.prefersFlats)
            return staffPosition(for: s) == position + 1
        }.isEmpty == false
        let noteX = x + (offsetRight ? lineSpacing * 1.05 : 0)

        ZStack {
            ForEach(ledgerLinePositions(for: position), id: \.self) { p in
                Rectangle().fill(C.ink.opacity(0.7))
                    .frame(width: lineSpacing * 1.7, height: 1.3)
                    .position(x: x, y: topLineY + CGFloat(p) * (lineSpacing / 2))
            }

            if spelling.accidental != .natural {
                Text(spelling.accidental.symbol)
                    .font(.system(size: lineSpacing * 1.7, weight: .medium))
                    .foregroundStyle(C.ink)
                    .position(x: x - lineSpacing * 1.3, y: y)
            }

            Rectangle()
                .fill(C.ink)
                .frame(width: 1.4, height: lineSpacing * 3)
                .position(x: noteX + (stemUp ? lineSpacing * 0.52 : -lineSpacing * 0.52),
                         y: y + (stemUp ? -lineSpacing * 1.5 : lineSpacing * 1.5))

            Ellipse()
                .fill(C.ink)
                .frame(width: lineSpacing * 1.2, height: lineSpacing * 0.86)
                .rotationEffect(.degrees(-16))
                .position(x: noteX, y: y)
        }
    }

    /// Les lignes supplémentaires nécessaires pour une note au-delà de la portée. `position`
    /// est négatif au-dessus (plus haut que fa5) ou supérieur à 8 en dessous (plus grave que
    /// mi4) ; les lignes elles-mêmes tombent toujours sur une position PAIRE — une portée
    /// n'a de ligne qu'à intervalle régulier, jamais dans les espaces.
    private func ledgerLinePositions(for position: Int) -> [Int] {
        var lines: [Int] = []
        if position < 0 {
            var p = -2
            while p >= position { lines.append(p); p -= 2 }
        } else if position > 8 {
            var p = 10
            while p <= position { lines.append(p); p += 2 }
        }
        return lines
    }
}
