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
    typealias ProfileSnapshot = (profiles: [BrowserProfile], issues: [String])
    typealias OpenBrowser = @MainActor (URL, BrowserProfile, @escaping @MainActor (Result<Void, Error>) -> Void) -> Void
    private var pendingURLs = URLQueue()
    private var chooserController: ChooserWindowController?
    private var entryController: URLEntryWindowController?
    private var settingsController: SettingsWindowController?
    private var launchGate = LaunchRequestGate()
    private let ruleStore: RoutingRuleStore
    private let profileProvider: (@MainActor () -> ProfileSnapshot)?
    private let browserOpener: OpenBrowser
    private let fallbackObserver: (@MainActor (URL, [String]) -> Void)?
    private var automaticURL: URL?
    private var deferredFailure: (url: URL, profiles: [BrowserProfile], issues: [String])?
    private var deferredManualError: Error?

    init(ruleStore: RoutingRuleStore = RoutingRuleStore(),
         profileProvider: (@MainActor () -> ProfileSnapshot)? = nil,
         browserOpener: @escaping OpenBrowser = BrowserLauncher.open,
         fallbackObserver: (@MainActor (URL, [String]) -> Void)? = nil) {
        self.ruleStore = ruleStore
        self.profileProvider = profileProvider
        self.browserOpener = browserOpener
        self.fallbackObserver = fallbackObserver
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let args = CommandLine.arguments
        if args.contains("--settings") { showSettings(); return }
        if let index = args.firstIndex(of: "--add-rule") {
            guard let request = AddRuleArguments.parse(Array(args.dropFirst(index + 1))) else {
                fputs("Usage: --add-rule HOST [--path-prefix /path] --profile browser:directory\n", stderr)
                exit(2)
            }
            let profiles = availableProfiles().profiles
            let requestedRule = RoutingRule(host: request.host, profileID: request.profileID, pathPrefix: request.pathPrefix)
            guard let profile = RuleRouting.availableProfile(for: requestedRule, profiles: profiles) else {
                fputs("Unavailable profile\n", stderr); exit(2)
            }
            var rules = ruleStore.load().filter { $0.id != requestedRule.id }
            rules.append(RoutingRule(host: request.host, profileID: profile.id, pathPrefix: request.pathPrefix))
            do { try ruleStore.save(rules); print("Saved \(request.host)\(request.pathPrefix ?? "") → \(profile.id)") }
            catch { fputs("Cannot save rule: \(error.localizedDescription)\n", stderr); exit(2) }
            NSApp.terminate(nil); return
        }
        if let index = args.firstIndex(of: "--explain-route"), args.count > index + 1 {
            guard let url = URLRouter.validatedWebURL(from: ["BrowserChooser", args[index + 1]]) else { fputs("Invalid web URL\n", stderr); exit(2) }
            let decision = routeDecision(for: url, profiles: availableProfiles().profiles)
            let destination = SafeLinkRouting.destination(for: url)
            let label = destination.map { URLRouter.hostLabel(for: $0.url) + ($0.isSafeLink ? " (via Safe Link)" : "") } ?? URLRouter.hostLabel(for: url)
            print(decision.profile.map { "\(label) → \($0.id)" } ?? "\(label) → chooser\(decision.issue.map { " (\($0))" } ?? "")")
            NSApp.terminate(nil); return
        }
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
        guard canPresentEntry else { return }
        let controller = URLEntryWindowController(
            submit: { [weak self] url in self?.enqueue(url) },
            settings: { [weak self] in self?.showSettings() },
            closed: { [weak self] controller in self?.entryDidClose(controller) }
        )
        entryController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    var canPresentEntry: Bool {
        entryController == nil && chooserController == nil && settingsController == nil &&
        automaticURL == nil && deferredFailure == nil && pendingURLs.isEmpty
    }

    private func entryDidClose(_ controller: URLEntryWindowController) {
        guard entryController === controller else { return }
        entryController = nil
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.presentNextIfNeeded()
            self.terminateIfIdle()
        }
    }

    private func presentNextIfNeeded() {
        guard chooserController == nil, automaticURL == nil, settingsController == nil, let url = pendingURLs.dequeue() else { return }
        let available = availableProfiles()
        let decision = routeDecision(for: url, profiles: available.profiles)
        if let profile = decision.profile {
            automaticURL = url
            let id = UUID()
            guard launchGate.begin(id) else { automaticURL = nil; pendingURLs.enqueue(url); return }
            browserOpener(url, profile) { [weak self] result in
                guard let self, self.launchGate.isActive(id), self.automaticURL == url else { return }
                _ = self.launchGate.finish(id)
                self.automaticURL = nil
                switch result {
                case .success: self.presentNextIfNeeded(); self.terminateIfIdle()
                case .failure(let error):
                    let issues = available.issues + [error.localizedDescription]
                    if self.settingsController != nil { self.deferredFailure = (url, available.profiles, issues) }
                    else { self.presentChooser(url, profiles: available.profiles, issues: issues) }
                }
            }
            return
        }
        presentChooser(url, profiles: available.profiles, issues: available.issues + (decision.issue.map { [$0] } ?? []))
    }

    private func presentChooser(_ url: URL, profiles: [BrowserProfile], issues: [String]) {
        if let fallbackObserver { fallbackObserver(url, issues); return }
        guard !profiles.isEmpty else { showNoBrowserError(); return }
        let controller = ChooserWindowController(
            url: url, profiles: ProfilePresentation.ordered(profiles), issues: issues,
            settings: { [weak self] in self?.showSettings() },
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
        browserOpener(url, profile) { [weak self] result in
            guard let self,
                  self.chooserController === controller,
                  self.launchGate.isActive(requestID) else { return }
            switch result {
            case .success: controller.close()
            case .failure(let error):
                _ = self.launchGate.finish(requestID)
                controller.finishLaunch()
                if self.settingsController != nil { self.deferredManualError = error }
                else { self.showLaunchError(error, for: controller) }
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
            self.terminateIfIdle()
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
        if pendingURLs.isEmpty { terminateIfIdle() } else { presentNextIfNeeded() }
    }

    private func availableProfiles() -> (profiles: [BrowserProfile], issues: [String]) {
        if let profileProvider { return profileProvider() }
        let discovery = ProfileDiscovery()
        var profiles: [BrowserProfile] = []
        var issues: [String] = []
        for browser in [BrowserKind.chrome, .edge] {
            let result = discovery.inspect(browser)
            if let issue = result.issue { issues.append(issue) }
            if BrowserLauncher.isAvailable(BrowserProfile(browser: browser, directory: nil, name: browser.displayName)) { profiles += result.profiles }
            else { issues.append("\(browser.displayName): app was not found by macOS") }
        }
        let safari = BrowserProfile(browser: .safari, directory: nil, name: "Safari")
        if BrowserLauncher.isAvailable(safari) { profiles.append(safari) }
        return (ProfilePresentation.ordered(profiles), issues)
    }

    private func routeDecision(for url: URL, profiles: [BrowserProfile]) -> (profile: BrowserProfile?, issue: String?) {
        guard let destination = SafeLinkRouting.destination(for: url),
              let rule = RuleRouting.matchingRule(for: destination.url, in: ruleStore.load()) else { return (nil, nil) }
        guard let profile = RuleRouting.availableProfile(for: rule, profiles: profiles) else {
            return (nil, "Saved route unavailable for \(rule.host). Choose a browser or update Settings.")
        }
        return (profile, nil)
    }

    @objc private func showSettings() {
        if let settingsController { settingsController.showWindow(nil); NSApp.activate(ignoringOtherApps: true); return }
        chooserController?.hideForSettings()
        let controller = SettingsWindowController(store: ruleStore, profiles: availableProfiles().profiles) { [weak self] in
            guard let self else { return }
            self.settingsController = nil
            if let chooser = self.chooserController {
                chooser.resumeAfterSettings()
                NSApp.activate(ignoringOtherApps: true)
                if let error = self.deferredManualError { self.deferredManualError = nil; self.showLaunchError(error, for: chooser) }
            }
            else if let failure = self.deferredFailure {
                self.deferredFailure = nil
                self.presentChooser(failure.url, profiles: failure.profiles, issues: failure.issues)
            } else { self.presentNextIfNeeded(); self.terminateIfIdle() }
        }
        settingsController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func terminateIfIdle() {
        if fallbackObserver == nil && chooserController == nil && entryController == nil && settingsController == nil && automaticURL == nil && pendingURLs.isEmpty { NSApp.terminate(nil) }
    }

    private func installMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Browser Chooser", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApp.mainMenu = menu
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
