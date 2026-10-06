import AVFoundation
import Foundation
import Speech

final class SpeechListener {
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?
    private var stopped = true
    private var tapped = false
    private var session = 0
    private var taskGeneration = 0
    private var restarts = 0
    private var onText: ((String) -> Void)?
    private var onError: ((String) -> Void)?

    func start(onText: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        session += 1
        let session = session
        stopped = false
        restarts = 0
        self.onText = onText
        self.onError = onError
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                guard let self, session == self.session, !self.stopped else { return }
                guard status == .authorized else {
                    onError("음성 인식 권한이 없습니다. 시스템 설정에서 허용해 주세요.")
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { allowed in
                    DispatchQueue.main.async {
                        guard session == self.session, !self.stopped else { return }
                        guard allowed else {
                            onError("마이크 권한이 없습니다. 시스템 설정에서 허용해 주세요.")
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
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        engine.stop()
        if tapped {
            engine.inputNode.removeTap(onBus: 0)
            tapped = false
        }
    }

    private func begin() {
        guard let recognizer = Self.recognizer() else {
            onError?("이 맥에서 음성 인식을 사용할 수 없습니다.")
            return
        }
        self.recognizer = recognizer
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            onError?("마이크를 열 수 없습니다.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }
        tapped = true
        armTask()
        engine.prepare()
        do {
            try engine.start()
        } catch {
            stop()
            onError?("마이크를 열 수 없습니다.")
        }
    }

    private func armTask() {
        guard let recognizer, !stopped else { return }
        restarts += 1
        guard restarts <= 8 else {
            let report = onError
            stop()
            report?("음성을 알아듣지 못했습니다.")
            return
        }
        task?.cancel()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.addsPunctuation = true
        self.request = request
        taskGeneration += 1
        let generation = taskGeneration
        let session = session
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self, session == self.session, generation == self.taskGeneration, !self.stopped else { return }
                if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                    self.onText?(text)
                }
                guard error != nil else { return }
                if Self.isBenign(error) {
                    self.armTask()
                    return
                }
                let report = self.onError
                self.stop()
                report?("음성을 알아듣지 못했습니다.")
            }
        }
    }

    private static func isBenign(_ error: Error?) -> Bool {
        let ns = error as NSError?
        guard let ns, ns.domain == "kAFAssistantErrorDomain" else { return false }
        return [203, 216, 1110].contains(ns.code)
    }

    private static func recognizer() -> SFSpeechRecognizer? {
        let identifiers = ["ko-KR", Locale.current.identifier, "en-US"]
        for identifier in identifiers {
            guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: identifier)),
                  recognizer.isAvailable else { continue }
            return recognizer
        }
        return nil
    }
}
