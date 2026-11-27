/// Encapsulates outbound MWB auto-reconnect state, suppression, and retry budget.
public struct MWBReconnectPolicy: Equatable, Sendable {
    public enum Decision: Equatable, Sendable {
        case skip
        case schedule(host: String, messagePort: UInt16, clipboardPort: UInt16, attempt: Int)
        case exhausted(host: String, maxAttempts: Int)
    }

    public private(set) var lastHost: String?
    public private(set) var lastMessagePort: UInt16?
    public private(set) var lastClipboardPort: UInt16?
    public private(set) var attempts = 0
    public let maxAttempts: Int
    private var suppressedSessions: Set<ObjectIdentifier> = []

    public init(maxAttempts: Int = 3) {
        self.maxAttempts = maxAttempts
    }

    public mutating func recordConnectTarget(host: String, messagePort: UInt16, clipboardPort: UInt16) {
        self.lastHost = host
        self.lastMessagePort = messagePort
        self.lastClipboardPort = clipboardPort
        self.attempts = 0
    }

    public mutating func markConnected() {
        self.attempts = 0
    }

    public mutating func suppressReconnect(for sessionID: ObjectIdentifier) {
        self.suppressedSessions.insert(sessionID)
    }

    public mutating func reset() {
        self.attempts = 0
        self.lastHost = nil
        self.lastMessagePort = nil
        self.lastClipboardPort = nil
        self.suppressedSessions.removeAll()
    }

    public mutating func evaluateDisconnect(
        sessionID: ObjectIdentifier,
        isOutbound: Bool,
        kind: MWBSessionKind,
        remainingMessageSessions: Int
    ) -> Decision {
        guard isOutbound, kind == .message else { return .skip }
        if self.suppressedSessions.remove(sessionID) != nil {
            return .skip
        }
        guard remainingMessageSessions == 0,
            let host = self.lastHost,
            let msgPort = self.lastMessagePort,
            let clipPort = self.lastClipboardPort
        else { return .skip }

        if self.attempts >= self.maxAttempts {
            return .exhausted(host: host, maxAttempts: self.maxAttempts)
        }

        self.attempts += 1
        return .schedule(
            host: host,
            messagePort: msgPort,
            clipboardPort: clipPort,
            attempt: self.attempts)
    }
}
