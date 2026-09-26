import SwiftUI
import CadenceCore

/// Une octave de clavier qu'on peut taper directement — l'AUTRE façon de répondre à "quel est le
/// nom de cette note", en plus du QCM. Trouver la touche du bon geste, sans lire quatre libellés,
/// est une compétence différente et tout aussi réelle que reconnaître un nom écrit ; beaucoup de
/// pianistes pensent d'abord en positions de touches, pas en syllabes.
///
/// **Pourquoi aucune touche n'est étiquetée AVANT la réponse.** Un vrai piano ne porte pas les
/// noms de ses touches — les montrer à l'avance transformerait le clavier en un simple QCM à
/// douze choix au lieu de tester la position elle-même. Le nom de la touche correcte (et de celle
/// tapée, si elle diffère) n'apparaît qu'une fois la réponse donnée.
struct PianoOctavePicker: View {
    let key: MusicalKey
    var tappedClass: Int?
    var correctClass: Int?
    let onTap: (Int) -> Void

    /// Classes de hauteur des sept touches blanches, dans l'ordre do-ré-mi-fa-sol-la-si.
    private static let whitePitchClasses = [0, 2, 4, 5, 7, 9, 11]
    /// (index de la touche blanche APRÈS laquelle la noire se place, classe de hauteur de cette
    /// noire) — vide après mi et après si, comme sur un clavier réel.
    private static let blackKeys: [(afterWhiteIndex: Int, pitchClass: Int)] =
        [(0, 1), (1, 3), (3, 6), (4, 8), (5, 10)]

    private var width: CGFloat { UIScreen.main.bounds.width - 48 }
    private var whiteKeyWidth: CGFloat { width / 7 }
    private let height: CGFloat = 150

    var body: some View {
        ZStack(alignment: .topLeading) {
            // LARGEUR EXPLICITE par touche (`whiteKeyWidth`), jamais `.frame(maxWidth: .infinity)`
            // sur des voisines dans ce `HStack` — même règle que partout ailleurs dans l'app,
            // pour la même raison : plusieurs `Button{Text}` flexibles voisins se sont déjà
            // affichés vides sur ce SDK (voir `QuizView.choiceGrid`).
            HStack(spacing: 0) {
                ForEach(Array(Self.whitePitchClasses.enumerated()), id: \.offset) { _, pitchClass in
                    whiteKey(pitchClass: pitchClass)
                }
            }
            ForEach(Array(Self.blackKeys.enumerated()), id: \.offset) { _, entry in
                blackKey(afterWhiteIndex: entry.afterWhiteIndex, pitchClass: entry.pitchClass)
            }
        }
        .frame(width: width, height: height)
    }

    // MARK: - Touches

    private func fillColor(for pitchClass: Int, base: Color) -> Color {
        guard let tappedClass, let correctClass else { return base }
        if pitchClass == correctClass { return C.good }
        if pitchClass == tappedClass { return C.bad }
        return base
    }

    /// Le nom ne se révèle qu'après coup, et seulement sur les deux touches qui comptent — la
    /// bonne, et celle tapée si elle diffère (les deux sont la même quand la réponse est juste).
    private func revealedLabel(for pitchClass: Int) -> String? {
        guard let tappedClass, pitchClass == correctClass || pitchClass == tappedClass else { return nil }
        return NoteNaming.name(forPitchClass: pitchClass, preferFlats: key.prefersFlats)
    }

    private func whiteKey(pitchClass: Int) -> some View {
        Button {
            guard tappedClass == nil else { return }
            onTap(pitchClass)
        } label: {
            VStack {
                Spacer()
                if let label = revealedLabel(for: pitchClass) {
                    Text(label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(C.ink)
                        .padding(.bottom, 10)
                }
            }
            .frame(width: whiteKeyWidth - 3, height: height)
            .background(fillColor(for: pitchClass, base: .white))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(C.line, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(tappedClass != nil)
    }

    private func blackKey(afterWhiteIndex: Int, pitchClass: Int) -> some View {
        let blackWidth = whiteKeyWidth * 0.62
        let blackHeight = height * 0.6
        let x = CGFloat(afterWhiteIndex + 1) * whiteKeyWidth

        return Button {
            guard tappedClass == nil else { return }
            onTap(pitchClass)
        } label: {
            VStack {
                Spacer()
                if let label = revealedLabel(for: pitchClass) {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.bottom, 8)
                }
            }
            .frame(width: blackWidth, height: blackHeight)
            .background(fillColor(for: pitchClass, base: C.ink))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(tappedClass != nil)
        .offset(x: x - blackWidth / 2, y: 0)
    }
}
