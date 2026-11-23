import Foundation

/// 再接続の待ち。通常は 1, 2, 4, 8 秒、以降は 15 秒。503 と到達不能は 10, 20, 30 秒。
public struct LinkBackoff: Equatable, Sendable {
    public static let sequence: [TimeInterval] = [1, 2, 4, 8, 15]
    public static let sessionHold: [TimeInterval] = [10, 20, 30]
    public private(set) var index = 0
    public var slow = false

    public init() {}

    public var next: TimeInterval {
        let steps = slow ? Self.sessionHold : Self.sequence
        return steps[min(index, steps.count - 1)]
    }

    public mutating func take() -> TimeInterval {
        let delay = next
        index = min(index + 1, Self.sequence.count - 1)
        return delay
    }

    public mutating func reset() {
        index = 0
        slow = false
    }

    public mutating func useSessionHold() {
        if !slow { index = 0 }
        slow = true
    }
}

public enum LinkDropKind: String, Equatable, Sendable {
    case ntrip
    case vidoc
    case correctionLag
    case openSky

    public var label: String {
        switch self {
        case .ntrip: return "NTRIP"
        case .vidoc: return "ViDoc"
        case .correctionLag: return "補正遅れ"
        case .openSky: return "上空"
        }
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
    public private(set) var lastKind: LinkDropKind = .ntrip
    public private(set) var lastReason = ""
    public private(set) var lastAt: TimeInterval?
    public private(set) var reconnecting = false

    public init() {}

    public mutating func dropped(kind: LinkDropKind, reason: String, at now: TimeInterval) {
        drops += 1
        lastKind = kind
        lastReason = reason
        lastAt = now
        reconnecting = true
    }

    public mutating func restored() {
        reconnecting = false
    }

    public func reconnectingText(time: String, ggaAge: String? = nil) -> String {
        let reason = lastReason.isEmpty ? "" : " \(lastReason)"
        let when = time.isEmpty ? "" : " \(time)"
        let age = ggaAge.map { " GGA \($0)" } ?? ""
        return "再接続中 (\(drops)回目) \(lastKind.label)\(reason)\(when)\(age)"
    }

    public func settledSuffix(time: String) -> String {
        guard drops > 0, !reconnecting else { return "" }
        let when = time.isEmpty ? "" : " \(time)"
        return "　切断\(drops)回 \(lastKind.label) \(lastReason)\(when)"
    }
}

/// 衛星が急に減ったら上空が開けていない、と出す。
public struct SkyWatch: Equatable, Sendable {
    public private(set) var previous: Int?
    public private(set) var count: Int?
    public private(set) var lost = false

    public init() {}

    @discardableResult
    public mutating func observe(_ satellites: Int?) -> Bool {
        count = satellites
        defer { if let satellites { previous = satellites } }
        guard let satellites, let previous else { return false }
        if previous >= 8, satellites < 5 {
            lost = true
            return true
        }
        if satellites >= 8 { lost = false }
        return false
    }

    public var note: String {
        guard lost else { return "" }
        return "上空 衛星\(count.map(String.init) ?? "—")"
    }
}

/// 再接続のあとは FIX に戻るまで基準点を残さない。
public struct GCPFixHold: Equatable, Sendable {
    public private(set) var waitingForFix = false

    public init() {}

    public mutating func noteReconnect() {
        waitingForFix = true
    }

    public mutating func observe(_ quality: FixQuality) {
        if quality == .rtkFix { waitingForFix = false }
    }

    public var allowsRecording: Bool { !waitingForFix }
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
    public mutating func lost(reason: String, at now: TimeInterval, dialectHint: Bool, kind: LinkDropKind = .ntrip, slow: Bool = false) -> TimeInterval? {
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
        if slow {
            backoff.useSessionHold()
        }
        streaming = false
        stall.reset()
        health.dropped(kind: kind, reason: reason, at: now)
        if socket.isOpen {
            _ = socket.close()
            closeFinished = false
        } else {
            closeFinished = !socket.isClosing
        }
        return backoff.take()
    }

    /// 経路が変わったら、待ちを伸ばさず、閉じたあとすぐ1本だけ開き直す。
    public mutating func rebind(reason: String, at now: TimeInterval) -> TimeInterval {
        recovering = true
        streaming = false
        stall.reset()
        health.dropped(kind: .ntrip, reason: reason, at: now)
        if socket.isOpen {
            _ = socket.close()
            closeFinished = false
        } else {
            closeFinished = !socket.isClosing
        }
        return 0
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
        health.dropped(kind: .vidoc, reason: reason, at: now)
        var steps: [String] = []
        if identifier != nil { steps.append("retrieve") }
        if identifier == nil || !retrieved { steps.append("scan") }
        return steps
    }
}
