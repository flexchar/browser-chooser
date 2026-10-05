import XCTest
@testable import BrowserChooser

final class BrowserChooserTests: XCTestCase {
    func testDefaultRuleStoreCanLoadWithoutCustomSuite() {
        _ = RoutingRuleStore().load()
    }
    func testRuleNormalizesHostOnlyAndRejectsInvalidHosts() {
        XCTAssertEqual(RuleRouting.normalizedHost(" HTTPS://Work.Example.com./tickets?id=secret "), "work.example.com")
        XCTAssertEqual(RuleRouting.normalizedHost("work.example.com"), "work.example.com")
        for invalid in ["", ".work.example.com", "work.example.com..", "work..example.com", "https://user:pass@work.example.com", "file://work.example.com", "localhost:bad", "https://work.example.com:bad/"] {
            XCTAssertNil(RuleRouting.normalizedHost(invalid), invalid)
        }
    }

    func testRuleMatchesOnlyExactHostAndEnabledWebLinks() {
        let rule = RoutingRule(host: "work.example.com", profileID: "chrome:Default")
        let urls = ["https://work.example.com/a?secret=1", "http://WORK.EXAMPLE.COM/b"]
        for raw in urls { XCTAssertEqual(RuleRouting.matchingRule(for: URL(string: raw)!, in: [rule]), rule) }
        for raw in ["https://sub.work.example.com", "https://work.example.com.evil.test", "https://other.example.com", "file://work.example.com/file"] {
            XCTAssertNil(RuleRouting.matchingRule(for: URL(string: raw)!, in: [rule]), raw)
        }
        XCTAssertNil(RuleRouting.matchingRule(for: URL(string: urls[0])!, in: [RoutingRule(host: rule.host, profileID: rule.profileID, enabled: false)]))
    }

    func testRuleStorePersistsAndRejectsCollisionsWithoutRealPreferences() throws {
        let suite = "test.browserchooser.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RoutingRuleStore(defaults: defaults)
        let rule = RoutingRule(host: "work.example.com", profileID: "chrome:Default")
        try store.save([rule])
        XCTAssertEqual(RoutingRuleStore(defaults: defaults).load(), [rule])
        XCTAssertThrowsError(try store.save([rule, rule]))
        XCTAssertEqual(store.load(), [rule])
    }

    func testMissingProfileDirectoryForcesChooser() {
        let rule = RoutingRule(host: "work.example.com", profileID: "chrome:Default")
        let profile = BrowserProfile(browser: .chrome, directory: "Default", name: "Work")
        XCTAssertNil(RuleRouting.availableProfile(for: rule, profiles: [profile], directoryExists: { _ in false }))
        XCTAssertEqual(RuleRouting.availableProfile(for: rule, profiles: [profile], directoryExists: { _ in true }), profile)
        XCTAssertNil(RuleRouting.availableProfile(for: rule, profiles: [BrowserProfile(browser: .edge, directory: "Default", name: "Work")], directoryExists: { _ in true }))
    }

    @MainActor func testSettingsWindowConstructsWithMissingRuleTarget() throws {
        let suite = "test.browserchooser.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RoutingRuleStore(defaults: defaults)
        try store.save([RoutingRule(host: "work.example.com", profileID: "chrome:Profile 9")])
        let settings = SettingsWindowController(store: store, profiles: [BrowserProfile(browser: .safari, directory: nil, name: "Safari")], closed: {})
        XCTAssertEqual(settings.window?.title, "Routing settings")
        XCTAssertEqual(store.load().count, 1)
        XCTAssertEqual(settings.window?.contentLayoutRect.size, NSSize(width: 560, height: 430))
        settings.beginEditingRule(at: 0)
        XCTAssertNil(settings.selectedProfileID)
        XCTAssertNotNil(settings.validationMessage)
    }

    @MainActor func testAutomaticRoutesSerializeAndFailureReturnsSameURLToChooser() throws {
        let suite = "test.browserchooser.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = RoutingRuleStore(defaults: defaults)
        try store.save([RoutingRule(host: "work.example.com", profileID: "safari:safari")])
        let profile = BrowserProfile(browser: .safari, directory: nil, name: "Safari")
        var opened: [URL] = []
        var completions: [@MainActor (Result<Void, Error>) -> Void] = []
        var fallbacks: [URL] = []
        let app = AppDelegate(ruleStore: store, profileProvider: { ([profile], []) }, browserOpener: { url, _, completion in
            opened.append(url)
            completions.append(completion)
        }, fallbackObserver: { url, _ in fallbacks.append(url) })
        let first = URL(string: "https://work.example.com/one")!
        let second = URL(string: "https://work.example.com/two")!
        app.application(NSApplication.shared, open: [first, second])
        XCTAssertEqual(opened, [first])
        XCTAssertFalse(app.canPresentEntry, "cold-start URL delivery must suppress the empty URL entry window")
        XCTAssertTrue(fallbacks.isEmpty)
        completions[0](.success(()))
        XCTAssertEqual(opened, [first, second])
        completions[1](.failure(BrowserLaunchError.exited(1)))
        XCTAssertEqual(fallbacks, [second])
        completions[0](.success(()))
        XCTAssertEqual(fallbacks, [second], "stale completion must not present a second chooser")
    }

    @MainActor func testHiddenChooserDoesNotCloseOnSettingsFocus() {
        let chooser = ChooserWindowController(url: URL(string: "https://example.com")!, profiles: [BrowserProfile(browser: .safari, directory: nil, name: "Safari")], issues: [], choose: { _, _ in }, closed: { _ in })
        XCTAssertTrue(chooser.shouldCloseOnResignKey)
        chooser.hideForSettings()
        XCTAssertFalse(chooser.shouldCloseOnResignKey)
    }
    func testRouterAcceptsOnlyWebURLs() {
        XCTAssertEqual(URLRouter.validatedWebURL(from: ["BrowserChooser", "https://example.com/a?b=c"])?.host, "example.com")
        XCTAssertNil(URLRouter.validatedWebURL(from: ["BrowserChooser", "zoommtg://zoom.us/join"]))
        XCTAssertNil(URLRouter.validatedWebURL(from: ["BrowserChooser", "file:///tmp/test"]))
        XCTAssertNil(URLRouter.validatedWebURL(from: ["BrowserChooser", "https:///missing-host"]))
    }

    func testProfileDiscoveryUsesNamesAndSkipsMalformedEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = directory.appendingPathComponent("Local State")
        let json = #"{"profile":{"info_cache":{"Profile 2":{"name":"Client"},"Default":{"name":"Work"},"":{"name":"Ignore"},"Profile 4":{}}}}"#
        try json.data(using: .utf8)!.write(to: state)
        let profiles = ProfileDiscovery().profiles(for: .chrome, localStateURL: state)
        XCTAssertEqual(profiles.map(\.directory), ["Profile 2", "Profile 4", "Default"])
        XCTAssertEqual(profiles.map(\.name), ["Client", "Profile 4", "Work"])
    }

    func testSafariIsAlwaysAvailableFallback() {
        XCTAssertEqual(ProfileDiscovery().allProfiles().last, BrowserProfile(browser: .safari, directory: nil, name: "Safari"))
    }

    func testPersonalShortcutOrderAndRoutingStayBoundToProfileDirectories() {
        let profiles = [
            BrowserProfile(browser: .chrome, directory: "Profile 2", name: "ClientA"),
            BrowserProfile(browser: .chrome, directory: "Profile 3", name: "Consulting"),
            BrowserProfile(browser: .chrome, directory: "Default", name: "Work"),
            BrowserProfile(browser: .chrome, directory: "Profile 4", name: "Studio"),
            BrowserProfile(browser: .chrome, directory: "Profile 6", name: "ClientB"),
            BrowserProfile(browser: .edge, directory: "Default", name: "Profile 1"),
            BrowserProfile(browser: .safari, directory: nil, name: "Safari")
        ]
        let ordered = ProfilePresentation.ordered(profiles)
        XCTAssertEqual(ordered.map(\.displayName), [
            "Edge - Personal", "Chrome - Work", "Chrome - ClientA",
            "Chrome - Consulting", "Chrome - Studio", "Chrome - ClientB", "Safari"
        ])
        XCTAssertEqual(ordered.map(\.menuName), [
            "Personal", "Work", "ClientA", "Consulting", "Studio", "ClientB", "Safari"
        ])
        XCTAssertEqual(ordered.map(\.id), [
            "edge:Default", "chrome:Default", "chrome:Profile 2", "chrome:Profile 3",
            "chrome:Profile 4", "chrome:Profile 6", "safari:safari"
        ])
        let url = URL(string: "https://example.com")!
        XCTAssertEqual(BrowserLaunchRequest(url: url, profile: ordered[0]).arguments[4], "--profile-directory=Default")
        XCTAssertEqual(BrowserLaunchRequest(url: url, profile: ordered[1]).arguments[4], "--profile-directory=Default")
        let anotherEdge = BrowserProfile(browser: .edge, directory: "Profile 2", name: "Other")
        XCTAssertEqual(ProfilePresentation.ordered(profiles + [anotherEdge]).last, anotherEdge)
        XCTAssertEqual(anotherEdge.displayName, "Edge - Other")
    }

    func testChromiumLaunchUsesBundleIdentifierNewInstanceAndExactProfileDirectory() {
        let profile = BrowserProfile(browser: .chrome, directory: "Profile 9", name: "Client")
        let request = BrowserLaunchRequest(url: URL(string: "https://example.com/a")!, profile: profile)
        XCTAssertEqual(request.executablePath, "/usr/bin/open")
        XCTAssertEqual(request.arguments, ["-n", "-b", "com.google.Chrome", "--args", "--profile-directory=Profile 9", "https://example.com/a"])
    }

    func testSafariLaunchTargetsSafariInsteadOfDefaultHandler() {
        let profile = BrowserProfile(browser: .safari, directory: nil, name: "Safari")
        let request = BrowserLaunchRequest(url: URL(string: "https://example.com")!, profile: profile)
        XCTAssertEqual(request.arguments, ["-b", "com.apple.Safari", "https://example.com"])
    }

    func testIncomingLinkQueuePreservesArrivalOrder() {
        var queue = URLQueue()
        let first = URL(string: "https://one.example")!
        let second = URL(string: "https://two.example")!
        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertEqual(queue.dequeue(), first)
        XCTAssertEqual(queue.dequeue(), second)
        XCTAssertNil(queue.dequeue())
    }

    func testLaunchRequestGateRejectsDuplicateAndStaleCompletions() {
        var gate = LaunchRequestGate()
        let first = UUID()
        let second = UUID()
        XCTAssertTrue(gate.begin(first))
        XCTAssertFalse(gate.begin(second))
        XCTAssertFalse(gate.finish(second))
        XCTAssertTrue(gate.finish(first))
        XCTAssertTrue(gate.begin(second))
    }

    @MainActor func testChooserWindowKeepsSevenProfileButtonsInVisibleContent() throws {
        let profiles = (1...6).map { BrowserProfile(browser: .chrome, directory: "Profile \($0)", name: "Test \($0)") } +
            [BrowserProfile(browser: .safari, directory: nil, name: "Safari")]
        let chooser = ChooserWindowController(url: URL(string: "https://example.com")!, profiles: profiles, issues: [], choose: { _, _ in }, closed: { _ in })
        let window = try XCTUnwrap(chooser.window)
        let scroll = try XCTUnwrap(window.contentViewController?.view.subviews.compactMap { $0 as? NSScrollView }.first)
        window.contentView?.layoutSubtreeIfNeeded()
        scroll.documentView?.layoutSubtreeIfNeeded()
        let buttons = (scroll.documentView as? NSStackView)?.arrangedSubviews.compactMap { $0 as? NSButton } ?? []
        XCTAssertEqual(buttons.count, 7)
        XCTAssertEqual(window.styleMask, .borderless)
        XCTAssertTrue(window.canBecomeKey)
        XCTAssertEqual(window.title, "Choose a browser")
        XCTAssertEqual(window.contentLayoutRect.size, NSSize(width: 296, height: 265))
        for button in buttons {
            let frame = button.convert(button.bounds, to: scroll.documentView)
            XCTAssertTrue(scroll.documentVisibleRect.contains(frame), "\(button.title) is outside the visible chooser")
            for child in button.subviews {
                let childCenter = NSPoint(x: child.bounds.midX, y: child.bounds.midY)
                let point = child.convert(childCenter, to: scroll.documentView)
                XCTAssertTrue(scroll.documentView?.hitTest(point) === button, "Row child intercepted a click")
            }
        }
    }

    @MainActor func testChooserRowsUseAlignedBrowserAndProfileColumns() throws {
        let profiles = [
            BrowserProfile(browser: .edge, directory: "Default", name: "Profile 1"),
            BrowserProfile(browser: .chrome, directory: "Default", name: "CONSULTING WORK"),
            BrowserProfile(browser: .safari, directory: nil, name: "Safari")
        ]
        let chooser = ChooserWindowController(url: URL(string: "https://example.com")!, profiles: profiles, issues: [], choose: { _, _ in }, closed: { _ in })
        let window = try XCTUnwrap(chooser.window)
        window.contentView?.layoutSubtreeIfNeeded()
        let scroll = try XCTUnwrap(window.contentViewController?.view.subviews.compactMap { $0 as? NSScrollView }.first)
        scroll.documentView?.layoutSubtreeIfNeeded()
        let rows = try XCTUnwrap((scroll.documentView as? NSStackView)?.arrangedSubviews.compactMap { $0 as? NSButton })
        XCTAssertEqual(rows.count, 3)

        func column(_ name: String, in row: NSButton) throws -> NSTextField {
            try XCTUnwrap(row.subviews.compactMap { $0 as? NSTextField }.first { $0.identifier?.rawValue == name })
        }
        let numbers = try rows.map { try column("shortcut", in: $0) }
        let browsers = try rows.map { try column("browser", in: $0) }
        let names = try rows.map { try column("profile", in: $0) }
        XCTAssertEqual(numbers.map(\.stringValue), ["1.", "2.", "3."])
        XCTAssertEqual(browsers.map(\.stringValue), ["Edge", "Chrome", "Safari"])
        XCTAssertEqual(names.map(\.stringValue), ["Personal", "CONSULTING WORK", ""])
        XCTAssertEqual(Set(numbers.map { $0.frame.minX }).count, 1)
        XCTAssertEqual(Set(browsers.map { $0.frame.minX }).count, 1)
        XCTAssertEqual(Set(names.map { $0.frame.minX }).count, 1)
        XCTAssertLessThan(numbers[0].frame.minX, browsers[0].frame.minX)
        XCTAssertLessThan(browsers[0].frame.minX, names[0].frame.minX)
        XCTAssertGreaterThanOrEqual(names[1].frame.width, names[1].intrinsicContentSize.width)
        XCTAssertEqual(window.contentLayoutRect.size, NSSize(width: 296, height: 137))
    }

    @MainActor func testLongChooserStartsAtFirstProfiles() throws {
        let profiles = (1...10).map { BrowserProfile(browser: .chrome, directory: "Profile \($0)", name: "Test \($0)") }
        let chooser = ChooserWindowController(url: URL(string: "https://example.com")!, profiles: profiles, issues: [], choose: { _, _ in }, closed: { _ in })
        let window = try XCTUnwrap(chooser.window)
        let scroll = try XCTUnwrap(window.contentViewController?.view.subviews.compactMap { $0 as? NSScrollView }.first)
        window.contentView?.layoutSubtreeIfNeeded()
        scroll.documentView?.layoutSubtreeIfNeeded()
        let rows = try XCTUnwrap((scroll.documentView as? NSStackView)?.arrangedSubviews)
        XCTAssertEqual(rows.count, 10)
        XCTAssertEqual(window.contentLayoutRect.height, 265)
        let first = rows[0].convert(rows[0].bounds, to: scroll.documentView)
        let seventh = rows[6].convert(rows[6].bounds, to: scroll.documentView)
        let last = rows[9].convert(rows[9].bounds, to: scroll.documentView)
        XCTAssertTrue(scroll.documentVisibleRect.contains(first), "The first prioritized profile must be visible")
        XCTAssertTrue(scroll.documentVisibleRect.contains(seventh), "Seven rows should fit without scrolling")
        XCTAssertFalse(scroll.documentVisibleRect.intersects(last), "Later profiles should start below the fold")
    }

    func testChooserPlacementPrefersBelowRightAndFlipsAtScreenEdges() {
        let screen = NSRect(x: -1920, y: -200, width: 1920, height: 1080)
        let size = NSSize(width: 360, height: 360)
        let middle = ChooserPlacement.frame(for: size, near: NSPoint(x: -1000, y: 500), in: screen)
        XCTAssertEqual(middle.origin, NSPoint(x: -988, y: 128))
        let bottomRight = ChooserPlacement.frame(for: size, near: NSPoint(x: -20, y: -180), in: screen)
        XCTAssertEqual(bottomRight.origin, NSPoint(x: -392, y: -168))
        XCTAssertTrue(screen.contains(bottomRight))
        let topLeft = ChooserPlacement.frame(for: size, near: NSPoint(x: -1900, y: 860), in: screen)
        XCTAssertEqual(topLeft.origin, NSPoint(x: -1888, y: 488))
        XCTAssertTrue(screen.contains(topLeft))
    }

    func testChooserPlacementFitsWithinSmallVisibleFrame() {
        let screen = NSRect(x: 400, y: 100, width: 300, height: 250)
        let frame = ChooserPlacement.frame(for: NSSize(width: 360, height: 400), near: NSPoint(x: 690, y: 110), in: screen)
        XCTAssertEqual(frame.size, NSSize(width: 276, height: 226))
        XCTAssertEqual(frame.origin, NSPoint(x: 412, y: 112))
        XCTAssertTrue(screen.contains(frame))
    }

    func testProfileInspectionReportsUnreadableDataWithoutNames() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = ProfileDiscovery().inspect(.chrome, localStateURL: missing)
        XCTAssertTrue(result.profiles.isEmpty)
        XCTAssertEqual(result.issue, "Chrome: profile data was not found")
    }
}
