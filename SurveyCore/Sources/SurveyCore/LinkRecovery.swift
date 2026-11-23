import Foundation

/// 再接続の待ち。1, 2, 4, 8 秒、以降は 15 秒。
public struct LinkBackoff: Equatable, Sendable {
    public static let sequence: [TimeInterval] = [1, 2, 4, 8, 15]
    public private(set) var index = 0

    public init() {}

    public var next: TimeInterval {
        Self.sequence[min(index, Self.sequence.count - 1)]
    }

    public mutating func take() -> TimeInterval {
        let delay = next
        index = min(index + 1, Self.sequence.count - 1)
        return delay
    }

    public mutating func reset() {
        index = 0
    }
}

/// つながっているあいだ、最後の受信から limit を超えたら途切れ。
public struct LinkStall: Equatable, Sendable {
    public var limit: TimeInterval
    public private(set) var lastAt: TimeInterval?

    public init(limit: TimeInterval = 5) {
        self.limit = limit
    }

    public mutating func mark(at now: TimeInterval) {
        lastAt = now
    }

    public mutating func reset() {
        lastAt = nil
    }

    public func isStalled(at now: TimeInterval, connected: Bool) -> Bool {
        guard connected, let lastAt else { return false }
        return now - lastAt > limit
    }
}

public enum LinkClock {
    public static func text(_ time: TimeInterval, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSinceReferenceDate: time))
    }
}

public struct LinkHealth: Equatable, Sendable {
    public private(set) var drops = 0
    public private(set) var lastReason = ""
    public private(set) var lastAt: TimeInterval?
    public private(set) var reconnecting = false

    public init() {}

    public mutating func dropped(reason: String, at now: TimeInterval) {
        drops += 1
        lastReason = reason
        lastAt = now
        reconnecting = true
    }

    public mutating func restored() {
        reconnecting = false
    }

    public func reconnectingText(time: String) -> String {
        let reason = lastReason.isEmpty ? "" : " \(lastReason)"
        let when = time.isEmpty ? "" : " \(time)"
        return "再接続中 (\(drops)回目)\(reason)\(when)"
    }

    public func settledSuffix(time: String) -> String {
        guard drops > 0, !reconnecting else { return "" }
        let when = time.isEmpty ? "" : " \(time)"
        return "　切断\(drops)回 \(lastReason)\(when)"
    }
}

/// 古いソケットを閉じ終わるまで、次を開かない。
public struct ExclusiveSocket: Equatable, Sendable {
    public private(set) var openID: Int?
    public private(set) var closingID: Int?
    private var nextID = 0

    public init() {}

    public var isOpen: Bool { openID != nil }
    public var isClosing: Bool { closingID != nil }

    public mutating func openFresh() -> Int? {
        guard openID == nil, closingID == nil else { return nil }
        nextID += 1
        openID = nextID
        return nextID
    }

    public mutating func close() -> Int? {
        guard let id = openID else { return nil }
        openID = nil
        closingID = id
        return id
    }

    /// 閉じ終わった印だけ付ける。新しいソケットはまだ開かない。
    public mutating func finishClose(_ id: Int) -> Bool {
        guard closingID == id else { return false }
        closingID = nil
        return true
    }
}

/// NTRIP を1本だけつなぎ直す。補正がオンのあいだは待ち時間を伸ばしながら続ける。
public struct NTRIPReconnect: Equatable, Sendable {
    public var backoff = LinkBackoff()
    public var stall = LinkStall(limit: 5)
    public var socket = ExclusiveSocket()
    public var health = LinkHealth()
    public var correctionsEnabled = true
    public private(set) var streaming = false
    public private(set) var recovering = false
    public private(set) var closeFinished = true
    public private(set) var dialect: NTRIPDialect = .v2
    public private(set) var usedFallback = false
    public private(set) var everStreamed = false

    public init() {}

    public mutating func start() -> Int? {
        socket = ExclusiveSocket()
        backoff.reset()
        stall.reset()
        streaming = false
        recovering = false
        closeFinished = true
        dialect = .v2
        usedFallback = false
        everStreamed = false
        health = LinkHealth()
        return socket.openFresh()
    }

    public mutating func streamBegan(at now: TimeInterval) {
        streaming = true
        everStreamed = true
        recovering = false
        stall.mark(at: now)
        backoff.reset()
        health.restored()
    }

    public mutating func bytes(at now: TimeInterval) {
        stall.mark(at: now)
    }

    public func stalled(at now: TimeInterval) -> Bool {
        stall.isStalled(at: now, connected: streaming)
    }

    /// 失敗を1回数え、古いソケットを閉じる。戻り値は次に開くまでの秒。既にやり直し中なら nil。
    public mutating func lost(reason: String, at now: TimeInterval, dialectHint: Bool) -> TimeInterval? {
        guard correctionsEnabled else {
            _ = socket.close()
            streaming = false
            recovering = false
            return nil
        }
        if recovering { return nil }
        recovering = true
        if dialectHint, !usedFallback {
            dialect = dialect == .v2 ? .v1 : .v2
            usedFallback = true
        }
        streaming = false
        stall.reset()
        health.dropped(reason: reason, at: now)
        if socket.isOpen {
            _ = socket.close()
            closeFinished = false
        } else {
            closeFinished = !socket.isClosing
        }
        return backoff.take()
    }

    public mutating func noteClosed(_ id: Int) {
        if socket.finishClose(id) {
            closeFinished = true
        }
    }

    /// 閉じ終わり、かつやり直し中のときだけ、新しい1本を開く。
    public mutating func readyToOpen() -> Int? {
        guard correctionsEnabled, recovering, closeFinished, !socket.isOpen, !socket.isClosing else { return nil }
        recovering = false
        return socket.openFresh()
    }
}

/// ViDoc は同じ個体へ戻し、戻るたびに start からやり直す。
public struct ViDocRecovery: Equatable, Sendable {
    public private(set) var identifier: String?
    public private(set) var bootRuns = 0
    public var stall = LinkStall(limit: 5)
    public private(set) var linked = false
    public var health = LinkHealth()

    public init() {}

    public mutating func remember(_ id: String) {
        identifier = id
    }

    public mutating func watch(at now: TimeInterval) {
        linked = true
        stall.mark(at: now)
    }

    public mutating func linkUp(at now: TimeInterval) {
        linked = true
        bootRuns += 1
        health.restored()
        if stall.lastAt == nil { stall.mark(at: now) }
    }

    public mutating func notify(at now: TimeInterval) {
        stall.mark(at: now)
    }

    /// retrieve を先に試し、個体が戻らなければ scan する。boot は linkUp で数える。
    public mutating func recover(reason: String, at now: TimeInterval, retrieved: Bool) -> [String] {
        linked = false
        stall.reset()
        health.dropped(reason: reason, at: now)
        var steps: [String] = []
        if identifier != nil { steps.append("retrieve") }
        if identifier == nil || !retrieved { steps.append("scan") }
        return steps
    }
}
