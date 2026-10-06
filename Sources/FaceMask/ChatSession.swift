import AVFoundation
import AppKit
import Combine
import Foundation
import SwiftUI

struct SpokenReply {
    var emotion: FaceEmotion
    var speech: String
}

enum ReplyParser {
    static func parse(_ raw: String) -> SpokenReply {
        let stripped = stripThinking(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        let lines = stripped
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard let first = lines.first else {
            return SpokenReply(emotion: .calm, speech: "")
        }
        let pieces = first.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        if let emotion = FaceEmotion.parse(pieces[0]) {
            var speech = lines.dropFirst().joined(separator: " ")
            if pieces.count > 1 {
                speech = (pieces[1] + " " + speech).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return SpokenReply(emotion: emotion, speech: speech)
        }
        return SpokenReply(emotion: .calm, speech: stripped)
    }

    private static func stripThinking(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?s)<think>.*?</think>") else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

enum OllamaError: Error {
    case unreachable
    case timedOut
    case noModel
    case empty
    case server(String)
}

enum OllamaClient {
    private static let chatURL = URL(string: "http://127.0.0.1:11434/api/chat")!
    private static let tagsURL = URL(string: "http://127.0.0.1:11434/api/tags")!
    private static let preferred = ["qwen3:latest", "qwen2.5:14b", "qwen2.5:14b-ctx"]

    static let systemPrompt = """
    너는 얼굴이 있는 대화 상대다. 답은 항상 이 형식만 지킨다.
    첫 줄은 감정 단어 하나뿐이다. 다음 중 하나만 쓴다: calm, curious, surprised, skeptical, concerned
    그 다음 줄부터 할 말을 쓴다. 한두 문장, 짧게, 한국어로.
    첫 줄에는 감정 단어 외에 아무것도 쓰지 않는다.
    """

    static func resolveModel() async throws -> String {
        if let chosen = ProcessInfo.processInfo.environment["FACEMASK_MODEL"], !chosen.isEmpty {
            return chosen
        }
        let names = try await models()
        for name in preferred where names.contains(name) {
            return name
        }
        guard let first = names.first else { throw OllamaError.noModel }
        return first
    }

    static func complete(model: String, history: [OllamaMessage]) async throws -> String {
        var messages = [OllamaMessage(role: "system", content: systemPrompt)]
        messages.append(contentsOf: history)
        let body = ChatBody(
            model: model,
            messages: messages,
            stream: false,
            think: false,
            options: ChatBody.Options(temperature: 0.7, numPredict: 160)
        )
        var request = URLRequest(url: chatURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw OllamaError.timedOut
        } catch {
            throw OllamaError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw OllamaError.unreachable }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw OllamaError.server(detail)
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw OllamaError.empty }
        return content
    }

    private static func models() async throws -> [String] {
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: tagsURL)
        } catch {
            throw OllamaError.unreachable
        }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map(\.name)
    }
}

struct OllamaMessage: Codable {
    var role: String
    var content: String
}

private struct ChatBody: Encodable {
    struct Options: Encodable {
        var temperature: Double
        var numPredict: Int

        enum CodingKeys: String, CodingKey {
            case temperature
            case numPredict = "num_predict"
        }
    }

    var model: String
    var messages: [OllamaMessage]
    var stream: Bool
    var think: Bool
    var options: Options
}

private struct TagsResponse: Decodable {
    struct Model: Decodable { var name: String }
    var models: [Model]
}

private struct ChatResponse: Decodable {
    struct Message: Decodable {
        var content: String
    }

    var message: Message
}

final class ChatSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    let director: FaceDirector
    @Published var draft = ""
    @Published var note = ""
    @Published var busy = false

    var onModel: ((String) -> Void)?

    private let speech = AVSpeechSynthesizer()
    private var history: [OllamaMessage] = []
    private var model: String?
    private var turn = 0
    private var speakingTurn = 0

    init(director: FaceDirector) {
        self.director = director
        super.init()
        speech.delegate = self
    }

    func prepare() {
        Task { [weak self] in
            do {
                let name = try await OllamaClient.resolveModel()
                DispatchQueue.main.async {
                    self?.model = name
                    self?.onModel?(name)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.onModel?("Ollama 없음")
                }
            }
        }
    }

    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        draft = ""
        note = ""
        busy = true
        turn += 1
        let turn = self.turn
        speech.stopSpeaking(at: .immediate)
        director.setMode(.thinking)
        director.setEmotion(.curious)
        history.append(OllamaMessage(role: "user", content: text))
        let historySnapshot = history
        let knownModel = model

        Task { [weak self] in
            guard let self else { return }
            do {
                let model = try await self.currentModel(known: knownModel)
                let raw = try await OllamaClient.complete(model: model, history: historySnapshot)
                let reply = ReplyParser.parse(raw)
                DispatchQueue.main.async {
                    self.remember(model)
                    self.receive(reply, turn: turn)
                }
            } catch {
                DispatchQueue.main.async {
                    self.fail(error, turn: turn)
                }
            }
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.finishTurn(self.speakingTurn)
        }
    }

    private func currentModel(known: String?) async throws -> String {
        if let known { return known }
        return try await OllamaClient.resolveModel()
    }

    private func remember(_ name: String) {
        guard model != name else { return }
        model = name
        onModel?(name)
    }

    private func receive(_ reply: SpokenReply, turn: Int) {
        guard turn == self.turn else { return }
        let speech = reply.speech.trimmingCharacters(in: .whitespacesAndNewlines)
        history.append(OllamaMessage(role: "assistant", content: speech.isEmpty ? reply.emotion.title : speech))
        if history.count > 8 {
            history.removeFirst(history.count - 8)
        }
        director.setEmotion(reply.emotion)
        guard !speech.isEmpty else {
            director.setMode(.idle)
            scheduleIdle(turn, after: 1.6)
            return
        }
        director.setMode(.speaking)
        speakingTurn = turn
        busy = false
        let utterance = AVSpeechUtterance(string: speech)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        if speech.unicodeScalars.contains(where: { (0xAC00...0xD7A3).contains($0.value) }) {
            utterance.voice = AVSpeechSynthesisVoice(language: "ko-KR")
        }
        self.speech.speak(utterance)
        let estimate = min(40, Double(speech.count) * 0.28 + 1.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + estimate) { [weak self] in
            guard let self, self.turn == turn, self.director.mode == .speaking else { return }
            self.finishTurn(turn)
        }
    }

    private func fail(_ error: Error, turn: Int) {
        guard turn == self.turn else { return }
        if history.last?.role == "user" {
            history.removeLast()
        }
        note = Self.note(for: error)
        director.setMode(.idle)
        director.setEmotion(.concerned)
        busy = false
        scheduleIdle(turn, after: 2.4)
    }

    private func scheduleIdle(_ turn: Int, after seconds: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            self?.finishTurn(turn)
        }
    }

    private func finishTurn(_ turn: Int) {
        guard turn == self.turn else { return }
        director.setMode(.idle)
        director.setEmotion(nil)
        note = ""
        busy = false
    }

    private static func note(for error: Error) -> String {
        guard let error = error as? OllamaError else {
            return "답을 받지 못했습니다"
        }
        switch error {
        case .unreachable:
            return "Ollama가 실행 중이 아닙니다"
        case .timedOut:
            return "응답이 너무 오래 걸립니다"
        case .noModel:
            return "설치된 모델이 없습니다"
        case .empty:
            return "빈 응답이 왔습니다"
        case .server:
            return "모델 응답을 읽지 못했습니다"
        }
    }
}

struct LineField: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> EntryField {
        let field = EntryField(string: text)
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 13)
        field.textColor = .white
        field.appearance = NSAppearance(named: .darkAqua)
        field.placeholderAttributedString = NSAttributedString(
            string: "메시지",
            attributes: [
                .foregroundColor: NSColor.white.withAlphaComponent(0.55),
                .font: NSFont.systemFont(ofSize: 13)
            ]
        )
        field.delegate = context.coordinator
        field.target = context.coordinator
        field.action = #selector(Coordinator.submit(_:))
        field.cell?.sendsActionOnEndEditing = false
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        return field
    }

    func updateNSView(_ field: EntryField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        let becameEnabled = isEnabled && !field.isEnabled
        field.isEnabled = isEnabled
        if becameEnabled {
            field.restoreFocus()
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: LineField

        init(_ parent: LineField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        @objc func submit(_ sender: NSTextField) {
            parent.onSubmit()
        }
    }
}

final class EntryField: NSTextField {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        NSApp.activate()
        window?.makeKey()
        super.mouseDown(with: event)
    }

    func restoreFocus() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isEnabled, let window = self.window else { return }
            NSApp.activate()
            window.makeKey()
            window.makeFirstResponder(self)
        }
    }
}

struct FaceDragPad: NSViewRepresentable {
    var acceptsClick: Bool
    var onClick: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(acceptsClick: acceptsClick, onClick: onClick)
    }

    func makeNSView(context: Context) -> DragPadView {
        let view = DragPadView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ view: DragPadView, context: Context) {
        context.coordinator.acceptsClick = acceptsClick
        context.coordinator.onClick = onClick
        view.coordinator = context.coordinator
    }

    final class Coordinator {
        var acceptsClick: Bool
        var onClick: () -> Void

        init(acceptsClick: Bool, onClick: @escaping () -> Void) {
            self.acceptsClick = acceptsClick
            self.onClick = onClick
        }
    }
}

final class DragPadView: NSView {
    var coordinator: FaceDragPad.Coordinator?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let start = NSEvent.mouseLocation
        window?.performDrag(with: event)
        let end = NSEvent.mouseLocation
        guard hypot(end.x - start.x, end.y - start.y) < 3 else { return }
        guard coordinator?.acceptsClick == true else { return }
        coordinator?.onClick()
    }
}

final class FacePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
