import AppKit
import Foundation

@main
struct BrowserChooserMain {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var pendingURLs = URLQueue()
    private var chooserController: ChooserWindowController?
    private var entryController: URLEntryWindowController?
    private var launchGate = LaunchRequestGate()

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = URLRouter.validatedWebURL(from: CommandLine.arguments) {
            enqueue(url)
        } else {
            DispatchQueue.main.async { [weak self] in self?.presentEntryIfNeeded() }
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where URLRouter.validatedWebURL(from: ["BrowserChooser", url.absoluteString]) != nil { enqueue(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func enqueue(_ url: URL?) {
        guard let url else { return }
        pendingURLs.enqueue(url)
        if let entryController { entryController.close() }
        else { presentNextIfNeeded() }
    }

    private func presentEntryIfNeeded() {
        guard entryController == nil, chooserController == nil, pendingURLs.isEmpty else { return }
        let controller = URLEntryWindowController(
            submit: { [weak self] url in self?.enqueue(url) },
            closed: { [weak self] controller in self?.entryDidClose(controller) }
        )
        entryController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func entryDidClose(_ controller: URLEntryWindowController) {
        guard entryController === controller else { return }
        entryController = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentNextIfNeeded()
            if self.chooserController == nil && self.pendingURLs.isEmpty { NSApp.terminate(nil) }
        }
    }

    private func presentNextIfNeeded() {
        guard chooserController == nil, let url = pendingURLs.dequeue() else { return }
        let discovery = ProfileDiscovery()
        var profiles: [BrowserProfile] = []
        var issues: [String] = []
        for browser in [BrowserKind.chrome, .edge] {
            let result = discovery.inspect(browser)
            if let issue = result.issue { issues.append(issue) }
            if BrowserLauncher.isAvailable(BrowserProfile(browser: browser, directory: nil, name: browser.displayName)) {
                profiles.append(contentsOf: result.profiles)
            } else {
                issues.append("\(browser.displayName): app was not found by macOS")
            }
        }
        let safari = BrowserProfile(browser: .safari, directory: nil, name: "Safari")
        if BrowserLauncher.isAvailable(safari) { profiles.append(safari) }
        guard !profiles.isEmpty else { showNoBrowserError(); return }
        let controller = ChooserWindowController(
            url: url, profiles: profiles, issues: issues,
            choose: { [weak self] controller, profile in self?.launch(url, in: profile, from: controller) },
            closed: { [weak self] controller in self?.chooserDidClose(controller) }
        )
        chooserController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func launch(_ url: URL, in profile: BrowserProfile, from controller: ChooserWindowController) {
        guard chooserController === controller, controller.beginLaunch() else { return }
        guard launchGate.begin(controller.requestID) else {
            controller.finishLaunch()
            return
        }
        let requestID = controller.requestID
        BrowserLauncher.open(url, in: profile) { [weak self] result in
            guard let self,
                  self.chooserController === controller,
                  self.launchGate.isActive(requestID) else { return }
            switch result {
            case .success: controller.close()
            case .failure(let error):
                _ = self.launchGate.finish(requestID)
                controller.finishLaunch()
                self.showLaunchError(error, for: controller)
            }
        }
    }

    private func chooserDidClose(_ controller: ChooserWindowController) {
        _ = launchGate.finish(controller.requestID)
        guard chooserController === controller else { return }
        chooserController = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentNextIfNeeded()
            if self.chooserController == nil && self.pendingURLs.isEmpty { NSApp.terminate(nil) }
        }
    }

    private func showLaunchError(_ error: Error, for controller: ChooserWindowController) {
        guard chooserController === controller, let window = controller.window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }

    private func showNoBrowserError() {
        let alert = NSAlert()
        alert.messageText = "No supported browser is available"
        alert.informativeText = "Chrome, Edge, or Safari could not be found."
        alert.addButton(withTitle: "Close")
        alert.runModal()
        if pendingURLs.isEmpty { NSApp.terminate(nil) } else { presentNextIfNeeded() }
    }
}

enum BrowserLaunchError: LocalizedError {
    case couldNotStart(String)
    case exited(Int32)

    var errorDescription: String? {
        switch self {
        case .couldNotStart(let message): "Could not start the browser: \(message)"
        case .exited(let status): "The browser launcher exited with status \(status). Please choose again."
        }
    }
}

enum BrowserLauncher {
    @MainActor static func isAvailable(_ profile: BrowserProfile) -> Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: profile.browser.bundleIdentifier) != nil
    }

    @MainActor static func open(_ url: URL, in profile: BrowserProfile, completion: @escaping @MainActor (Result<Void, Error>) -> Void) {
        let request = BrowserLaunchRequest(url: url, profile: profile)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: request.executablePath)
        task.arguments = request.arguments
        task.terminationHandler = { process in
            DispatchQueue.main.async {
                if process.terminationStatus == 0 { completion(.success(())) }
                else { completion(.failure(BrowserLaunchError.exited(process.terminationStatus))) }
            }
        }
        do { try task.run() }
        catch { completion(.failure(BrowserLaunchError.couldNotStart(error.localizedDescription))) }
    }
}

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
        let window = NSWindow(contentViewController: NSViewController())
        window.title = "Choose a browser"
        window.styleMask = [.titled, .closable]
        super.init(window: window)
        window.delegate = self
        window.contentViewController = ChooserView(url: url, profiles: profiles, issues: issues) { [weak self] profile in
            guard let self else { return }
            self.choose(self, profile)
        }
        window.setContentSize(NSSize(width: 460, height: min(600, max(190, 112 + profiles.count * 42 + issues.count * 28))))
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func beginLaunch() -> Bool {
        guard !isLaunching else { return false }
        isLaunching = true
        return true
    }

    func finishLaunch() { isLaunching = false }
}

extension ChooserWindowController: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { closed(self) }
}

@MainActor
final class ChooserView: NSViewController {
    private let profiles: [BrowserProfile]
    private let choose: @MainActor (BrowserProfile) -> Void
    private var keyMonitor: Any?

    init(url: URL, profiles: [BrowserProfile], issues: [String], choose: @escaping @MainActor (BrowserProfile) -> Void) {
        self.profiles = profiles
        self.choose = choose
        super.init(nibName: nil, bundle: nil)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let heading = NSTextField(labelWithString: "Open link from \(URLRouter.hostLabel(for: url))")
        heading.font = .systemFont(ofSize: 16, weight: .semibold)
        heading.lineBreakMode = .byTruncatingMiddle
        heading.toolTip = url.absoluteString
        stack.addArrangedSubview(heading)
        let hint = NSTextField(labelWithString: "Press 1-9 to choose, or Escape to cancel.")
        hint.textColor = .secondaryLabelColor
        stack.addArrangedSubview(hint)
        for issue in issues {
            let label = NSTextField(labelWithString: issue)
            label.textColor = .systemOrange
            label.font = .systemFont(ofSize: 12)
            label.lineBreakMode = .byTruncatingMiddle
            label.toolTip = issue
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor).isActive = true
        }
        for (index, profile) in profiles.enumerated() {
            let prefix = index < 9 ? "\(index + 1).  " : ""
            let button = NSButton(title: "\(prefix)\(profile.displayName)", target: self, action: #selector(selectProfile(_:)))
            button.tag = index
            button.bezelStyle = .rounded
            button.translatesAutoresizingMaskIntoConstraints = false
            stack.addArrangedSubview(button)
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let document = NSView()
        document.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        scroll.documentView = document
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -22),
            heading.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor)
        ])
        view = NSView()
        view.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)
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
