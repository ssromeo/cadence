import SwiftUI
import CadenceCore

/// Le parcours tiré d'UN MORCEAU IMPORTÉ : "qu'est-ce qu'il y a à travailler dans ce fichier
/// précis ?" — voir `ExerciseGenerator.pathFromImportedMusic`. Même esprit que `ScalePathView`
/// (un thème à la fois, jamais un unique quiz qui mélange tout sans distinction), mais deux
/// différences assumées, dictées par la nature de la source :
///
/// **Un seul nœud par thème, pas trois niveaux.** `ScalePathView` peut se permettre "reprise" et
/// "défi" parce qu'une gamme choisie a une variété INFINIE — `scaleExercises` en retire un lot
/// frais à chaque appel. Un morceau importé, lui, ne contient QUE ce qu'il contient : il n'y a pas
/// de second lot différent à tirer pour un "niveau 2" qui ne serait, sur cette source, qu'une
/// resucée du même contenu sous un autre nom.
///
/// **Les thèmes sont CLASSÉS et FILTRÉS, jamais dans un ordre fixe.** `ScalePathView` suit
/// toujours le même `themeOrder` : une gamme majeure a toujours ses sept degrés, ses sept notes,
/// son armure. Un morceau importé n'a AUCUNE de ces garanties — un fichier sans accord plaqué ne
/// doit simplement pas proposer "Accords", et celui qui déborde d'intervalles doit mettre ce
/// thème-là en avant plutôt que de le noyer à sa place alphabétique. Voir
/// `ExerciseGenerator.ImportedMusicPath.themes`, déjà trié et filtré côté moteur — cette vue
/// n'a plus qu'à l'afficher dans l'ordre reçu.
struct MusicPathView: View {
    let onBack: () -> Void

    @Environment(AppStore.self) private var store
    @State private var activeTheme: ExerciseGenerator.ImportedMusicTheme?

    /// Lu EN DIRECT depuis le store à chaque rendu, jamais reçu figé en paramètre — voir "Mes
    /// chansons" dans `QuizView`, accessible DEPUIS l'exercice embarqué ici : changer de morceau
    /// sans quitter cet écran met à jour `store.musicPath`, et un retour arrière doit alors
    /// retrouver le NOUVEAU morceau, pas l'ancien capturé à l'ouverture.
    private var path: ExerciseGenerator.ImportedMusicPath? { store.musicPath }
    private var songName: String? {
        guard case .ready(let fileName, _, _) = store.importState else { return nil }
        return fileName
    }

    var body: some View {
        ZStack(alignment: .top) {
            if activeTheme != nil {
                // Pas de "terminé" à cocher ici, contrairement à `ScalePathView` : un thème tiré
                // d'un morceau n'a pas de progression persistante d'une visite à l'autre — son
                // contenu peut changer si le morceau est réimporté ou recompte différemment ses
                // mesures (voir `restartSession`, qui régénère ce thème plutôt que de rejouer une
                // liste figée).
                QuizView()
                    .padding(.top, 52)
                    .transition(.opacity)
            } else if let path, let songName {
                pathScroll(path: path, songName: songName)
                    .transition(.opacity)
            } else {
                // Le morceau a disparu sous nos pieds (supprimé depuis "Mes chansons" pendant
                // qu'on regardait son parcours, par exemple) — repartir en arrière plutôt que de
                // montrer un écran vide sans explication.
                Color.clear.onAppear(perform: onBack)
            }

            backButton {
                if activeTheme != nil {
                    withAnimation(.easeInOut(duration: 0.2)) { activeTheme = nil }
                } else {
                    onBack()
                }
            }
        }
    }

    // MARK: - Le chemin

    private func pathScroll(path: ExerciseGenerator.ImportedMusicPath, songName: String) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                header(songName: songName, key: path.key)

                ForEach(Array(path.themes.enumerated()), id: \.1.id) { index, theme in
                    themeCard(theme, isMostPresent: index == 0 && theme.focus != .speed)
                }

                Spacer(minLength: 40)
            }
            .padding(.horizontal, 24)
            .padding(.top, 76)
            .padding(.bottom, 140)
        }
    }

    private func header(songName: String, key: MusicalKey) -> some View {
        VStack(spacing: 4) {
            Text("Parcours").font(.system(size: 15)).foregroundStyle(C.ink2)
            Text(songName)
                .font(.system(size: 26, weight: .bold, design: .rounded)).foregroundStyle(C.ink)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(key.name().capitalized)
                .font(.system(size: 14, weight: .medium)).foregroundStyle(C.inkFaint)
        }
        .padding(.bottom, 8)
    }

    /// UNE carte par thème — icône, nom, et le COMPTE d'exercices trouvés dans CE morceau : c'est
    /// ce compte, pas un simple libellé générique, qui répond à "qu'est-ce qu'il y a à travailler
    /// ici" d'un coup d'œil, avant même d'entrer dans le thème.
    /// **Bogue de rendu confirmé sur ce SDK (bêta), un QUATRIÈME après ceux déjà documentés dans
    /// `LiquidGlass.swift`, `StaffView.swift`, `QuizView.libraryButtonOverlay` et
    /// `PianoOctavePicker.swift`.** `.liquidGlass()` appliqué DIRECTEMENT au contenu à l'intérieur
    /// du label d'un `Button` — surtout combiné à `.frame(maxWidth: .infinity)` et plusieurs
    /// `Text` — peignait des cartes ENTIÈREMENT VIDES : seul le dégradé de fond du verre liquide
    /// apparaissait, sans l'icône, sans le nom du thème, sans le compte d'exercices, sans le
    /// chevron. Vérifié par capture d'écran (voir le rapport : "gros boutons sans texte" au
    /// moment précis où le parcours d'un morceau importé s'affiche). Comme pour
    /// `SongLibraryView.row` — qui fonctionne déjà — la correction sort `.liquidGlass()` ET
    /// `.frame(maxWidth: .infinity)` HORS du `Button`, appliqués à sa coque plutôt qu'au contenu
    /// de son label : le label lui-même ne garde qu'un `.padding()` et un `.contentShape()`.
    private func themeCard(_ theme: ExerciseGenerator.ImportedMusicTheme, isMostPresent: Bool) -> some View {
        Button {
            store.startImportedMusicFocus(theme)
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { activeTheme = theme }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(color(for: theme.focus)).frame(width: 52, height: 52)
                    Image(systemName: icon(for: theme.focus))
                        .font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(theme.focus.displayName)
                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                            .foregroundStyle(C.ink)
                        if isMostPresent {
                            Text("LE PLUS PRÉSENT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(color(for: theme.focus), in: Capsule())
                        }
                    }
                    Text(exerciseCountLabel(theme))
                        .font(.system(size: 13)).foregroundStyle(C.inkFaint)
                }
            }
            .padding(16)
            .padding(.trailing, 28)
            .contentShape(Rectangle())
            // `.overlay(alignment: .trailing)`, JAMAIS `Spacer()` — voir la documentation
            // au-dessus de cette fonction : c'est précisément `Spacer()` dans ce `HStack`,
            // combiné à `.frame(maxWidth: .infinity)` sur le `Button` depuis l'extérieur, qui
            // peignait la carte entièrement vide. `.overlay()` pousse le chevron au bord sans
            // jamais introduire la moindre vue flexible à l'intérieur du label.
            .overlay(alignment: .trailing) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(C.inkFaint)
                    .padding(.trailing, 16)
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .liquidGlass(radius: 24, tint: color(for: theme.focus))
    }

    private func exerciseCountLabel(_ theme: ExerciseGenerator.ImportedMusicTheme) -> String {
        let n = theme.exercises.count
        switch theme.focus {
        case .speed:
            return "\(n) questions mélangées"
        default:
            return n > 1 ? "\(n) exercices tirés du morceau" : "1 exercice tiré du morceau"
        }
    }

    // MARK: - Apparence par thème — même mapping que `ScalePathView`, pour que "Accords" ou
    // "Intervalles" gardent TOUJOURS la même couleur et la même icône, qu'ils viennent d'une
    // gamme choisie ou d'un morceau importé.

    private func color(for focus: ExerciseGenerator.ScaleFocus) -> Color {
        switch focus {
        case .noteNames: C.apricot
        case .degrees: C.gold
        case .intervals: C.coral
        case .chords: C.lilac
        case .keySignature: C.ink2
        case .speed: C.good
        }
    }

    private func icon(for focus: ExerciseGenerator.ScaleFocus) -> String {
        switch focus {
        case .noteNames: "music.note.list"
        case .degrees: "list.number"
        case .intervals: "arrow.up.arrow.down"
        case .chords: "pianokeys"
        case .keySignature: "number.square.fill"
        case .speed: "bolt.fill"
        }
    }

    // MARK: - Retour

    private func backButton(_ action: @escaping () -> Void) -> some View {
        HStack {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(C.ink)
                    .frame(width: 40, height: 40)
                    .liquidGlass(radius: 20)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }
}
