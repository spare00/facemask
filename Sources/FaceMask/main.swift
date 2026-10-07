import AppKit
import SwiftUI

@main
enum FaceMaskMain {
    static func main() {
        UserDefaults.standard.set(false, forKey: "NSAutoFillHeuristicControllerEnabled")
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

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let director: FaceDirector
    private let chat: ChatSession
    private let looks: FaceLooks
    private let speechLanguages: SpeechLanguages
    private var panel: NSPanel?
    private var statusItem: NSStatusItem?
    private var modeItems: [FaceMode: NSMenuItem] = [:]
    private var emotionItems: [Int: NSMenuItem] = [:]
    private var lookItems: [FaceLook: NSMenuItem] = [:]
    private var speechItems: [SpeechLanguage: NSMenuItem] = [:]
    private var modelItem: NSMenuItem?
    private var visibilityItem: NSMenuItem?

    override init() {
        let director = FaceDirector()
        self.director = director
        chat = ChatSession(director: director)
        looks = FaceLooks()
        speechLanguages = SpeechLanguages()
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
        chat.useSpeechLanguage(speechLanguages.current)
        setupEditMenu()
        setupStatusItem()
        setupPanel()
        director.start()
        chat.prepare()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
        guard client is EntryField else { return nil }
        return EntryField.editor
    }

    private func setupEditMenu() {
        let main = NSMenu()
        let editItem = NSMenuItem()
        main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        edit.addItem(editCommand("Cut", #selector(NSText.cut(_:)), "x"))
        edit.addItem(editCommand("Copy", #selector(NSText.copy(_:)), "c"))
        edit.addItem(editCommand("Paste", #selector(NSText.paste(_:)), "v"))
        edit.addItem(editCommand("Select All", #selector(NSText.selectAll(_:)), "a"))
        NSApp.mainMenu = main
    }

    private func editCommand(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = [.command]
        return item
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
        let model = NSMenuItem(title: "Connecting model", action: nil, keyEquivalent: "")
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
        menu.addItem(lookMenuItem())
        menu.addItem(speechMenuItem())
        menu.addItem(.separator())
        let visibility = NSMenuItem(
            title: "Hide",
            action: #selector(toggleVisibility(_:)),
            keyEquivalent: ""
        )
        visibility.target = self
        visibilityItem = visibility
        menu.addItem(visibility)
        let quit = NSMenuItem(
            title: "Quit",
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
        panel.delegate = self

        let host = ClearHostingView(rootView: FaceScreen(director: director, chat: chat, looks: looks))
        host.toolTip = "Drag the face to move it. Type in the field below."
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

    @objc private func toggleVisibility(_ sender: NSMenuItem) {
        guard let panel else { return }
        if panel.isVisible {
            panel.orderOut(nil)
            sender.title = "Show"
            statusItem?.button?.toolTip = "FaceMask (hidden)"
        } else {
            panel.orderFrontRegardless()
            sender.title = "Hide"
            statusItem?.button?.toolTip = "FaceMask"
        }
    }

    private func emotionMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        let auto = emotionItem(title: "Auto", tag: -1, selected: director.emotion == nil)
        submenu.addItem(auto)
        submenu.addItem(.separator())
        for emotion in FaceEmotion.allCases {
            submenu.addItem(emotionItem(
                title: emotion.title,
                tag: emotion.rawValue,
                selected: director.emotion == emotion
            ))
        }
        let root = NSMenuItem(title: "Emotion", action: nil, keyEquivalent: "")
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

    private func lookMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for (index, look) in FaceLook.allCases.enumerated() {
            let item = NSMenuItem(
                title: look.title,
                action: #selector(selectLook(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = look == looks.current ? .on : .off
            lookItems[look] = item
            submenu.addItem(item)
        }
        let root = NSMenuItem(title: "Face", action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    private func speechMenuItem() -> NSMenuItem {
        let submenu = NSMenu()
        for (index, language) in SpeechLanguage.allCases.enumerated() {
            let item = NSMenuItem(
                title: language.title,
                action: #selector(selectSpeech(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.tag = index
            item.state = language == speechLanguages.current ? .on : .off
            speechItems[language] = item
            submenu.addItem(item)
        }
        let root = NSMenuItem(title: "Voice", action: nil, keyEquivalent: "")
        root.submenu = submenu
        return root
    }

    @objc private func selectSpeech(_ sender: NSMenuItem) {
        let cases = SpeechLanguage.allCases
        guard sender.tag >= 0, sender.tag < cases.count else { return }
        let language = cases[sender.tag]
        speechLanguages.select(language)
        chat.useSpeechLanguage(language)
        for (itemLanguage, item) in speechItems {
            item.state = itemLanguage == language ? .on : .off
        }
    }

    @objc private func selectLook(_ sender: NSMenuItem) {
        let cases = FaceLook.allCases
        guard sender.tag >= 0, sender.tag < cases.count else { return }
        let look = cases[sender.tag]
        looks.select(look)
        for (itemLook, item) in lookItems {
            item.state = itemLook == look ? .on : .off
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
            line.move(to: NSPoint(x: 1.2, y: 13.2))
            line.curve(to: NSPoint(x: 7.1, y: 12.4), controlPoint1: NSPoint(x: 3.0, y: 15.0), controlPoint2: NSPoint(x: 5.6, y: 14.7))
            line.move(to: NSPoint(x: 16.8, y: 13.2))
            line.curve(to: NSPoint(x: 10.9, y: 12.4), controlPoint1: NSPoint(x: 15.0, y: 15.0), controlPoint2: NSPoint(x: 12.4, y: 14.7))
            line.appendOval(in: NSRect(x: 1.0, y: 7.8, width: 6.6, height: 5.2))
            line.appendOval(in: NSRect(x: 10.4, y: 7.8, width: 6.6, height: 5.2))
            line.move(to: NSPoint(x: 6.0, y: 5.5))
            line.curve(
                to: NSPoint(x: 12.0, y: 5.5),
                controlPoint1: NSPoint(x: 7.4, y: 3.6),
                controlPoint2: NSPoint(x: 10.6, y: 3.6)
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
    @ObservedObject var looks: FaceLooks

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                FaceCanvas(pose: director.pose, look: looks.current)
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
                .help(chat.voiceSession ? "Stop voice input" : "Talk")

                LineField(
                    text: $chat.draft,
                    isEnabled: !chat.busy && !chat.listening,
                    restoresFocus: !chat.voiceSession
                ) {
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
