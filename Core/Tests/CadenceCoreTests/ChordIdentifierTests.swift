import XCTest
@testable import CadenceCore

final class ChordIdentifierTests: XCTestCase {

    func testRootPositionCMajor() {
        // do-mi-sol, basse = do : accord à l'état fondamental.
        let chord = ChordIdentifier.identify(pitchClasses: [0, 4, 7], bassPitchClass: 0)
        XCTAssertEqual(chord?.rootPitchClass, 0)
        XCTAssertEqual(chord?.quality, .major)
        XCTAssertEqual(chord?.inversion, 0)
    }

    func testFirstInversionCMajor() {
        // mi-sol-do : mêmes classes de hauteur, mais la basse est le mi — premier renversement.
        // C'est le cas qui distingue un identifiant "par gabarit depuis chaque note candidate"
        // d'un identifiant naïf qui supposerait que la basse EST la fondamentale.
        let chord = ChordIdentifier.identify(pitchClasses: [0, 4, 7], bassPitchClass: 4)
        XCTAssertEqual(chord?.rootPitchClass, 0)
        XCTAssertEqual(chord?.quality, .major)
        XCTAssertEqual(chord?.inversion, 1)
    }

    func testSecondInversionCMajor() {
        // sol-do-mi : basse = sol — second renversement.
        let chord = ChordIdentifier.identify(pitchClasses: [0, 4, 7], bassPitchClass: 7)
        XCTAssertEqual(chord?.inversion, 2)
        XCTAssertEqual(chord?.rootPitchClass, 0)
    }

    func testMinorTriad() {
        // la-do-mi : la mineur.
        let chord = ChordIdentifier.identify(pitchClasses: [9, 0, 4], bassPitchClass: 9)
        XCTAssertEqual(chord?.rootPitchClass, 9)
        XCTAssertEqual(chord?.quality, .minor)
    }

    func testDiminishedTriad() {
        // si-ré-fa : si diminué (viie degré de do majeur).
        let chord = ChordIdentifier.identify(pitchClasses: [11, 2, 5], bassPitchClass: 11)
        XCTAssertEqual(chord?.rootPitchClass, 11)
        XCTAssertEqual(chord?.quality, .diminished)
    }

    func testDominantSeventh() {
        // sol-si-ré-fa : sol septième de dominante.
        let chord = ChordIdentifier.identify(pitchClasses: [7, 11, 2, 5], bassPitchClass: 7)
        XCTAssertEqual(chord?.rootPitchClass, 7)
        XCTAssertEqual(chord?.quality, .dominantSeventh)
    }

    func testSus4() {
        let chord = ChordIdentifier.identify(pitchClasses: [0, 5, 7], bassPitchClass: 0)
        XCTAssertEqual(chord?.quality, .sus4)
    }

    func testUnrecognizableClusterReturnsNil() {
        // do-do dièse-ré : cluster chromatique serré, pas un accord tonal reconnu.
        let chord = ChordIdentifier.identify(pitchClasses: [0, 1, 2], bassPitchClass: 0)
        XCTAssertNil(chord)
    }

    func testTwoNotesAreNotAChord() {
        XCTAssertNil(ChordIdentifier.identify(pitchClasses: [0, 7], bassPitchClass: 0))
    }
}
