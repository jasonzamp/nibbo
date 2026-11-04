import AVFoundation

/// Measures microphone loudness so the prompter can pause when you stop talking.
/// Simple energy-based detection: no audio is stored or sent anywhere.
final class VoiceActivityDetector {
    private let engine = AVAudioEngine()
    private var running = false
    var onLevel: ((Float) -> Void)?

    func start(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(begin())
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted && self.begin()) }
            }
        default:
            completion(false)
        }
    }

    private func begin() -> Bool {
        guard !running else { return true }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += samples[i] * samples[i] }
            let rms = (sum / Float(n)).squareRoot()
            let db = 20 * log10(max(rms, 1e-7))
            DispatchQueue.main.async { self?.onLevel?(db) }
        }

        do {
            try engine.start()
            running = true
            return true
        } catch {
            input.removeTap(onBus: 0)
            return false
        }
    }

    func stop() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }
}
