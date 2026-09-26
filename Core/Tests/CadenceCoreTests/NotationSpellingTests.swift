import XCTest
@testable import CadenceCore

final class NotationSpellingTests: XCTestCase {

    func testMiddleCIsNaturalInBothConventions() {
        for preferFlats in [true, false] {
            let spelling = NotationSpelling.spell(pitch: 60, preferFlats: preferFlats)
            XCTAssertEqual(spelling.letterStep, 0) // do
            XCTAssertEqual(spelling.octave, 4)
            XCTAssertEqual(spelling.accidental, .natural)
        }
    }

    func testBlackKeySpelledSharpOrFlatDependingOnConvention() {
        let csharp = NotationSpelling.spell(pitch: 61, preferFlats: false)
        XCTAssertEqual(csharp.letterStep, 0) // do dièse : reste sur la ligne du DO
        XCTAssertEqual(csharp.accidental, .sharp)

        let dflat = NotationSpelling.spell(pitch: 61, preferFlats: true)
        XCTAssertEqual(dflat.letterStep, 1) // ré bémol : sur la ligne du RÉ
        XCTAssertEqual(dflat.accidental, .flat)
    }

    func testOctaveBoundaryAtB3ToC4() {
        // Si le passage à l'octave supérieure était mal calculé (division entière, décalage
        // d'un demi-ton), c'est ICI que ça se verrait : si3 et do4 doivent être des positions
        // diatoniques CONSÉCUTIVES malgré le changement d'octave.
        let b3 = NotationSpelling.spell(pitch: 59, preferFlats: false)
        let c4 = NotationSpelling.spell(pitch: 60, preferFlats: false)
        XCTAssertEqual(b3.octave, 3)
        XCTAssertEqual(c4.octave, 4)
        XCTAssertEqual(c4.diatonicIndex - b3.diatonicIndex, 1)
    }

    func testDiatonicIndexIncreasesMonotonicallyWithPitch() {
        // La position diatonique ne doit jamais reculer quand la hauteur MIDI monte — sans quoi
        // une note dessinerait PLUS BAS qu'une note plus grave qui la précède.
        var previous = NotationSpelling.spell(pitch: 21, preferFlats: false).diatonicIndex
        for pitch in 22...108 {
            let current = NotationSpelling.spell(pitch: pitch, preferFlats: false).diatonicIndex
            XCTAssertGreaterThanOrEqual(current, previous, "régression à la hauteur \(pitch)")
            previous = current
        }
    }

    func testTrebleStaffReferenceNotesLandOnExpectedLines() {
        // E4 (bas de la portée) et F5 (haut de la portée) doivent être séparés d'exactement huit
        // demi-espaces — la hauteur de la portée elle-même, en clé de sol.
        let e4 = NotationSpelling.spell(pitch: 64, preferFlats: false) // mi4
        let f5 = NotationSpelling.spell(pitch: 77, preferFlats: false) // fa5
        XCTAssertEqual(e4.letterStep, 2)
        XCTAssertEqual(f5.diatonicIndex - e4.diatonicIndex, 8)
    }
}
