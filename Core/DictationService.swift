import Foundation
import Speech
import OSLog

@MainActor
final class DictationService: ObservableObject {
    static let shared = DictationService()

    @Published var isListening = false
    @Published var transcribedText = ""
    @Published var authorizationStatus: SFSpeechRecognizerAuthorizationStatus = .notDetermined

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
        checkAuthorization()
    }

    func checkAuthorization() {
        authorizationStatus = SFSpeechRecognizer.authorizationStatus()
    }

    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            Task { @MainActor [weak self] in
                self?.authorizationStatus = status
            }
        }
    }

    func startListening() {
        guard authorizationStatus == .authorized else { return }
        guard let speechRecognizer, speechRecognizer.isAvailable else { return }

        stopListening()

        let engine = AVAudioEngine()
        audioEngine = engine
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.taskHint = .dictation
        recognitionRequest = request

        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 8192, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let result {
                transcribedText = result.bestTranscription.formattedString
            }
            if error != nil || (result?.isFinal ?? false) {
                stopListening()
            }
        }

        try? audioEngine?.start()
        isListening = true
    }

    func stopListening() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)

        recognitionRequest = nil
        recognitionTask = nil
        audioEngine = nil
        isListening = false
    }

    func clear() {
        stopListening()
        transcribedText = ""
    }
}
