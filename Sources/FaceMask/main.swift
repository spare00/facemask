import AppKit
import SwiftUI

@main
enum FaceMaskMain {
    static func main() {
        if CommandLine.arguments.contains("--snapshot") {
            let path = snapshotPath()
            _ = NSApplication.shared
            MainActor.assumeIsolated {
                do {
                    try FaceSnapshot.write(to: URL(fileURLWithPath: path))
                    print(path)
                } catch {
                    fputs("\(error)\n", stderr)
                    Foundation.exit(1)
                }
            }
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private static func snapshotPath() -> String {
        let args = CommandLine.arguments
        guard let flag = args.firstIndex(of: "--snapshot"),
              flag + 1 < args.count,
              !args[flag + 1].hasPrefix("-")
        else {
            return ".preview/face.png"
        }
        return args[flag + 1]
    }
}

@MainActor
enum FaceSnapshot {
    static func write(to url: URL) throws {
        let renderer = ImageRenderer(content: FacePreview())
        renderer.scale = 2
        guard let image = renderer.cgImage else {
            throw CocoaError(.coderReadCorrupt)
        }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw CocoaError(.coderReadCorrupt)
        }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let director: FaceDirector
    private let chat: ChatSession
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var modeItems: [FaceMode: NSMenuItem] = [:]
    private var emotionItems: [Int: NSMenuItem] = [:]
    private var modelItem: NSMenuItem?

    override init() {
        let director = FaceDirector()
        self.director = director
        chat = ChatSession(director: director)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        director.onModeChange = { [weak self] mode in
            self?.syncChecks(mode)
        }
        director.onEmotionChange = { [weak self] emotion in
            self?.syncEmotion(emotion)
        }
        chat.onModel = { [weak self] name in
            self?.modelItem?.title = name
        }
        setupStatusItem()
        setupPanel()
        director.start()
        chat.prepare()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = statusImage()
        item.button?.image?.isTemplate = true
        item.button?.toolTip = "FaceMask"

        let menu = NSMenu()
        let title = NSMenuItem(title: "FaceMask", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        let model = NSMenuItem(title: "모델 연결 중", action: nil, keyEquivalent: "")
        model.isEnabled = false
        modelItem = model
        menu.addItem(model)
        menu.addItem(.separator())

        for mode in FaceMode.allCases {
            let entry = NSMenuItem(
                title: mode.title,
                action: #selector(selectMode(_:)),
                keyEquivalent: ""
            )
            entry.target = self
            entry.tag = mode.rawValue
            entry.state = mode == director.mode ? .on : .off
            modeItems[mode] = entry
            menu.addItem(entry)
        }

        menu.addItem(.separator())
        menu.addItem(emotionMenuItem())
        menu.addItem(.separator())
        let quit = NSMenuItem(
            title: "종료",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quit.target = NSApp
        menu.addItem(quit)

        item.menu = menu
        statusItem = item
    }

    private func setupPanel() {
        let size = FaceLayout.window
        let panel = FacePanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isRestorable = false
        panel.title = "FaceMask"

        let host = ClearHostingView(rootView: FaceScreen(director: director, chat: chat))
        host.toolTip = "얼굴은 드래그해서 옮기기 · 아래 칸에 메시지"
        host.sizingOptions = [.intrinsicContentSize]
        host.frame = NSRect(origin: .zero, size: size)
        host.autoresizingMask = [.width, .height]

        let container = NSView(frame: NSRect(origin: .zero, size: size))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(host)
        panel.contentView = container
        panel.setContentSize(size)

        if let screen = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(
                x: screen.maxX - size.width - 40,
                y: screen.maxY - size.height - 28
            ))
        } else {
            panel.center()
        }

        panel.orderFrontRegardless()
        self.panel = panel
    }

    private func emotionMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let auto = emotionItem(title: "자동", tag: -1, selected: director.emotion == nil)
        submenu.addItem(auto)
        submenu.addItem(.separator())
        for emotion in FaceEmotion.allCases {
            submenu.addItem(emotionItem(
                title: emotion.title,
                tag: emotion.rawValue,
                selected: director.emotion == emotion
            ))
        }
        let root = NSMenuItem(title: "감정", action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    private func emotionItem(title: String, tag: Int, selected: Bool) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: #selector(selectEmotion(_:)),
            keyEquivalent: ""
        )
        item.target = self
        item.tag = tag
        item.state = selected ? .on : .off
        emotionItems[tag] = item
        return item
    }

    private func syncEmotion(_ emotion: FaceEmotion?) {
        let selected = emotion?.rawValue ?? -1
        for (tag, item) in emotionItems {
            item.state = tag == selected ? .on : .off
        }
    }

    @objc private func selectEmotion(_ sender: NSMenuItem) {
        if sender.tag < 0 {
            director.setEmotion(nil)
        } else if let emotion = FaceEmotion(rawValue: sender.tag) {
            director.setEmotion(emotion)
        }
    }

    private func syncChecks(_ mode: FaceMode) {
        for (itemMode, item) in modeItems {
            item.state = itemMode == mode ? .on : .off
        }
    }

    @objc private func selectMode(_ sender: NSMenuItem) {
        guard let mode = FaceMode(rawValue: sender.tag) else { return }
        director.setMode(mode)
    }

    private func statusImage() -> NSImage {
        let side: CGFloat = 18
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            NSColor.black.setStroke()
            let line = NSBezierPath()
            line.lineWidth = 1.35
            line.lineCapStyle = .round
            line.lineJoinStyle = .round
            line.appendOval(in: NSRect(x: 1.6, y: 8.2, width: 5.4, height: 4.2))
            line.appendOval(in: NSRect(x: 11.0, y: 8.2, width: 5.4, height: 4.2))
            line.move(to: NSPoint(x: 4.2, y: 5.4))
            line.curve(
                to: NSPoint(x: 13.8, y: 5.4),
                controlPoint1: NSPoint(x: 6.4, y: 2.2),
                controlPoint2: NSPoint(x: 11.6, y: 2.2)
            )
            line.stroke()
            return true
        }
    }
}

final class ClearHostingView<Content: View>: NSHostingView<Content> {
    override var isOpaque: Bool { false }
}

struct FaceScreen: View {
    @ObservedObject var director: FaceDirector
    @ObservedObject var chat: ChatSession

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                FaceCanvas(pose: director.pose)
                FaceDragPad(acceptsClick: !chat.busy && !chat.listening) {
                    director.cycle()
                }
                .frame(width: FaceLayout.width, height: FaceLayout.height)
                if !chat.note.isEmpty {
                    Text(chat.note)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color.black.opacity(0.62))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: FaceLayout.width, height: FaceLayout.height)

            HStack(spacing: 6) {
                Button {
                    chat.toggleListen()
                } label: {
                    Image(systemName: chat.voiceSession ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .disabled(chat.busy && !chat.voiceSession)
                .help(chat.voiceSession ? "음성 입력을 끝낸다" : "말로 대화")

                LineField(text: $chat.draft, isEnabled: !chat.busy && !chat.listening) {
                    chat.send()
                }
                .frame(height: 20)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.62))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .frame(width: FaceLayout.window.width, height: FaceLayout.window.height)
    }
}
