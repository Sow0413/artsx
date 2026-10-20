import Foundation

/// Playgrounds では PushToTalk と MultipeerConnectivity を切る。権限の出る API はコンパイルしない。
enum RadioHardware {
    #if !SURVEY_PLAYGROUND && canImport(PushToTalk) && !targetEnvironment(macCatalyst)
    /// PushToTalk は Apple silicon 上の iOS アプリには無い。呼ぶ前にここで止める。
    static var pushToTalk: Bool {
        !ProcessInfo.processInfo.isiOSAppOnMac
    }
    #else
    static let pushToTalk = false
    #endif

    #if !SURVEY_PLAYGROUND && canImport(MultipeerConnectivity)
    static let nearbyPeers = true
    #else
    static let nearbyPeers = false
    #endif

    #if !SURVEY_PLAYGROUND && canImport(NearbyInteraction)
    static let nearbyInteraction = true
    #else
    static let nearbyInteraction = false
    #endif

    #if !SURVEY_PLAYGROUND && canImport(WatchConnectivity)
    static let watch = true
    #else
    static let watch = false
    #endif
}
