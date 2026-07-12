import AVFAudio

@MainActor
final class MessageSpeechService {
    private let synthesizer = AVSpeechSynthesizer()

    func speak(_ text: String) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        let utterance = AVSpeechUtterance(string: value)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
