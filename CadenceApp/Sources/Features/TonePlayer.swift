import AVFoundation

/// Fait ENTENDRE une hauteur MIDI, en synthétisant un ton pur — pas de banque de sons, pas de
/// fichier audio embarqué.
///
/// **Pourquoi pas un vrai son de piano.** Un échantillonneur (`AVAudioUnitSampler` + une banque
/// de sons) donnerait un rendu bien plus riche, mais il faudrait embarquer ou télécharger une
/// banque, ce qui alourdit le premier lancement d'une app qui se veut "locale et légère" par
/// principe. Un ton pur suffit à ENTRAÎNER LA RECONNAISSANCE D'INTERVALLES — ce que l'oreille
/// doit apprendre ici, c'est un rapport de fréquences, qu'un ton sinusoïdal restitue aussi
/// fidèlement qu'un vrai piano. Le rendu réaliste est un raffinement pour plus tard, pas un
/// prérequis du quiz.
@MainActor
final class TonePlayer {
    private let engine = AVAudioEngine()
    private let sampleRate = 44_100.0
    private var sourceNode: AVAudioSourceNode?

    /// Fréquence en cours, en Hz — 0 = silence. Écrite depuis l'acteur principal, LUE depuis le
    /// callback audio temps réel (un thread à part, géré par CoreAudio). Ce n'est pas
    /// verrouillé : dans le pire cas, quelques échantillons à la frontière d'un changement de
    /// note portent la mauvaise fréquence, ce qui donne un déclic inaudible à cette échelle —
    /// un compromis correct pour un prototype, à revoir avec un vrai type atomique le jour où
    /// la lecture doit être irréprochable.
    private var frequency: Double = 0
    private var phase: Double = 0

    init() {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList in
            guard let self else { return noErr }
            let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let thetaIncrement = 2.0 * Double.pi * self.frequency / self.sampleRate
            for frame in 0..<Int(frameCount) {
                // Enveloppe très simple pour éviter le "clic" d'une onde qui démarre à une phase
                // arbitraire — sans elle, chaque note attaquerait par un saut de courant net,
                // audible comme un claquement sec.
                let value = self.frequency > 0 ? Float(sin(self.phase)) * 0.18 : 0
                self.phase += thetaIncrement
                if self.phase > 2 * .pi { self.phase -= 2 * .pi }
                for buffer in buffers {
                    let typed = UnsafeMutableBufferPointer<Float>(buffer)
                    if frame < typed.count { typed[frame] = value }
                }
            }
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        sourceNode = node
        try? engine.start()
    }

    private func hz(forPitch pitch: Int) -> Double {
        440.0 * pow(2.0, Double(pitch - 69) / 12.0)
    }

    /// Joue une hauteur pendant `duration` secondes puis se tait.
    func play(pitch: Int, duration: Double = 0.55) {
        frequency = hz(forPitch: pitch)
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            self?.frequency = 0
        }
    }

    /// Joue une suite de hauteurs l'une après l'autre — l'usage du quiz d'intervalles : on
    /// entend la première note, un silence bref, puis la seconde.
    func playSequence(_ pitches: [Int], noteDuration: Double = 0.5, gap: Double = 0.12) {
        var delay = 0.0
        for pitch in pitches {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.play(pitch: pitch, duration: noteDuration)
            }
            delay += noteDuration + gap
        }
    }
}
