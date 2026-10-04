import AppKit
import Foundation

@MainActor
final class ChooserWindowController: NSWindowController {
    let requestID = UUID()
    private let choose: @MainActor (ChooserWindowController, BrowserProfile) -> Void
    private let closed: @MainActor (ChooserWindowController) -> Void
    private var isLaunching = false

    init(url: URL, profiles: [BrowserProfile], issues: [String], choose: @escaping @MainActor (ChooserWindowController, BrowserProfile) -> Void,
         closed: @escaping @MainActor (ChooserWindowController) -> Void) {
        self.choose = choose
        self.closed = closed
        let window = ChooserPanel(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.title = "Choose a browser"
        super.init(window: window)
        window.delegate = self
        window.contentViewController = ChooserView(url: url, profiles: profiles, issues: issues) { [weak self] profile in
            guard let self else { return }
            self.choose(self, profile)
        }
        window.setContentSize(ChooserView.contentSize(for: profiles.count))
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main ?? NSScreen.screens.first {
            window.setFrame(ChooserPlacement.frame(for: window.frame.size, near: pointer, in: screen.visibleFrame), display: false)
        }
    }

    required init?(coder: NSCoder) { nil }

    func beginLaunch() -> Bool {
        guard !isLaunching else { return false }
        isLaunching = true
        return true
    }

    func finishLaunch() { isLaunching = false }
}

private final class ChooserPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing bufferingType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: bufferingType, defer: flag)
        isFloatingPanel = true
        level = .floating
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
    }
}

enum ChooserPlacement {
    static func frame(for size: NSSize, near pointer: NSPoint, in visibleFrame: NSRect) -> NSRect {
        let margin: CGFloat = 12
        let width = min(size.width, max(0, visibleFrame.width - 2 * margin))
        let height = min(size.height, max(0, visibleFrame.height - 2 * margin))
        let right = pointer.x + margin
        let left = pointer.x - margin - width
        let below = pointer.y - margin - height
        let above = pointer.y + margin
        let x = right + width <= visibleFrame.maxX - margin ? right : left
        let y = below >= visibleFrame.minY + margin ? below : above
        return NSRect(
            x: min(max(x, visibleFrame.minX + margin), visibleFrame.maxX - margin - width),
            y: min(max(y, visibleFrame.minY + margin), visibleFrame.maxY - margin - height),
            width: width, height: height
        )
    }
}

extension ChooserWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { closed(self) }

    func windowDidResignKey(_ notification: Notification) {
        if !isLaunching, window?.attachedSheet == nil { close() }
    }
}

@MainActor
final class ChooserView: NSViewController {
    static let width: CGFloat = 296
    static let rowHeight: CGFloat = 32
    static let footerHeight: CGFloat = 29
    static let listPadding: CGFloat = 12

    static func contentSize(for profileCount: Int) -> NSSize {
        NSSize(width: width, height: CGFloat(min(profileCount, 7)) * rowHeight + listPadding + footerHeight)
    }

    private let profiles: [BrowserProfile]
    private let choose: @MainActor (BrowserProfile) -> Void
    private var keyMonitor: Any?
    private var rows: [ChooserRowButton] = []

    init(url: URL, profiles: [BrowserProfile], issues: [String], choose: @escaping @MainActor (BrowserProfile) -> Void) {
        self.profiles = profiles
        self.choose = choose
        super.init(nibName: nil, bundle: nil)

        let background = NSView()
        background.wantsLayer = true
        background.layer?.cornerRadius = 13
        background.layer?.masksToBounds = true
        background.layer?.backgroundColor = NSColor(calibratedWhite: 0.16, alpha: 0.98).cgColor
        view = background

        let list = FlippedStackView()
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 0
        list.edgeInsets = NSEdgeInsets(top: 6, left: 7, bottom: 6, right: 7)
        list.translatesAutoresizingMaskIntoConstraints = false
        for (index, profile) in profiles.enumerated() {
            let row = ChooserRowButton(profile: profile, shortcut: index < 9 ? index + 1 : nil)
            row.tag = index
            row.target = self
            row.action = #selector(selectProfile(_:))
            row.isSelectedRow = index == 0
            row.onHover = { [weak self, weak row] in
                guard let self, let row else { return }
                for item in self.rows { item.isSelectedRow = item === row }
            }
            list.addArrangedSubview(row)
            row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true
            row.widthAnchor.constraint(equalTo: list.widthAnchor, constant: -14).isActive = true
            rows.append(row)
        }

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = profiles.count > 7
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = list
        background.addSubview(scroll)

        let divider = NSView()
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor(calibratedWhite: 1, alpha: 0.10).cgColor
        divider.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(divider)

        let host = NSTextField(labelWithString: URLRouter.hostLabel(for: url))
        host.font = .systemFont(ofSize: 11, weight: .medium)
        host.textColor = NSColor(calibratedWhite: 0.66, alpha: 1)
        host.alignment = .center
        host.lineBreakMode = .byTruncatingMiddle
        host.toolTip = ([url.absoluteString] + issues).joined(separator: "\n")
        host.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(host)

        if !issues.isEmpty {
            let warning = NSTextField(labelWithString: "⚠")
            warning.font = .systemFont(ofSize: 11)
            warning.textColor = .systemYellow
            warning.toolTip = issues.joined(separator: "\n")
            warning.translatesAutoresizingMaskIntoConstraints = false
            background.addSubview(warning)
            NSLayoutConstraint.activate([
                warning.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 12),
                warning.centerYAnchor.constraint(equalTo: host.centerYAnchor)
            ])
        }

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: background.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: divider.topAnchor),
            list.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            divider.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 7),
            divider.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -7),
            divider.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.footerHeight),
            divider.heightAnchor.constraint(equalToConstant: 1),
            host.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 30),
            host.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -30),
            host.centerYAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.footerHeight / 2)
        ])
    }

    required init?(coder: NSCoder) { nil }

    override func viewDidAppear() {
        super.viewDidAppear()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            guard self.view.window === NSApp.keyWindow, self.view.window?.attachedSheet == nil else { return event }
            if event.keyCode == 53 { self.view.window?.close(); return nil }
            if let text = event.characters, let number = Int(text), (1...min(9, self.profiles.count)).contains(number) {
                self.choose(self.profiles[number - 1]); return nil
            }
            return event
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    @objc private func selectProfile(_ sender: NSButton) { choose(profiles[sender.tag]) }
}

private final class FlippedStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
private final class ChooserRowButton: NSButton {
    var isSelectedRow = false { didSet { updateBackground() } }
    var onHover: (() -> Void)?

    init(profile: BrowserProfile, shortcut: Int?) {
        super.init(frame: .zero)
        title = ""
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 8
        toolTip = profile.displayName
        setAccessibilityLabel(profile.displayName)
        translatesAutoresizingMaskIntoConstraints = false

        let number = NSTextField(labelWithString: shortcut.map { "\($0)." } ?? "")
        number.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        number.textColor = NSColor(calibratedWhite: 0.78, alpha: 1)
        number.alignment = .left
        number.identifier = NSUserInterfaceItemIdentifier("shortcut")
        number.translatesAutoresizingMaskIntoConstraints = false
        addSubview(number)

        let browser = NSTextField(labelWithString: profile.browser.displayName)
        browser.font = .systemFont(ofSize: 13, weight: .medium)
        browser.textColor = .white
        browser.alignment = .left
        browser.identifier = NSUserInterfaceItemIdentifier("browser")
        browser.translatesAutoresizingMaskIntoConstraints = false
        addSubview(browser)

        let profileName = NSTextField(labelWithString: profile.browser == .safari ? "" : profile.menuName)
        profileName.font = .systemFont(ofSize: 13, weight: .medium)
        profileName.textColor = .white
        profileName.alignment = .left
        profileName.lineBreakMode = .byTruncatingTail
        profileName.identifier = NSUserInterfaceItemIdentifier("profile")
        profileName.translatesAutoresizingMaskIntoConstraints = false
        addSubview(profileName)

        let icon = NSImageView()
        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.browser.bundleIdentifier) {
            icon.image = NSWorkspace.shared.icon(forFile: appURL.path)
        }
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        addSubview(icon)

        NSLayoutConstraint.activate([
            number.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            number.centerYAnchor.constraint(equalTo: centerYAnchor),
            number.widthAnchor.constraint(equalToConstant: 20),
            browser.leadingAnchor.constraint(equalTo: number.trailingAnchor, constant: 3),
            browser.centerYAnchor.constraint(equalTo: centerYAnchor),
            browser.widthAnchor.constraint(equalToConstant: 59),
            profileName.leadingAnchor.constraint(equalTo: browser.trailingAnchor, constant: 9),
            profileName.trailingAnchor.constraint(equalTo: icon.leadingAnchor, constant: -7),
            profileName.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -13),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 20),
            icon.heightAnchor.constraint(equalToConstant: 20)
        ])
        updateBackground()
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { onHover?() }

    private func updateBackground() {
        layer?.backgroundColor = isSelectedRow ? NSColor(calibratedRed: 0.12, green: 0.35, blue: 0.83, alpha: 1).cgColor : NSColor.clear.cgColor
    }
}
