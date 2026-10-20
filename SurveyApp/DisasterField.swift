import Foundation
import SurveyCore
#if canImport(Network)
import Network
#endif

extension FieldModel {
    func setDisasterMode(_ enabled: Bool) {
        guard extras.disaster else {
            disasterMode = false
            disasterMessage = "おまけの災害派遣をオンにしてから使います。"
            return
        }
        guard drawing.project != nil else {
            disasterMode = false
            disasterMessage = "プロジェクトを開いてから災害派遣にします。"
            return
        }
        disasterMode = enabled
        storeDisasterSettings()
        if enabled {
            disasterMessage = "災害派遣です。圏外のまま、近くの端末へ中継します。"
            noteDisasterMotion(force: true)
        } else {
            disasterMessage = "災害派遣を止めました。記録はそのまま残します。"
        }
    }

    func setBatterySaver(_ enabled: Bool) {
        guard drawing.project != nil else {
            batterySaver = false
            disasterMessage = "プロジェクトを開いてから電池節約にします。"
            return
        }
        batterySaver = enabled
        storeDisasterSettings()
        disasterMessage = enabled ? BatterySaver.note : "電池節約を止めました。"
    }

    func recordDisasterSite(
        kind: DisasterKind,
        length: Double?,
        width: Double?,
        height: Double?,
        note: String,
        photo: Data?
    ) {
        guard disasterMode else {
            disasterMessage = "災害派遣をオンにしてから記録します。"
            return
        }
        guard let project = drawing.project else {
            disasterMessage = "プロジェクトを開いてから記録します。"
            return
        }
        guard let position = workingReading.position, position.isPlottable else {
            disasterMessage = "位置がまだありません。"
            return
        }
        let id = UUID()
        let photoFile = try? DisasterBook.savePhoto(photo ?? Data(), id: id, projectName: project.name, at: drawing.projectsRoot)
        do {
            let site = try DisasterEntry.site(
                id: id,
                at: Date(),
                kind: kind,
                latitudeDegrees: position.latitudeDegrees,
                longitudeDegrees: position.longitudeDegrees,
                horizontalAccuracyMeters: position.horizontalAccuracyMeters,
                lengthMeters: length,
                widthMeters: width,
                heightMeters: height,
                note: note,
                photoFile: photoFile,
                author: crew.displayName
            )
            guard try DisasterBook.appendSite(site, projectName: project.name, at: drawing.projectsRoot) else { return }
            reloadDisaster()
            publishDisaster(kind: .site, site: site)
            disasterMessage = "\(site.kind.label)を記録しました。"
        } catch DisasterEntryError.badMeasure {
            disasterMessage = "延長・幅・高さは0以上のメートルで入れてください。"
        } catch {
            disasterMessage = "被災箇所を書けませんでした。"
        }
    }

    func markRoadClosed() {
        guard disasterMode else {
            disasterMessage = "災害派遣をオンにしてから記録します。"
            return
        }
        guard let project = drawing.project else {
            disasterMessage = "プロジェクトを開いてから記録します。"
            return
        }
        guard let position = workingReading.position, position.isPlottable else {
            disasterMessage = "位置がまだありません。"
            return
        }
        guard let sample = DisasterEntry.passage(
            at: Date(),
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            state: .closed,
            author: crew.displayName
        ) else { return }
        storePassage(sample, projectName: project.name)
        disasterMessage = "ここで止まった、と地図に出しました。"
    }

    func sendDisasterText(_ body: String) {
        guard disasterMode else {
            disasterMessage = "災害派遣をオンにしてから送ります。"
            return
        }
        guard let project = drawing.project else {
            disasterMessage = "プロジェクトを開いてから送ります。"
            return
        }
        do {
            let text = try DisasterEntry.text(at: Date(), author: crew.displayName, body: body)
            guard try DisasterBook.appendText(text, projectName: project.name, at: drawing.projectsRoot) else { return }
            reloadDisaster()
            publishDisaster(kind: .text, text: text)
            disasterMessage = "文字を中継に出しました。"
        } catch {
            disasterMessage = "空の文字は送れません。"
        }
    }

    func exportDisasterReports() {
        guard let project = drawing.project else {
            disasterMessage = "プロジェクトを開いてから書き出します。"
            return
        }
        do {
            let exported = try DisasterBook.export(projectName: project.name, at: drawing.projectsRoot, generatedAt: Date())
            disasterMessage = "\(exported.pdf)、\(exported.csv)、\(exported.ledger) を書きました。"
        } catch {
            disasterMessage = "報告書を書けませんでした。"
        }
    }

    func flushDisasterNow() {
        guard let project = drawing.project else { return }
        if !disasterRelay.isReachable {
            disasterMessage = "P510まで届いていません。衛星回線でも、届いてからまとめて送ります。"
            return
        }
        let batch = DisasterBook.pending(projectID: project.id, projectName: project.name, at: drawing.projectsRoot)
        guard !batch.isEmpty else {
            disasterMessage = "送るものはありません。"
            return
        }
        guard disasterRelay.submit(batch) == .sent else {
            disasterMessage = "P510まで届いていません。衛星回線でも、届いてからまとめて送ります。"
            return
        }
        try? DisasterBook.markSynced(batch, projectName: project.name, at: drawing.projectsRoot)
        reloadDisaster()
        disasterMessage = "P510へ\(batch.count)件送りました。記録は消していません。"
    }

    func noteDisasterMotion(force: Bool = false) {
        loadDisasterIfNeeded()
        guard extras.disaster, disasterMode, let project = drawing.project else { return }
        guard locationShare.shares else { return }
        guard let position = navigationReading.position, position.isPlottable else { return }
        let now = Date()
        if let point = DisasterEntry.position(
            deviceID: crew.deviceID,
            name: crew.displayName,
            at: now,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            horizontalAccuracyMeters: position.horizontalAccuracyMeters
        ) {
            let interval = BatterySaver.shareInterval(enabled: batterySaver)
            let due = force || lastDisasterShare.map { now.timeIntervalSince($0) >= interval } ?? true
            if due {
                lastDisasterShare = now
                _ = disasterPeersDesk.note(point)
                disasterPeers = disasterPeersDesk.latest
                try? DisasterBook.savePositions(disasterPeersDesk.latest, projectName: project.name, at: drawing.projectsRoot)
                publishDisaster(kind: .position, position: point)
                refreshDisasterPending()
            }
        }
        let step = BatterySaver.passageStep(enabled: batterySaver)
        guard PassageTrack.shouldSample(
            after: lastPassageSample,
            latitude: position.latitudeDegrees,
            longitude: position.longitudeDegrees,
            now: now,
            stepMeters: step
        ) else { return }
        guard let sample = DisasterEntry.passage(
            at: now,
            latitudeDegrees: position.latitudeDegrees,
            longitudeDegrees: position.longitudeDegrees,
            state: .open,
            author: crew.displayName
        ) else { return }
        storePassage(sample, projectName: project.name)
    }

    func ingestBucket(_ envelope: BucketEnvelope) {
        guard extras.mesh || extras.disaster else { return }
        loadDisasterIfNeeded()
        guard let project = drawing.project else { return }
        prepareBucket()
        let decision = bucketDesk.receive(envelope, now: Date(), projectID: project.id)
        switch decision {
        case .drop:
            return
        case .keep(let next):
            applyBucket(next, projectName: project.name)
        case .forward(let next):
            applyBucket(next, projectName: project.name)
            if extras.mesh, meshChoice(for: next) == .forward {
                nearby.send(next)
            }
        }
    }

    func relayDisasterSOS(_ packet: SOSPacket) {
        guard drawing.project != nil else { return }
        publishDisaster(kind: .sos, sos: packet)
    }

    func relayDisasterHeld(now: Date) {
        guard extras.mesh, drawing.project != nil, MeshDuty.relaying(meshPresence) else { return }
        let interval = MeshDuty.relayInterval(
            batteryPercent: meshBattery,
            charging: meshCharging,
            saver: batterySaver
        )
        if let last = lastDisasterRelay, now.timeIntervalSince(last) < interval { return }
        lastDisasterRelay = now
        prepareBucket()
        for envelope in bucketDesk.forwardable(now: now) where meshChoice(for: envelope) == .forward {
            nearby.send(envelope)
        }
    }

    func noteMeshPresence(_ presence: MeshDuty.Presence) {
        let wasLive = MeshDuty.relaying(meshPresence)
        meshPresence = presence
        guard MeshDuty.relaying(presence), !wasLive else { return }
        lastDisasterRelay = nil
        relayDisasterHeld(now: Date())
    }

    private func meshChoice(for envelope: BucketEnvelope) -> MeshRelayChoice {
        MeshDuty.choice(
            addressedTo: nil,
            selfID: crew.deviceID,
            kind: envelope.kind,
            hops: envelope.hops.count,
            hopLimit: envelope.hopLimit,
            batteryPercent: meshBattery,
            charging: meshCharging,
            presence: meshPresence
        )
    }

    func disasterPeerCount(_ count: Int) {
        if count > disasterPeersNearby {
            lastDisasterRelay = nil
            relayDisasterHeld(now: Date())
        }
        disasterPeersNearby = count
    }

    func flushDisasterSync() {
        guard disasterRelay.isReachable, let project = drawing.project else { return }
        let batch = DisasterBook.pending(projectID: project.id, projectName: project.name, at: drawing.projectsRoot)
        guard !batch.isEmpty, disasterRelay.submit(batch) == .sent else { return }
        try? DisasterBook.markSynced(batch, projectName: project.name, at: drawing.projectsRoot)
        reloadDisaster()
        disasterMessage = "通信が戻ったので、P510へ\(batch.count)件送りました。"
    }

    func startDisasterUplink() {
        #if canImport(Network)
        let monitor = DisasterPathMonitor()
        disasterPath = monitor
        monitor.onSatisfied = { [weak self] online in
            DispatchQueue.main.async {
                self?.noteDisasterUplink(online)
            }
        }
        monitor.start()
        #endif
    }

    func noteDisasterUplink(_ online: Bool) {
        let rose = disasterUplink.note(online: online)
        disasterRelay.isReachable = online
        guard rose else { return }
        flushDisasterSync()
    }

    private func storePassage(_ sample: PassageSample, projectName: String) {
        do {
            guard try DisasterBook.appendPassage(sample, projectName: projectName, at: drawing.projectsRoot) else { return }
        } catch {
            disasterMessage = "通行を書けませんでした。"
            return
        }
        lastPassageSample = sample
        reloadDisaster()
        publishDisaster(kind: .passage, passage: sample)
    }

    func publishDisaster(
        kind: BucketKind,
        position: DisasterPosition? = nil,
        sos: SOSPacket? = nil,
        text: DisasterText? = nil,
        site: DisasterSite? = nil,
        passage: PassageSample? = nil,
        radioPacket: RadioPacket? = nil,
        hopLimit: Int = BucketRelay.hopLimit,
        envelopeID: UUID = UUID()
    ) {
        guard let project = drawing.project else { return }
        prepareBucket()
        let envelope = BucketRelay.envelope(
            id: envelopeID,
            projectID: project.id,
            kind: kind,
            deviceID: crew.deviceID,
            at: Date(),
            hopLimit: hopLimit,
            position: position,
            sos: sos,
            text: text,
            site: site,
            passage: passage,
            radio: radioPacket
        )
        guard let sent = bucketDesk.originate(envelope, now: Date()) else { return }
        if MeshDuty.relaying(meshPresence) {
            nearby.send(sent)
        }
        objectWillChange.send()
    }

    private func applyBucket(_ envelope: BucketEnvelope, projectName: String) {
        if let position = envelope.position, disasterPeersDesk.note(position) {
            disasterPeers = disasterPeersDesk.latest
            try? DisasterBook.savePositions(disasterPeersDesk.latest, projectName: projectName, at: drawing.projectsRoot)
        }
        if let sos = envelope.sos {
            ingestSOS(sos, arrived: .nearby)
        }
        if let text = envelope.text {
            _ = try? DisasterBook.appendText(text, projectName: projectName, at: drawing.projectsRoot)
        }
        if let site = envelope.site {
            _ = try? DisasterBook.appendSite(site, projectName: projectName, at: drawing.projectsRoot)
        }
        if let passage = envelope.passage {
            _ = try? DisasterBook.appendPassage(passage, projectName: projectName, at: drawing.projectsRoot)
        }
        if let packet = envelope.radio {
            radio.ingestRelayed(packet, play: true)
        }
        reloadDisaster()
    }

    private func prepareBucket() {
        if bucketDesk.selfID.isEmpty {
            bucketDesk.selfID = crew.deviceID
        }
    }

    private func loadDisasterIfNeeded() {
        guard let project = drawing.project else { return }
        guard disasterLoadedProject != project.name else { return }
        disasterLoadedProject = project.name
        let settings = DisasterBook.loadSettings(projectName: project.name, at: drawing.projectsRoot)
        if extras.disaster {
            disasterMode = settings.mode
            batterySaver = settings.batterySaver
        } else {
            disasterMode = false
            batterySaver = false
        }
        disasterPeersDesk = DisasterPeers()
        for position in DisasterBook.loadPositions(projectName: project.name, at: drawing.projectsRoot) {
            disasterPeersDesk.note(position)
        }
        lastPassageSample = DisasterBook.loadPassages(projectName: project.name, at: drawing.projectsRoot)
            .filter { $0.author == crew.displayName }
            .max { $0.at < $1.at }
        reloadDisaster()
    }

    private func reloadDisaster() {
        guard let project = drawing.project else { return }
        disasterSites = DisasterBook.loadSites(projectName: project.name, at: drawing.projectsRoot).sorted { $0.at > $1.at }
        disasterTexts = DisasterBook.loadTexts(projectName: project.name, at: drawing.projectsRoot).sorted { $0.at > $1.at }
        let passages = DisasterBook.loadPassages(projectName: project.name, at: drawing.projectsRoot)
        disasterSegments = PassageTrack.segments(from: passages)
        disasterPeers = disasterPeersDesk.latest
        refreshDisasterPending()
    }

    private func refreshDisasterPending() {
        guard let project = drawing.project else {
            disasterPending = 0
            return
        }
        disasterPending = DisasterBook.pending(projectID: project.id, projectName: project.name, at: drawing.projectsRoot).count
    }

    private func storeDisasterSettings() {
        guard let project = drawing.project else { return }
        try? DisasterBook.saveSettings(
            DisasterSettings(mode: disasterMode, batterySaver: batterySaver),
            projectName: project.name,
            at: drawing.projectsRoot
        )
    }
}

#if canImport(Network)
final class DisasterPathMonitor {
    var onSatisfied: ((Bool) -> Void)?
    private let monitor = NWPathMonitor()

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.onSatisfied?(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "disaster.uplink"))
    }
}
#endif
