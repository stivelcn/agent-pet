import Foundation

public enum PetRelayIcon: String, Codable, CaseIterable, Identifiable, Sendable {
    case heart, water, meal, rest, hug, look
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .heart: "❤️"
        case .water: "💧"
        case .meal: "🍚"
        case .rest: "☕"
        case .hug: "🤗"
        case .look: "👀"
        }
    }
    public var labelKey: String {
        switch self {
        case .heart: "Send a heart"
        case .water: "Drink some water"
        case .meal: "Time to eat"
        case .rest: "Take a rest"
        case .hug: "Send a hug"
        case .look: "Look over here"
        }
    }
}

public enum PetRelayGesture: String, Codable, CaseIterable, Identifiable, Sendable {
    case poke, hug, peek
    public var id: String { rawValue }
    public var labelKey: String {
        switch self { case .poke: "Poke"; case .hug: "Hug"; case .peek: "Peek" }
    }
    public var symbol: String {
        switch self { case .poke: "👉"; case .hug: "🤗"; case .peek: "👀" }
    }
}

public struct PetRelayPetProfile: Codable, Equatable, Sendable {
    public var name: String
    public var builtinID: String?
    public var thumbnailPNG: String?
    public var interactionVersion: Int?
    public init(name: String, builtinID: String? = nil, thumbnailPNG: String? = nil, interactionVersion: Int? = 1) {
        self.name = name; self.builtinID = builtinID; self.thumbnailPNG = thumbnailPNG
        self.interactionVersion = interactionVersion
    }
}

public struct PetRelayPair: Codable, Equatable, Sendable {
    public var id: String
    public var peerName: String
    public var peerPet: PetRelayPetProfile?
    public init(id: String, peerName: String, peerPet: PetRelayPetProfile? = nil) {
        self.id = id; self.peerName = peerName; self.peerPet = peerPet
    }
}

public struct PetRelayInvitation: Codable, Equatable, Sendable {
    public var code: String
    public var expiresAt: Double
    public var isCreator: Bool
    public var peerName: String?
    public var awaitingConfirmation: Bool
}

public struct PetRelayMessage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var clientID: String
    public var pairID: String
    public var senderName: String
    public var text: String?
    public var icon: PetRelayIcon?
    public var replyTo: String?
    public var createdAt: Double
    public var deliveredAt: Double?
    public var handledAt: Double?
    // Raw string lets older clients retain future gesture kinds without losing the inbox.
    public var gesture: String?
    public var expiresAt: Double?
    public var senderPet: PetRelayPetProfile?
    public var interaction: PetRelayGesture? { gesture.flatMap(PetRelayGesture.init(rawValue:)) }
    public var content: String { text ?? icon?.symbol ?? interaction?.symbol ?? "✨" }
    public init(id: String, clientID: String, pairID: String, senderName: String,
                text: String? = nil, icon: PetRelayIcon? = nil, replyTo: String? = nil,
                createdAt: Double, deliveredAt: Double? = nil, handledAt: Double? = nil,
                gesture: String? = nil, expiresAt: Double? = nil, senderPet: PetRelayPetProfile? = nil) {
        self.id = id; self.clientID = clientID; self.pairID = pairID; self.senderName = senderName
        self.text = text; self.icon = icon; self.replyTo = replyTo; self.createdAt = createdAt
        self.deliveredAt = deliveredAt; self.handledAt = handledAt
        self.gesture = gesture; self.expiresAt = expiresAt; self.senderPet = senderPet
    }
}

public struct PetRelaySnapshot: Codable, Sendable {
    public var deviceID: String
    public var name: String
    public var pair: PetRelayPair?
    public var invitation: PetRelayInvitation?
    public var incoming: [PetRelayMessage]
    public var sent: [PetRelayMessage]
    public var capabilities: [String]?
    public var pet: PetRelayPetProfile?
    public init(deviceID: String, name: String, pair: PetRelayPair? = nil,
                invitation: PetRelayInvitation? = nil, incoming: [PetRelayMessage] = [], sent: [PetRelayMessage] = [],
                capabilities: [String]? = nil, pet: PetRelayPetProfile? = nil) {
        self.deviceID = deviceID; self.name = name; self.pair = pair; self.invitation = invitation
        self.incoming = incoming; self.sent = sent
        self.capabilities = capabilities; self.pet = pet
    }
}

/// Durable idempotency key: a timed-out send is retained and retried with the SAME identity.
/// It can never be reassigned to a different pairing.
public struct PetRelayDraft: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var pairID: String
    public var text: String?
    public var icon: PetRelayIcon?
    public var replyTo: String?
    public var gesture: PetRelayGesture?
    public var expiresAt: Double?
    public init(pairID: String, text: String? = nil, icon: PetRelayIcon? = nil, replyTo: String? = nil,
                gesture: PetRelayGesture? = nil, expiresAt: Double? = nil) {
        id = UUID().uuidString; self.pairID = pairID; self.text = text; self.icon = icon; self.replyTo = replyTo
        self.gesture = gesture; self.expiresAt = expiresAt
    }
    public var content: String { text ?? icon?.symbol ?? gesture?.symbol ?? "" }
    public func isExpired(at now: Double) -> Bool {
        gesture != nil && (expiresAt == nil || expiresAt! <= now)
    }
}

public enum PetRelayValidation {
    public static func normalizedCode(_ input: String) -> String {
        input.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
    public static func validCode(_ input: String) -> Bool {
        let code = normalizedCode(input)
        let bytes = Array(code.utf8)
        return bytes.count == 6 && bytes.allSatisfy { (65...90).contains($0) || (48...57).contains($0) }
            && bytes.contains { (65...90).contains($0) } && bytes.contains { (48...57).contains($0) }
    }
    public static func trimmedText(_ input: String) -> String { input.trimmingCharacters(in: .whitespacesAndNewlines) }
    public static func validText(_ input: String) -> Bool {
        let text = trimmedText(input)
        return !text.isEmpty && text.count <= 20 && text.utf8.count <= 1024
            && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) && $0.value != 0x200D }
            && !text.contains("\u{2028}") && !text.contains("\u{2029}")
    }
}

/// Private messages are independent of completion notices, companion archives and skin IDs.
/// Server omissions (e.g. unpairing) NEVER clear a locally unread message.
public struct PetRelayMailbox: Codable, Equatable, Sendable {
    public var deviceID: String?
    public var name = "Pet friend"
    public var pair: PetRelayPair?
    public var invitation: PetRelayInvitation?
    public var incoming: [PetRelayMessage] = []
    public var sent: [PetRelayMessage] = []
    public var outbox: [PetRelayDraft] = []
    public var handled: Set<String> = []
    public var delivered: Set<String> = []
    public var capabilities: [String]?
    public var pet: PetRelayPetProfile?
    public var playedInteractions: Set<String>?
    public init() {}

    public mutating func merge(_ snapshot: PetRelaySnapshot) {
        // The credential/installation owns the mailbox, not the selected pet.
        guard deviceID == nil || deviceID == snapshot.deviceID else { return }
        deviceID = snapshot.deviceID; name = snapshot.name
        pair = snapshot.pair; invitation = snapshot.invitation; sent = snapshot.sent
        capabilities = snapshot.capabilities; pet = snapshot.pet
        for message in snapshot.incoming where !handled.contains(message.id) {
            if let index = incoming.firstIndex(where: { $0.id == message.id }) { incoming[index] = message }
            else { incoming.append(message) }
            if message.deliveredAt == nil { delivered.insert(message.id) }
        }
        incoming.sort { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        // A successful retry can be recognized even if the first HTTP response was lost.
        let accepted = Set(snapshot.sent.map(\.clientID))
        let completed = outbox.filter { accepted.contains($0.id) }
        for draft in completed { accept(draft.id) }
    }

    public mutating func dismiss(_ id: String) {
        incoming.removeAll { $0.id == id }
        delivered.remove(id)
        handled.insert(id)
    }

    public mutating func accept(_ clientID: String) {
        guard let draft = outbox.first(where: { $0.id == clientID }) else { return }
        if let parent = draft.replyTo { dismiss(parent) }
        outbox.removeAll { $0.id == clientID }
    }

    /// Consume before display, including expired/hidden events. A restart never replays a visit.
    /// Unread messages stay available for an explicit reply or dismissal.
    public mutating func consumeInteractions(at now: Double, canAnimate: Bool) -> PetRelayMessage? {
        let seen = playedInteractions ?? []
        let new = incoming.filter { $0.gesture != nil && !seen.contains($0.id) }
        playedInteractions = Set(incoming.filter { $0.gesture != nil }.map(\.id))
        guard canAnimate else { return nil }
        return new.last {
            $0.interaction != nil && $0.pairID == pair?.id && $0.createdAt <= now + 5
                && now - $0.createdAt <= 30 && ($0.expiresAt ?? 0) > now
        }
    }
}
