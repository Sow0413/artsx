import Foundation

public enum GNSSLinkState: String, Sendable, Equatable {
    case idle
    case connecting
    case live
    case reconnecting

    public var label: String {
        switch self {
        case .idle: return ""
        case .connecting: return "GNSS につないでいます"
        case .live: return "GNSS 接続中"
        case .reconnecting: return "GNSS が切れました。つなぎ直しています。"
        }
    }
}

public struct GNSSChoice: Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name.isEmpty ? id : name
    }
}

/// 機器との口。接続の待ちは、この口の中で画面を止めない。
public protocol GNSSRadio: AnyObject {
    var hasSavedDevice: Bool { get }
    var onConnect: (() -> Void)? { get set }
    var onDrop: (() -> Void)? { get set }
    var onDiscover: ((GNSSChoice) -> Void)? { get set }
    func start()
    func scan()
    func connect(_ id: String)
    func stop()
}

/// 保存していないときは何もしない。Playgrounds と、機器を選ぶ前。
public final class IdleGNSSRadio: GNSSRadio {
    public var hasSavedDevice: Bool { false }
    public var onConnect: (() -> Void)?
    public var onDrop: (() -> Void)?
    public var onDiscover: ((GNSSChoice) -> Void)?

    public init() {}

    public func start() {}
    public func scan() {}
    public func connect(_ id: String) {}
    public func stop() {}
}

/// 切れたら、画面のスレッドを待たせずにつなぎ直す。iPhone / iPad の前面だけ。
public final class GNSSLink {
    public static let retrySeconds = 2.0

    public private(set) var state: GNSSLinkState = .idle
    public var onState: ((GNSSLinkState) -> Void)?
    public var onDiscover: ((GNSSChoice) -> Void)?

    private let radio: GNSSRadio
    private let retryDelay: TimeInterval
    private let queue: DispatchQueue
    private var stopped = false
    private var generation = 0

    public init(radio: GNSSRadio, retryDelay: TimeInterval = GNSSLink.retrySeconds, queue: DispatchQueue = DispatchQueue(label: "survey.gnss")) {
        self.radio = radio
        self.retryDelay = retryDelay
        self.queue = queue
        radio.onConnect = { [weak self] in
            guard let link = self else { return }
            link.queue.async { [weak link] in
                link?.connected()
            }
        }
        radio.onDrop = { [weak self] in
            guard let link = self else { return }
            link.queue.async { [weak link] in
                link?.dropped()
            }
        }
        radio.onDiscover = { [weak self] choice in
            self?.onDiscover?(choice)
        }
    }

    /// 以前選んだ機器があるときだけ、起動時につなぐ。
    public func resume() {
        queue.async {
            self.stopped = false
            guard self.radio.hasSavedDevice else {
                self.set(.idle)
                return
            }
            self.set(.connecting)
            self.radio.start()
        }
    }

    public func scan() {
        queue.async {
            self.stopped = false
            self.generation += 1
            self.set(.connecting)
            self.radio.scan()
        }
    }

    public func choose(_ id: String) {
        queue.async {
            self.stopped = false
            self.generation += 1
            self.set(.connecting)
            self.radio.connect(id)
        }
    }

    public func pause() {
        queue.async {
            self.stopped = true
            self.generation += 1
            self.radio.stop()
            self.set(.idle)
        }
    }

    private func connected() {
        guard !stopped else { return }
        set(.live)
    }

    private func dropped() {
        guard !stopped else { return }
        set(.reconnecting)
        generation += 1
        let ticket = generation
        queue.asyncAfter(deadline: .now() + retryDelay) { [weak self] in
            guard let self, !self.stopped, ticket == self.generation else { return }
            self.set(.connecting)
            self.radio.start()
        }
    }

    private func set(_ next: GNSSLinkState) {
        state = next
        let notify = onState
        DispatchQueue.main.async {
            notify?(next)
        }
    }
}
