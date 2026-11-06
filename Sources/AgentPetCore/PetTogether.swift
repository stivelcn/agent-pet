import Foundation

public enum PetTogetherMode: String, Codable, Sendable, CaseIterable {
    case visit, work
}

/// Authoritative shared session, separate from unread messages and gesture replay receipts.
public struct PetTogetherSession: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var clientID: String
    public var pairID: String
    public var initiatorID: String
    public var mode: PetTogetherMode
    public var status: String
    public var createdAt: Double
    public var startedAt: Double?
    public var expiresAt: Double
    public var restAt: Double?
    public var endedAt: Double?
    public var endedBy: String?
    public var reason: String?

    public init(id: String, clientID: String, pairID: String, initiatorID: String,
                mode: PetTogetherMode, status: String, createdAt: Double,
                startedAt: Double? = nil, expiresAt: Double, restAt: Double? = nil,
                endedAt: Double? = nil, endedBy: String? = nil, reason: String? = nil) {
        self.id = id; self.clientID = clientID; self.pairID = pairID; self.initiatorID = initiatorID
        self.mode = mode; self.status = status; self.createdAt = createdAt; self.startedAt = startedAt
        self.expiresAt = expiresAt; self.restAt = restAt; self.endedAt = endedAt
        self.endedBy = endedBy; self.reason = reason
    }

    public func isPending(at now: Double) -> Bool { status == "pending" && expiresAt > now }
    public func isActive(at now: Double) -> Bool { status == "active" && startedAt != nil && expiresAt > now }
    public func isResting(at now: Double) -> Bool { isActive(at: now) && mode == .work && (restAt ?? .infinity) <= now }
    public func isAway(deviceID: String?, at now: Double) -> Bool {
        isActive(at: now) && mode == .visit && initiatorID == deviceID
    }
    public func showsCompanion(deviceID: String?, at now: Double) -> Bool {
        isActive(at: now) && (mode == .work || initiatorID != deviceID)
    }
}

/// Durable requests and stop commands reuse their identity after a lost response or restart.
public struct PetTogetherCommand: Codable, Equatable, Sendable {
    public var pairID: String
    public var clientID: String
    public var mode: PetTogetherMode?
    public var sessionID: String?
    public var action: String?
    public var createdAt: Double
    public init(pairID: String, mode: PetTogetherMode? = nil, sessionID: String? = nil,
                action: String? = nil, createdAt: Double) {
        self.pairID = pairID; clientID = UUID().uuidString; self.mode = mode
        self.sessionID = sessionID; self.action = action; self.createdAt = createdAt
    }
    public var stopsPresentation: Bool { ["end", "decline", "cancel"].contains(action ?? "") }
    public func isExpired(at now: Double) -> Bool { !stopsPresentation && now - createdAt >= 120 }
}
