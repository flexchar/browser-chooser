import Foundation

struct RoutingRule: Codable, Equatable, Identifiable {
    var host: String
    var profileID: String
    var enabled: Bool = true
    var pathPrefix: String? = nil
    var id: String { "\(host)|\(pathPrefix ?? "")" }
}

enum RuleError: LocalizedError {
    case invalidHost, invalidPathPrefix, duplicateHost, invalidProfile

    var errorDescription: String? {
        switch self {
        case .invalidHost: "Enter a valid web host or paste an http or https URL."
        case .invalidPathPrefix: "Enter a path beginning with /, such as /acme. Leave it empty for the whole host."
        case .duplicateHost: "A rule for this host and path prefix already exists."
        case .invalidProfile: "Choose an available browser profile."
        }
    }
}

enum RuleRouting {
    static func normalizedPathPrefix(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("/"), value != "/", !value.contains("//"),
              !value.contains("?"), !value.contains("#"), !value.contains("%") else { return nil }
        let path = value.hasSuffix("/") ? String(value.dropLast()) : value
        guard path.split(separator: "/").allSatisfy({ segment in
            segment != "." && segment != ".." && !segment.isEmpty && segment.utf8.allSatisfy {
                ($0 >= 65 && $0 <= 90) || ($0 >= 97 && $0 <= 122) ||
                ($0 >= 48 && $0 <= 57) || [45, 46, 95, 126].contains($0)
            }
        }) else { return nil }
        return path
    }

    static func normalizedHost(_ input: String) -> String? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        let candidate = value.contains("://") ? value : "https://\(value)"
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              components.user == nil, components.password == nil,
              let componentHost = components.host?.lowercased(),
              !componentHost.hasPrefix("."), !componentHost.hasSuffix(".."),
              let rawHost = Optional(componentHost.hasSuffix(".") ? String(componentHost.dropLast()) : componentHost),
              !rawHost.isEmpty, !rawHost.contains(".."), !rawHost.contains(":"),
              rawHost.count <= 253,
              rawHost.split(separator: ".").allSatisfy({ label in
                  label.count <= 63 && !label.isEmpty && label.first != "-" && label.last != "-" &&
                  label.utf8.allSatisfy { ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 }
              }) else { return nil }
        return rawHost
    }

    static func matchingRule(for url: URL, in rules: [RoutingRule]) -> RoutingRule? {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let host = url.host, let normalized = normalizedHost(host) else { return nil }
        let path = url.path(percentEncoded: true)
        let safePrefixPath = path.split(separator: "/").allSatisfy { segment in
            guard let decoded = String(segment).removingPercentEncoding else { return false }
            return decoded != "." && decoded != ".." && !decoded.contains("/") && !decoded.contains("\\")
        }
        return rules.filter { rule in
            guard rule.enabled, rule.host == normalized else { return false }
            guard let prefix = rule.pathPrefix else { return true }
            return safePrefixPath && (path == prefix || path.hasPrefix(prefix + "/"))
        }.max { ($0.pathPrefix?.count ?? 0) < ($1.pathPrefix?.count ?? 0) }
    }

    static func availableProfile(for rule: RoutingRule, profiles: [BrowserProfile], directoryExists: (BrowserProfile) -> Bool = { profile in
        guard profile.browser != .safari, let directory = profile.directory, let state = profile.browser.localStateURL else { return true }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: state.deletingLastPathComponent().appendingPathComponent(directory).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }) -> BrowserProfile? {
        profiles.first { $0.id == rule.profileID && directoryExists($0) }
    }
}

struct RoutingDestination {
    let url: URL
    let isSafeLink: Bool
}

enum SafeLinkRouting {
    private static let host = "safelinks.protection.outlook.com"

    static func destination(for original: URL) -> RoutingDestination? {
        guard let originalHost = original.host?.lowercased(), isSafeLinkHost(originalHost) else {
            return RoutingDestination(url: original, isSafeLink: false)
        }
        guard original.scheme?.lowercased() == "https",
              original.user == nil, original.password == nil,
              original.port == nil || original.port == 443,
              original.path.isEmpty || original.path == "/",
              let components = URLComponents(url: original, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else { return nil }
        let destinations = queryItems.filter { $0.name.lowercased() == "url" }
        guard destinations.count == 1, destinations[0].name == "url",
              let value = destinations[0].value, !value.isEmpty, validTargetText(value),
              let target = URL(string: value),
              let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme),
              target.user == nil, target.password == nil,
              let targetHost = target.host, RuleRouting.normalizedHost(targetHost) != nil,
              !isSafeLinkHost(targetHost.lowercased()) else { return nil }
        return RoutingDestination(url: target, isSafeLink: true)
    }

    private static func validTargetText(_ value: String) -> Bool {
        guard value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else { return false }
        let bytes = Array(value.utf8)
        for index in bytes.indices where bytes[index] == 37 {
            guard index + 2 < bytes.count,
                  bytes[(index + 1)...(index + 2)].allSatisfy({
                      ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
                  }) else { return false }
        }
        return true
    }

    private static func isSafeLinkHost(_ candidate: String) -> Bool {
        guard let normalized = RuleRouting.normalizedHost(candidate), normalized == candidate else { return false }
        return normalized == host || normalized.hasSuffix("." + host)
    }
}

struct AddRuleArguments: Equatable {
    let host: String
    let pathPrefix: String?
    let profileID: String

    static func parse(_ arguments: [String]) -> AddRuleArguments? {
        guard let first = arguments.first, let host = RuleRouting.normalizedHost(first) else { return nil }
        var profileID: String?
        var pathPrefix: String?
        var index = 1
        while index < arguments.count {
            guard index + 1 < arguments.count else { return nil }
            switch arguments[index] {
            case "--profile":
                guard profileID == nil, BrowserProfile.validID(arguments[index + 1]) else { return nil }
                profileID = arguments[index + 1]
            case "--path-prefix":
                guard pathPrefix == nil, let normalized = RuleRouting.normalizedPathPrefix(arguments[index + 1]) else { return nil }
                pathPrefix = normalized
            default: return nil
            }
            index += 2
        }
        guard let profileID else { return nil }
        return AddRuleArguments(host: host, pathPrefix: pathPrefix, profileID: profileID)
    }
}

final class RoutingRuleStore {
    private let defaults: UserDefaults
    private let key = "routingRules.v1"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [RoutingRule] {
        guard let data = defaults.data(forKey: key), let decoded = try? JSONDecoder().decode([RoutingRule].self, from: data) else { return [] }
        var seen = Set<String>()
        return decoded.filter { rule in
            guard RuleRouting.normalizedHost(rule.host) == rule.host,
                  rule.pathPrefix.map({ RuleRouting.normalizedPathPrefix($0) == $0 }) ?? true,
                  BrowserProfile.validID(rule.profileID), !seen.contains(rule.id) else { return false }
            seen.insert(rule.id)
            return true
        }
    }

    func save(_ rules: [RoutingRule]) throws {
        var seen = Set<String>()
        for rule in rules {
            guard RuleRouting.normalizedHost(rule.host) == rule.host else { throw RuleError.invalidHost }
            guard rule.pathPrefix.map({ RuleRouting.normalizedPathPrefix($0) == $0 }) ?? true else { throw RuleError.invalidPathPrefix }
            guard BrowserProfile.validID(rule.profileID) else { throw RuleError.invalidProfile }
            guard seen.insert(rule.id).inserted else { throw RuleError.duplicateHost }
        }
        defaults.set(try JSONEncoder().encode(rules), forKey: key)
    }
}
