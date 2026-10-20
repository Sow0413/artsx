import Foundation

/// どの端末も、見通しの届く範囲で中継する。宛先が自分でなくても次へ渡す。
public enum MeshDuty {
    public enum Presence: String, Sendable {
        case active
        case inactive
        case background
    }

    public static let lowBatteryPercent = 20
    public static let sparingRelaySeconds: TimeInterval = 60
    public static let everyoneNote = "どの端末も、見通しの届く範囲で、自分宛てでない通も次へ渡します。"
    public static let rangeNote = "届く範囲は、近くの端末どうしが見通せる距離です。"
    public static let sparingLabel = "中継を控えめにしています"
    public static let sparingNote = "電池が20%を下回ると、SOS・音声・文字だけを渡し、再送を60秒に延ばします。充電中は通常どおりです。"
    public static let stoppedLabel = "中継停止中"
    public static let stoppedReason = "アプリが前面にありません。戻すと中継を再開します。"
    public static let locationBackgroundNote = "位置情報のバックグラウンドは、GPSの更新を続けるだけで、近くの端末とのセッションは維持しません。中継のためには使いません。"
    public static let pttStandbyNote = "PTTの待受は、P510からの音声でアプリを短く起こします。近くの端末への中継は、その起床では続きません。"

    public static func relaying(_ presence: Presence) -> Bool {
        presence == .active
    }

    public static func sparing(batteryPercent: Int?, charging: Bool) -> Bool {
        guard !charging, let batteryPercent else { return false }
        return batteryPercent < lowBatteryPercent
    }

    /// 控えめな端末が、受け取った通を次へ渡すか。自分が作った通の初回送信は別。
    public static func forwards(_ kind: BucketKind, batteryPercent: Int?, charging: Bool) -> Bool {
        guard sparing(batteryPercent: batteryPercent, charging: charging) else { return true }
        switch kind {
        case .sos, .radio, .text:
            return true
        case .position, .site, .passage:
            return false
        }
    }

    public static func relayInterval(batteryPercent: Int?, charging: Bool, saver: Bool) -> TimeInterval {
        if sparing(batteryPercent: batteryPercent, charging: charging) {
            return sparingRelaySeconds
        }
        return BatterySaver.relayInterval(enabled: saver)
    }

    /// 宛先が自分でも他人でも、前面にいて上限前なら渡す。電池が少ないときは種類で絞る。
    public static func choice(
        addressedTo: String?,
        selfID: String,
        kind: BucketKind,
        hops: Int,
        hopLimit: Int,
        batteryPercent: Int?,
        charging: Bool,
        presence: Presence
    ) -> MeshRelayChoice {
        guard relaying(presence) else { return .stopped }
        guard hops < hopLimit else { return .keep }
        guard forwards(kind, batteryPercent: batteryPercent, charging: charging) else { return .spare }
        if addressedTo == selfID {
            return .forward
        }
        return .forward
    }

    public static func radioEnvelopeID(_ packet: RadioPacket) -> UUID {
        var payload = Data()
        let uuid = packet.utteranceID.uuid
        payload.append(contentsOf: [uuid.0, uuid.1, uuid.2, uuid.3, uuid.4, uuid.5, uuid.6, uuid.7, uuid.8, uuid.9, uuid.10, uuid.11, uuid.12, uuid.13, uuid.14, uuid.15])
        payload.append(contentsOf: packet.kind.rawValue.utf8)
        var millis = Int64((packet.sentAt.timeIntervalSince1970 * 1000).rounded())
        payload.append(contentsOf: Swift.withUnsafeBytes(of: &millis) { Data($0) })
        if let audio = packet.audio {
            var count = UInt32(audio.count).littleEndian
            payload.append(contentsOf: Swift.withUnsafeBytes(of: &count) { Data($0) })
            payload.append(audio.prefix(32))
        }
        let digest = SHA256.digest(payload)
        return UUID(uuid: (
            digest[0], digest[1], digest[2], digest[3],
            digest[4], digest[5], digest[6], digest[7],
            digest[8], digest[9], digest[10], digest[11],
            digest[12], digest[13], digest[14], digest[15]
        ))
    }

    public static func radioFingerprint(_ packet: RadioPacket) -> String {
        "\(packet.utteranceID.uuidString)|\(packet.kind.rawValue)|\(Int64((packet.sentAt.timeIntervalSince1970 * 1000).rounded()))|\(packet.audio?.count ?? 0)"
    }
}

public enum MeshRelayChoice: Equatable, Sendable {
    case forward
    case keep
    case spare
    case stopped
}
