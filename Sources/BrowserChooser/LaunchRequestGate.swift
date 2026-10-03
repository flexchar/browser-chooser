import Foundation

struct LaunchRequestGate {
    private(set) var activeRequestID: UUID?

    func isActive(_ requestID: UUID) -> Bool { activeRequestID == requestID }

    mutating func begin(_ requestID: UUID) -> Bool {
        guard activeRequestID == nil else { return false }
        activeRequestID = requestID
        return true
    }

    mutating func finish(_ requestID: UUID) -> Bool {
        guard activeRequestID == requestID else { return false }
        activeRequestID = nil
        return true
    }
}
