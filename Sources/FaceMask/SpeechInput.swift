import AVFoundation
import Foundation
import Speech

enum SpeechLanguage: String, CaseIterable {
    case automatic = "auto"
    case korean = "ko-KR"
    case english = "en-US"

    var title: String {
        switch self {
        case .automatic: return "Auto"
        case .korean: return "Korean"
        case .english: return "English"
        }
    }

    var answerRule: String {
        switch self {
        case .automatic:
            return "The user switches between Korean and English. Understand whichever they used, including a rough speech transcript. Reply in that language. Korean is the default when the language is unclear. If one message uses both, reply in the language that carries the question."
        case .korean, .english:
            return "The user speaks \(title). Understand \(title), including a rough speech transcript, and answer only in \(title)."
        }
    }

    var speechFieldDescription: String {
        switch self {
        case .automatic:
            return "The words to speak aloud, in the language the user just used. Korean by default, English when the user spoke English. Plain text of finished sentences. Do not include code, charts, tables, lists, URLs, or markdown."
        case .korean, .english:
            return "The words to speak aloud, in \(title). Plain text of finished sentences. Do not include code, charts, tables, lists, URLs, or markdown."
        }
    }

    static func voiceCode(for text: String) -> String {
        let hangul = text.unicodeScalars.filter { (0xAC00...0xD7A3).contains($0.value) }.count
        var latin = 0
        for scalar in text.unicodeScalars where scalar.value < 128 && CharacterSet.letters.contains(scalar) {
            latin += 1
        }
        if hangul == 0 && latin > 0 { return SpeechLanguage.english.rawValue }
        return SpeechLanguage.korean.rawValue
    }
}

final class SpeechLanguages: ObservableObject {
    @Published private(set) var current: SpeechLanguage

    init() {
        let raw = UserDefaults.standard.string(forKey: "SpeechLanguage") ?? SpeechLanguage.automatic.rawValue
        current = SpeechLanguage(rawValue: raw) ?? .automatic
    }

    func select(_ language: SpeechLanguage) {
        guard language != current else { return }
        current = language
        UserDefaults.standard.set(language.rawValue, forKey: "SpeechLanguage")
    }
}

final class SpeechListener {
    var localeIdentifier = SpeechLanguage.automatic.rawValue
    private let engine = AVAudioEngine()
    private var lanes: [Lane] = []
    private var stopped = true
    private var tapped = false
    private var session = 0
    private var onText: ((String) -> Void)?
    private var onError: ((String) -> Void)?

    private final class Lane {
        let recognizer: SFSpeechRecognizer
        var request: SFSpeechAudioBufferRecognitionRequest?
        var task: SFSpeechRecognitionTask?
        var text = ""
        var confidence: Float = 0
        var restarts = 0
        var generation = 0

        init(recognizer: SFSpeechRecognizer) {
            self.recognizer = recognizer
        }
    }

    func start(onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        session += 1
        let session = session
        stopped = false
        self.onText = onText
        self.onError = onError
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, session == self.session, !self.stopped else { return }
                guard status == .authorized else {
                    onError("Speech recognition is not allowed. Enable it in System Settings.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    DispatchQueue.main.async {
                        guard session == self.session, !self.stopped else { return }
                        guard allowed else {
                            onError("Microphone access is not allowed. Enable it in System Settings.")
                            return
                        }
                        self.begin()
                    }
                }
            }
        }
    }

    func stop() {
        session += 1
        stopped = true
        onText = nil
        onError = nil
        for lane in lanes {
            lane.task?.cancel()
            lane.task = nil
            lane.request?.endAudio()
            lane.request = nil
        }
        lanes = []
        engine.stop()
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
    }

    private func begin() {
        let identifiers = localeIdentifier == SpeechLanguage.automatic.rawValue
            ? [SpeechLanguage.korean.rawValue, SpeechLanguage.english.rawValue]
            : [localeIdentifier]
        lanes = identifiers.compactMap { identifier in
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
                  recognizer.isAvailable else { return nil }
            return Lane(recognizer: recognizer)
        }
        guard !lanes.isEmpty else {
            onError?("Speech recognition is not available on this Mac.")
            return
        }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("Could not open the microphone.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            for lane in self.lanes {
                lane.request?.append(buffer)
            }
        }
        tapped = true
        for lane in lanes {
            arm(lane)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            onError?("Could not open the microphone.")
        }
    }

    private func arm(_ lane: Lane) {
        guard !stopped else { return }
        lane.restarts += 1
        guard lane.restarts <= 8 else {
            lane.task?.cancel()
            lane.task = nil
            lane.request = nil
            guard lanes.contains(where: { $0.task != nil }) else {
                let report = onError
                stop()
                report?("Could not understand the speech.")
                return
            }
            return
        }
        lane.task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        lane.request = request
        lane.generation += 1
        let generation = lane.generation
        let session = session
        lane.task = lane.recognizer.recognitionTask(with: request) { [weak self, weak lane] result, error in
            DispatchQueue.main.async {
                guard let self, let lane, session == self.session, generation == lane.generation, !self.stopped else { return }
                if let result {
                    let transcript = result.bestTranscription
                    let text = transcript.formattedString
                    if !text.isEmpty {
                        lane.text = text
                        let segments = transcript.segments
                        lane.confidence = segments.isEmpty
                            ? 0
                            : segments.reduce(Float(0)) { $0 + $1.confidence } / Float(segments.count)
                        self.publish()
                    }
                }
                guard error != nil else { return }
                if Self.isBenign(error) {
                    self.arm(lane)
                    return
                }
                lane.task = nil
                lane.request = nil
                guard self.lanes.contains(where: { $0.task != nil }) else {
                    let report = self.onError
                    self.stop()
                    report?("Could not understand the speech.")
                    return
                }
            }
        }
    }

    private func publish() {
        let text = preferredText()
        guard !text.isEmpty else { return }
        onText?(text)
    }

    private func preferredText() -> String {
        guard localeIdentifier == SpeechLanguage.automatic.rawValue, lanes.count > 1 else {
            return lanes.first?.text ?? ""
        }
        let korean = lanes.first { $0.recognizer.locale.identifier.lowercased().hasPrefix("ko") }
        let english = lanes.first { $0.recognizer.locale.identifier.lowercased().hasPrefix("en") }
        let ko = korean?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let en = english?.text.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if ko.isEmpty { return en }
        if en.isEmpty { return ko }
        let englishHeard = SpeechLanguage.voiceCode(for: en) == SpeechLanguage.english.rawValue
        if englishHeard, (english?.confidence ?? 0) > (korean?.confidence ?? 0) + 0.08 {
            return en
        }
        return ko
    }

    private static func isBenign(_ error: Error?) -> Bool {
        let ns = error as NSError?
        guard let ns, ns.domain == "kAFAssistantErrorDomain" else { return false }
        return [203, 216, 1110].contains(ns.code)
    }

}
