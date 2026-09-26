import XCTest
@testable import CadenceCore

final class KeyDetectorTests: XCTestCase {

    /// Réplique privée des profils K-K pour construire des entrées de test qui doivent
    /// correspondre EXACTEMENT à une tonalité donnée — la façon la plus directe de vérifier que
    /// la rotation et la corrélation dans `KeyDetector` sont mathématiquement correctes, plutôt
    /// que de deviner un morceau plausible et espérer qu'il tombe juste.
    private static let majorProfile: [Double] = [6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88]
    private static let minorProfile: [Double] = [6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17]

    private func rotate(_ profile: [Double], to tonic: Int) -> [Double] {
        (0..<12).map { profile[(($0 - tonic) % 12 + 12) % 12] }
    }

    func testDetectsCMajorFromItsOwnProfile() {
        let key = KeyDetector.detectKey(pitchClassWeights: rotate(Self.majorProfile, to: 0))
        XCTAssertEqual(key.tonicPitchClass, 0)
        XCTAssertTrue(key.isMajor)
    }

    func testDetectsFSharpMinorFromItsOwnProfile() {
        let key = KeyDetector.detectKey(pitchClassWeights: rotate(Self.minorProfile, to: 6))
        XCTAssertEqual(key.tonicPitchClass, 6)
        XCTAssertFalse(key.isMajor)
    }

    func testEveryTonicIsRecoverable() {
        // Les 24 tonalités, une par une : c'est le test qui aurait attrapé une erreur de signe
        // dans la formule de rotation — une inversion du sens de rotation ne se serait vue que
        // sur certaines toniques, jamais toutes, selon la symétrie du profil.
        for tonic in 0..<12 {
            let major = KeyDetector.detectKey(pitchClassWeights: rotate(Self.majorProfile, to: tonic))
            XCTAssertEqual(major.tonicPitchClass, tonic, "majeur, tonique \(tonic)")
            XCTAssertTrue(major.isMajor)

            let minor = KeyDetector.detectKey(pitchClassWeights: rotate(Self.minorProfile, to: tonic))
            XCTAssertEqual(minor.tonicPitchClass, tonic, "mineur, tonique \(tonic)")
            XCTAssertFalse(minor.isMajor)
        }
    }

    func testDetectKeyFromNotesWeightsByDuration() {
        // Une seule note très longue doit peser davantage qu'une poignée de notes brèves dans
        // la détection — c'est la raison d'être du pondérage par durée plutôt que par comptage.
        // Un do tenu huit secondes contre sept notes brèves ailleurs doit encore pencher pour
        // une tonalité où do domine.
        let notes = [
            MIDINoteEvent(pitch: 60, velocity: 80, startSeconds: 0, durationSeconds: 8.0, track: 0, channel: 0), // do, long
            MIDINoteEvent(pitch: 63, velocity: 80, startSeconds: 8, durationSeconds: 0.1, track: 0, channel: 0),
            MIDINoteEvent(pitch: 66, velocity: 80, startSeconds: 8.1, durationSeconds: 0.1, track: 0, channel: 0),
            MIDINoteEvent(pitch: 69, velocity: 80, startSeconds: 8.2, durationSeconds: 0.1, track: 0, channel: 0),
        ]
        let key = KeyDetector.detectKey(from: notes)
        XCTAssertEqual(key.tonicPitchClass, 0, "le do tenu longuement doit dominer la détection")
    }

    func testMajorKeyNamesUseSharpsOnTheSharpSide() {
        let sol = MusicalKey(tonicPitchClass: 7, isMajor: true) // sol majeur : un dièse (fa#)
        XCTAssertFalse(sol.prefersFlats)
        let fa = MusicalKey(tonicPitchClass: 5, isMajor: true) // fa majeur : un bémol (si♭)
        XCTAssertTrue(fa.prefersFlats)
    }

    func testScalePitchClassesForCMajor() {
        let key = MusicalKey(tonicPitchClass: 0, isMajor: true)
        XCTAssertEqual(key.scalePitchClasses, [0, 2, 4, 5, 7, 9, 11])
    }

    func testScalePitchClassesForANaturalMinor() {
        let key = MusicalKey(tonicPitchClass: 9, isMajor: false)
        XCTAssertEqual(key.scalePitchClasses, [9, 11, 0, 2, 4, 5, 7])
    }
}
