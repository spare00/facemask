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
    private struct Payload: Decodable {
        var emotion: String
        var speech: String
    }

    static func parse(_ raw: String) -> SpokenReply {
        let stripped = stripThinking(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        if let payload = payload(in: stripped) {
            let emotion = FaceEmotion.parse(payload.emotion) ?? .calm
            return SpokenReply(emotion: emotion, speech: spoken(payload.speech))
        }
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
            return SpokenReply(emotion: emotion, speech: spoken(speech))
        }
        return SpokenReply(emotion: .calm, speech: spoken(stripped))
    }

    private static func payload(in text: String) -> Payload? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    private static func spoken(_ text: String) -> String {
        var value = stripNotes(text)
        if let regex = try? NSRegularExpression(pattern: "(?s)```.*?```") {
            let range = NSRange(value.startIndex..., in: value)
            value = regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        }
        let lines = value.split(whereSeparator: \.isNewline).filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("|") { return false }
            if trimmed.hasPrefix("```") { return false }
            if trimmed.hasPrefix("![") { return false }
            return true
        }
        return lines.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripNotes(_ text: String) -> String {
        var value = text
        let patterns = [
            #"\[[^\]]*\]\([^)]*\)"#,
            #"https?://\S+"#,
            #"【[^】]*】"#,
            #"\([^)]{0,40}https?://[^)]*\)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..., in: value)
            value = regex.stringByReplacingMatches(in: value, range: range, withTemplate: "")
        }
        return value
    }

    private static func stripThinking(_ text: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "(?s)<think>.*?</think>") else {
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }
}

enum ChatError: Error {
    case ollamaDown
    case apiDown
    case timedOut
    case noModel
    case empty
    case unauthorized
    case missingAPIKey
    case missingModelName
    case server(String)
}

enum AppEnv {
    static func string(_ key: String) -> String? {
        if let live = cleaned(ProcessInfo.processInfo.environment[key]) {
            return live
        }
        return cleaned(fileValues[key])
    }

    private static let fileValues: [String: String] = loadFile()

    private static func cleaned(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func loadFile() -> [String: String] {
        guard let url = findFile(),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return [:]
        }
        var values: [String: String] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine).trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("export ") {
                line.removeFirst("export ".count)
                line = line.trimmingCharacters(in: .whitespaces)
            }
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = parseValue(String(line[line.index(after: eq)...]))
            if !key.isEmpty {
                values[key] = value
            }
        }
        return values
    }

    private static func parseValue(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
            value.removeFirst()
            value.removeLast()
            return value
        }
        if let hash = value.range(of: " #") {
            value = String(value[..<hash.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespaces)
    }

    private static func findFile() -> URL? {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        if let found = walk(cwd) { return found }
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        return walk(executable.deletingLastPathComponent())
    }

    private static func walk(_ directory: URL) -> URL? {
        var dir = directory.standardizedFileURL
        for _ in 0..<10 {
            let candidate = dir.appendingPathComponent(".env")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { return nil }
            dir = parent
        }
        return nil
    }
}

enum ChatBackend: Equatable {
    case ollama(model: String)
    case api(endpoint: URL, apiKey: String, model: String)

    var label: String {
        switch self {
        case .ollama(let model), .api(_, _, let model):
            return model
        }
    }

    static func resolve() async throws -> ChatBackend {
        if let api = try configuredAPI() {
            return api
        }
        let model = try await OllamaClient.resolveModel()
        return .ollama(model: model)
    }

    func complete(history: [OllamaMessage]) async throws -> String {
        switch self {
        case .ollama(let model):
            return try await OllamaClient.complete(model: model, history: history)
        case .api(let endpoint, let apiKey, let model):
            return try await APIClient.complete(
                endpoint: endpoint,
                apiKey: apiKey,
                model: model,
                history: history
            )
        }
    }

    private static func configuredAPI() throws -> ChatBackend? {
        let key = AppEnv.string("AI_API_KEY")
        let model = AppEnv.string("AI_MODEL")
        let base = AppEnv.string("AI_BASE_URL")
        if key == nil, model == nil, base == nil {
            return nil
        }
        guard let key else { throw ChatError.missingAPIKey }
        guard let model else { throw ChatError.missingModelName }
        guard let endpoint = chatURL(base ?? "https://api.openai.com/v1") else {
            throw ChatError.server("The API address is not valid")
        }
        return .api(endpoint: endpoint, apiKey: key, model: model)
    }

    private static func chatURL(_ base: String) -> URL? {
        var root = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while root.hasSuffix("/") {
            root.removeLast()
        }
        if root.hasSuffix("/chat/completions") {
            return URL(string: root)
        }
        return URL(string: root + "/chat/completions")
    }
}

enum OllamaClient {
    private static let chatURL = URL(string: "http://127.0.0.1:11434/api/chat")!
    private static let tagsURL = URL(string: "http://127.0.0.1:11434/api/tags")!
    private static let preferred = ["qwen3:latest", "qwen2.5:14b", "qwen2.5:14b-ctx"]

    static let systemPrompt = """
    You are a face the user talks to. Always answer in this format only.
    The first line is one emotion word and nothing else. Use only one of: calm, curious, surprised, skeptical, concerned
    From the next line, write what you will say. One or two short sentences, in English.
    Do not put anything except the emotion word on the first line.
    """

    static func resolveModel() async throws -> String {
        if let chosen = ProcessInfo.processInfo.environment["FACEMASK_MODEL"], !chosen.isEmpty {
            return chosen
        }
        let names = try await models()
        for name in preferred where names.contains(name) {
            return name
        }
        guard let first = names.first else { throw ChatError.noModel }
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
            throw ChatError.timedOut
        } catch {
            throw ChatError.ollamaDown
        }
        guard let http = response as? HTTPURLResponse else { throw ChatError.ollamaDown }
        guard http.statusCode == 200 else {
            throw ChatError.server("Could not read the model response")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let content = decoded.message.content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { throw ChatError.empty }
        return content
    }

    private static func models() async throws -> [String] {
        let data: Data
        do {
            (data, _) = try await URLSession.shared.data(from: tagsURL)
        } catch {
            throw ChatError.ollamaDown
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

private enum APIClient {
    static func complete(
        endpoint: URL,
        apiKey: String,
        model: String,
        history: [OllamaMessage]
    ) async throws -> String {
        var messages = [OllamaMessage(role: "system", content: OllamaClient.systemPrompt)]
        messages.append(contentsOf: history)
        if canSearch(model), let responses = responsesURL(from: endpoint) {
            return try await searchedReply(
                endpoint: responses,
                apiKey: apiKey,
                model: model,
                history: history
            )
        }
        let body = APIChatBody.make(model: model, messages: messages)
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ChatError.timedOut
        } catch {
            throw ChatError.apiDown
        }
        guard let http = response as? HTTPURLResponse else { throw ChatError.apiDown }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ChatError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw ChatError.server(APIClient.message(from: data, hiding: apiKey))
        }
        let decoded = try JSONDecoder().decode(APIChatResponse.self, from: data)
        let content = decoded.choices.first?.message.content?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !content.isEmpty else { throw ChatError.empty }
        return content
    }

    private static func searchedReply(
        endpoint: URL,
        apiKey: String,
        model: String,
        history: [OllamaMessage]
    ) async throws -> String {
        let body = ResponsesBody(
            model: model,
            instructions: """
            You are a face the user talks to. Reply in English. Put only the words you will speak into speech.
            speech is plain text made of finished sentences. Do not include code, charts, tables, lists, headings, URLs, or markdown.
            emotion is one of calm, curious, surprised, skeptical, concerned.
            Search the web when the question needs current facts, news, weather, or prices.
            Do not search for ordinary conversation you already know.
            Use search results only to decide what to say. Leave only the spoken reply in speech.
            """,
            input: history,
            tools: [ResponsesBody.Tool()],
            reasoning: ResponsesBody.Reasoning(effort: "none"),
            maxOutputTokens: 800,
            text: ResponsesBody.TextOutput()
        )
        let data = try await send(body, to: endpoint, apiKey: apiKey, timeout: 90)
        let decoded = try JSONDecoder().decode(ResponsesResult.self, from: data)
        let text = (decoded.output ?? [])
            .filter { $0.type == "message" }
            .flatMap { $0.content ?? [] }
            .compactMap(\.text)
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ChatError.empty }
        return text
    }

    private static func send(_ body: some Encodable, to endpoint: URL, apiKey: String, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw ChatError.timedOut
        } catch {
            throw ChatError.apiDown
        }
        guard let http = response as? HTTPURLResponse else { throw ChatError.apiDown }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw ChatError.unauthorized
        }
        guard http.statusCode == 200 else {
            throw ChatError.server(message(from: data, hiding: apiKey))
        }
        return data
    }

    private static func canSearch(_ model: String) -> Bool {
        let name = model.lowercased()
        if name.contains("search-api") { return false }
        return name.contains("gpt-5") || name.contains("gpt-6")
    }

    private static func responsesURL(from chatEndpoint: URL) -> URL? {
        let text = chatEndpoint.absoluteString
        let suffix = "/chat/completions"
        guard text.hasSuffix(suffix) else { return nil }
        return URL(string: String(text.dropLast(suffix.count)) + "/responses")
    }

    private static func message(from data: Data, hiding secret: String) -> String {
        let decoded = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error?.message
        let text = (decoded ?? String(data: data, encoding: .utf8) ?? "")
            .replacingOccurrences(of: secret, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return "Could not read the model response" }
        return String(text.prefix(90))
    }
}

private struct APIChatBody: Encodable {
    var model: String
    var messages: [OllamaMessage]
    var temperature: Double?
    var maxTokens: Int?
    var maxCompletionTokens: Int?
    var reasoningEffort: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case maxCompletionTokens = "max_completion_tokens"
        case reasoningEffort = "reasoning_effort"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(maxCompletionTokens, forKey: .maxCompletionTokens)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
    }

    static func make(model: String, messages: [OllamaMessage]) -> APIChatBody {
        if usesFixedSampling(model) {
            return APIChatBody(
                model: model,
                messages: messages,
                temperature: nil,
                maxTokens: nil,
                maxCompletionTokens: 400,
                reasoningEffort: "none"
            )
        }
        return APIChatBody(
            model: model,
            messages: messages,
            temperature: 0.7,
            maxTokens: 400,
            maxCompletionTokens: nil,
            reasoningEffort: nil
        )
    }

    private static func usesFixedSampling(_ model: String) -> Bool {
        let name = model.lowercased()
        return name.contains("gpt-5") || name.contains("gpt-6")
            || name.contains("o1") || name.contains("o3") || name.contains("o4")
    }
}

private struct ResponsesBody: Encodable {
    struct Tool: Encodable {
        var type = "web_search"
        var searchContextSize = "low"

        enum CodingKeys: String, CodingKey {
            case type
            case searchContextSize = "search_context_size"
        }
    }

    struct Reasoning: Encodable {
        var effort: String
    }

    struct TextOutput: Encodable {
        var format = SpokenFormat()
    }

    struct SpokenFormat: Encodable {
        var type = "json_schema"
        var name = "spoken_reply"
        var strict = true
        var schema = SpokenJSONSchema()
    }

    struct SpokenJSONSchema: Encodable {
        var type = "object"
        var additionalProperties = false
        var properties = Properties()
        var required = ["emotion", "speech"]

        struct Properties: Encodable {
            var emotion = EmotionField()
            var speech = SpeechField()
        }

        struct EmotionField: Encodable {
            var type = "string"
            var choices = ["calm", "curious", "surprised", "skeptical", "concerned"]

            enum CodingKeys: String, CodingKey {
                case type
                case choices = "enum"
            }
        }

        struct SpeechField: Encodable {
            var type = "string"
            var description = "The words to speak aloud, in English. Plain text of finished sentences. Do not include code, charts, tables, lists, URLs, or markdown."
        }
    }

    var model: String
    var instructions: String
    var input: [OllamaMessage]
    var tools: [Tool]
    var reasoning: Reasoning
    var maxOutputTokens: Int
    var text = TextOutput()

    enum CodingKeys: String, CodingKey {
        case model
        case instructions
        case input
        case tools
        case reasoning
        case maxOutputTokens = "max_output_tokens"
        case text
    }
}

private struct ResponsesResult: Decodable {
    struct Item: Decodable {
        struct Part: Decodable {
            var text: String?
        }

        var type: String?
        var content: [Part]?
    }

    var output: [Item]?
}

private struct APIChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            var content: String?
        }

        var message: Message
    }

    var choices: [Choice]
}

private struct APIErrorBody: Decodable {
    struct Detail: Decodable {
        var message: String?
    }

    var error: Detail?
}

final class ChatSession: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    let director: FaceDirector
    @Published var draft = ""
    @Published var note = ""
    @Published var busy = false
    @Published var listening = false
    @Published var voiceSession = false

    var onModel: ((String) -> Void)?

    private let speech = AVSpeechSynthesizer()
    private let listener = SpeechListener()
    private var history: [OllamaMessage] = []
    private var backend: ChatBackend?
    private var turn = 0
    private var speakingTurn = 0
    private var silence: DispatchWorkItem?
    private var listenDeadline: DispatchWorkItem?

    init(director: FaceDirector) {
        self.director = director
        super.init()
        speech.delegate = self
    }

    func prepare() {
        Task { [weak self] in
            do {
                let backend = try await ChatBackend.resolve()
                DispatchQueue.main.async {
                    self?.backend = backend
                    self?.onModel?(backend.label)
                }
            } catch {
                DispatchQueue.main.async {
                    self?.onModel?(ChatSession.note(for: error))
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
        stopListening()
        speech.stopSpeaking(at: .immediate)
        director.setMode(.thinking)
        director.setEmotion(.curious)
        history.append(OllamaMessage(role: "user", content: text))
        let historySnapshot = history
        let knownBackend = backend

        Task { [weak self] in
            guard let self else { return }
            do {
                let backend = try await self.currentBackend(known: knownBackend)
                let raw = try await backend.complete(history: historySnapshot)
                let reply = ReplyParser.parse(raw)
                DispatchQueue.main.async {
                    self.remember(backend)
                    self.receive(reply, turn: turn)
                }
            } catch {
                DispatchQueue.main.async {
                    self.fail(error, turn: turn)
                }
            }
        }
    }

    func toggleListen() {
        if voiceSession {
            endVoiceSession()
        } else {
            voiceSession = true
            startListen()
        }
    }

    private func startListen() {
        guard voiceSession, !busy, !listening else { return }
        listening = true
        note = "Listening"
        draft = ""
        speech.stopSpeaking(at: .immediate)
        director.setMode(.idle)
        director.setEmotion(.curious)
        armListenDeadline()
        listener.start { [weak self] text in
            guard let self, self.listening else { return }
            self.draft = text
            self.listenDeadline?.cancel()
            self.armSilence()
        } onError: { [weak self] message in
            guard let self, self.listening else { return }
            if self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.endVoiceSession()
                self.note = message
                self.scheduleClearNote()
            } else {
                self.finishListen(send: true)
            }
        }
    }

    private func finishListen(send shouldSend: Bool) {
        guard listening else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        stopListening()
        guard shouldSend, !text.isEmpty else {
            voiceSession = false
            draft = ""
            note = ""
            director.setMode(.idle)
            director.setEmotion(nil)
            return
        }
        draft = text
        send()
    }

    private func endVoiceSession() {
        voiceSession = false
        let wasListening = listening
        stopListening()
        guard wasListening else { return }
        draft = ""
        note = ""
        director.setMode(.idle)
        director.setEmotion(nil)
    }

    private func stopListening() {
        listening = false
        silence?.cancel()
        listenDeadline?.cancel()
        listener.stop()
    }

    private func armSilence() {
        silence?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.finishListen(send: true)
        }
        silence = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    private func armListenDeadline() {
        listenDeadline?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.listening else { return }
            if self.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.endVoiceSession()
                self.note = "Voice input ended"
                self.scheduleClearNote()
                return
            }
            self.finishListen(send: true)
        }
        listenDeadline = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
    }

    private func scheduleClearNote() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            guard let self, !self.listening, !self.busy else { return }
            self.note = ""
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.finishTurn(self.speakingTurn)
        }
    }

    private func currentBackend(known: ChatBackend?) async throws -> ChatBackend {
        if let known { return known }
        return try await ChatBackend.resolve()
    }

    private func remember(_ backend: ChatBackend) {
        guard self.backend != backend else { return }
        self.backend = backend
        onModel?(backend.label)
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
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
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
        if listening {
            busy = false
            return
        }
        if speech.isSpeaking {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.finishTurn(turn)
            }
            return
        }
        busy = false
        director.setMode(.idle)
        director.setEmotion(nil)
        note = ""
        guard voiceSession else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.voiceSession, self.turn == turn, !self.busy, !self.listening else { return }
            self.startListen()
        }
    }

    private static func note(for error: Error) -> String {
        guard let error = error as? ChatError else {
            return "No reply came back"
        }
        switch error {
        case .ollamaDown:
            return "Ollama is not running"
        case .apiDown:
            return "Could not reach the API"
        case .timedOut:
            return "The response took too long"
        case .noModel:
            return "No model is installed"
        case .empty:
            return "The response was empty"
        case .unauthorized:
            return "The API key is not valid"
        case .missingAPIKey:
            return "AI_API_KEY is missing"
        case .missingModelName:
            return "AI_MODEL is missing"
        case .server(let detail):
            return detail
        }
    }
}

struct LineField: NSViewRepresentable {
    @Binding var text: String
    var isEnabled: Bool
    var restoresFocus: Bool
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
            string: "Message",
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
        field.isAutomaticTextCompletionEnabled = false
        if #available(macOS 15.2, *) {
            field.allowsWritingTools = false
        }
        return field
    }

    func updateNSView(_ field: EntryField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text {
            field.stringValue = text
        }
        if !isEnabled && field.isEnabled {
            field.returnFocusWhenEnabled = restoresFocus && field.window?.isKeyWindow == true
        }
        let becameEnabled = isEnabled && !field.isEnabled
        field.isEnabled = isEnabled
        if becameEnabled {
            let shouldRestore = restoresFocus && field.returnFocusWhenEnabled
            field.returnFocusWhenEnabled = false
            if shouldRestore {
                field.restoreFocus()
            }
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

final class EntryEditor: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isPaste(event) {
            paste(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if Self.isPaste(event) {
            paste(nil)
            return
        }
        super.keyDown(with: event)
    }

    private static func isPaste(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown,
              event.charactersIgnoringModifiers?.lowercased() == "v" else { return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return flags == .command || flags == .control
    }
}

final class EntryField: NSTextField {
    static let editor: EntryEditor = {
        let editor = EntryEditor()
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.importsGraphics = false
        return editor
    }()

    var returnFocusWhenEnabled = false

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
