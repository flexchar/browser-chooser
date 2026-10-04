import Foundation

enum BrowserKind: String, CaseIterable, Sendable {
    case chrome
    case edge
    case safari

    var displayName: String {
        switch self {
        case .chrome: "Chrome"
        case .edge: "Edge"
        case .safari: "Safari"
        }
    }

    var applicationName: String? {
        switch self {
        case .chrome: "Google Chrome"
        case .edge: "Microsoft Edge"
        case .safari: nil
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .chrome: "com.google.Chrome"
        case .edge: "com.microsoft.edgemac"
        case .safari: "com.apple.Safari"
        }
    }

    var localStateURL: URL? {
        let library = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support")
        switch self {
        case .chrome: return library.appendingPathComponent("Google/Chrome/Local State")
        case .edge: return library.appendingPathComponent("Microsoft Edge/Local State")
        case .safari: return nil
        }
    }
}

struct BrowserLaunchRequest: Equatable, Sendable {
    let executablePath: String = "/usr/bin/open"
    let arguments: [String]

    init(url: URL, profile: BrowserProfile) {
        if profile.browser == .safari {
            arguments = ["-b", profile.browser.bundleIdentifier, url.absoluteString]
        } else {
            arguments = ["-n", "-b", profile.browser.bundleIdentifier, "--args", "--profile-directory=\(profile.directory ?? "Default")", url.absoluteString]
        }
    }
}

struct BrowserProfile: Identifiable, Equatable, Sendable {
    let browser: BrowserKind
    let directory: String?
    let name: String

    var id: String { "\(browser.rawValue):\(directory ?? "safari")" }
    var displayName: String {
        if id == "edge:Default" { return "Edge - Personal" }
        return browser == .safari ? name : "\(browser.displayName) - \(name)"
    }

    var menuName: String { id == "edge:Default" ? "Personal" : name }
}

enum ProfilePresentation {
    // These are local profile directories, not account names. Keep routing tied to each directory.
    private static let preferredIDs = ["edge:Default", "chrome:Default"]

    static func ordered(_ profiles: [BrowserProfile]) -> [BrowserProfile] {
        preferredIDs.compactMap { id in profiles.first { $0.id == id } } +
        profiles.filter { !preferredIDs.contains($0.id) }
    }
}

enum URLRouter {
    static func validatedWebURL(from arguments: [String]) -> URL? {
        for argument in arguments.dropFirst() {
            guard let url = URL(string: argument),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  let host = url.host,
                  !host.isEmpty else { continue }
            return url
        }
        return nil
    }

    static func hostLabel(for url: URL) -> String {
        url.host(percentEncoded: false) ?? url.absoluteString
    }
}

struct URLQueue {
    private var values: [URL] = []

    var isEmpty: Bool { values.isEmpty }

    mutating func enqueue(_ url: URL) { values.append(url) }

    mutating func dequeue() -> URL? {
        guard !values.isEmpty else { return nil }
        return values.removeFirst()
    }
}

struct ProfileDiscovery {
    struct Result {
        let profiles: [BrowserProfile]
        let issue: String?
    }

    private struct LocalState: Decodable {
        let profile: ProfileContainer?
    }

    private struct ProfileContainer: Decodable {
        let infoCache: [String: ProfileInfo]?
        enum CodingKeys: String, CodingKey { case infoCache = "info_cache" }
    }

    private struct ProfileInfo: Decodable {
        let name: String?
    }

    let fileManager: FileManager

    init(fileManager: FileManager = .default) { self.fileManager = fileManager }

    func profiles(for browser: BrowserKind, localStateURL: URL? = nil) -> [BrowserProfile] {
        inspect(browser, localStateURL: localStateURL).profiles
    }

    func inspect(_ browser: BrowserKind, localStateURL: URL? = nil) -> Result {
        guard browser != .safari, let stateURL = localStateURL ?? browser.localStateURL else {
            return Result(profiles: [], issue: nil)
        }
        guard fileManager.fileExists(atPath: stateURL.path) else {
            return Result(profiles: [], issue: "\(browser.displayName): profile data was not found")
        }
        let data: Data
        do { data = try Data(contentsOf: stateURL) }
        catch {
            return Result(profiles: [], issue: "\(browser.displayName): cannot read profiles. Check Files & Folders access.")
        }
        guard let state = try? JSONDecoder().decode(LocalState.self, from: data),
              let cache = state.profile?.infoCache else {
            return Result(profiles: [], issue: "\(browser.displayName): profile data could not be parsed")
        }

        let profiles: [BrowserProfile] = cache.compactMap { directory, info in
            guard !directory.isEmpty else { return nil }
            let cleanName = info.name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return BrowserProfile(browser: browser, directory: directory,
                                  name: cleanName?.isEmpty == false ? cleanName! : directory)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return Result(profiles: profiles,
                      issue: profiles.isEmpty ? "\(browser.displayName): no profiles were found" : nil)
    }

    func allProfiles() -> [BrowserProfile] {
        ProfilePresentation.ordered(
            BrowserKind.allCases.filter { $0 != .safari }.flatMap { profiles(for: $0) } +
            [BrowserProfile(browser: .safari, directory: nil, name: "Safari")]
        )
    }
}
