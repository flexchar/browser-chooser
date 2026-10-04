import XCTest
@testable import BrowserChooser

final class BrowserChooserTests: XCTestCase {
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
            BrowserProfile(browser: .chrome, directory: "Profile 2", name: "DS-TTA"),
            BrowserProfile(browser: .chrome, directory: "Profile 3", name: "Heat Harmony"),
            BrowserProfile(browser: .chrome, directory: "Default", name: "JOE & THE JUICE"),
            BrowserProfile(browser: .chrome, directory: "Profile 4", name: "lvc.dk"),
            BrowserProfile(browser: .chrome, directory: "Profile 6", name: "PadelYard"),
            BrowserProfile(browser: .edge, directory: "Default", name: "Profile 1"),
            BrowserProfile(browser: .safari, directory: nil, name: "Safari")
        ]
        let ordered = ProfilePresentation.ordered(profiles)
        XCTAssertEqual(ordered.map(\.displayName), [
            "Edge - Personal", "Chrome - JOE & THE JUICE", "Chrome - DS-TTA",
            "Chrome - Heat Harmony", "Chrome - lvc.dk", "Chrome - PadelYard", "Safari"
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
        let buttons = scroll.documentView?.subviews.compactMap { $0 as? NSStackView }.flatMap(\.arrangedSubviews).compactMap { $0 as? NSButton } ?? []
        XCTAssertEqual(buttons.count, 7)
        XCTAssertEqual(window.contentLayoutRect.width, 360)
        XCTAssertLessThan(window.contentLayoutRect.height, 360)
        for button in buttons {
            let frame = button.convert(button.bounds, to: scroll.documentView)
            XCTAssertTrue(scroll.documentVisibleRect.contains(frame), "\(button.title) is outside the visible chooser")
        }
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
