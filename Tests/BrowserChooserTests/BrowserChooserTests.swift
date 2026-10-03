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

    @MainActor func testChooserViewBuildsWithProfileButtons() {
        let profiles = [BrowserProfile(browser: .safari, directory: nil, name: "Safari")]
        let chooser = ChooserView(url: URL(string: "https://example.com")!, profiles: profiles, issues: ["Chrome: profile data could not be read"]) { _ in }
        XCTAssertNotNil(chooser.view)
    }

    func testProfileInspectionReportsUnreadableDataWithoutNames() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let result = ProfileDiscovery().inspect(.chrome, localStateURL: missing)
        XCTAssertTrue(result.profiles.isEmpty)
        XCTAssertEqual(result.issue, "Chrome: profile data was not found")
    }
}
