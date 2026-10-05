import Foundation

struct RoutingRule: Codable, Equatable, Identifiable {
    var host: String
    var profileID: String
    var enabled: Bool = true
    var id: String { host }
}

enum RuleError: LocalizedError {
    case invalidHost, duplicateHost, invalidProfile

    var errorDescription: String? {
        switch self {
        case .invalidHost: "Enter a valid web host or paste an http or https URL."
        case .duplicateHost: "A rule for this host already exists."
        case .invalidProfile: "Choose an available browser profile."
        }
    }
}

enum RuleRouting {
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
        return rules.first { $0.enabled && $0.host == normalized }
    }

    static func availableProfile(for rule: RoutingRule, profiles: [BrowserProfile], directoryExists: (BrowserProfile) -> Bool = { profile in
        guard profile.browser != .safari, let directory = profile.directory, let state = profile.browser.localStateURL else { return true }
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: state.deletingLastPathComponent().appendingPathComponent(directory).path, isDirectory: &isDirectory) && isDirectory.boolValue
    }) -> BrowserProfile? {
        profiles.first { $0.id == rule.profileID && directoryExists($0) }
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
                  BrowserProfile.validID(rule.profileID), !seen.contains(rule.host) else { return false }
            seen.insert(rule.host)
            return true
        }
    }

    func save(_ rules: [RoutingRule]) throws {
        var seen = Set<String>()
        for rule in rules {
            guard RuleRouting.normalizedHost(rule.host) == rule.host else { throw RuleError.invalidHost }
            guard BrowserProfile.validID(rule.profileID) else { throw RuleError.invalidProfile }
            guard seen.insert(rule.host).inserted else { throw RuleError.duplicateHost }
        }
        defaults.set(try JSONEncoder().encode(rules), forKey: key)
    }
}
