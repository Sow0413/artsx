import Foundation

/// Playgrounds では PushToTalk と MultipeerConnectivity を切る。権限の出る API はコンパイルしない。
enum RadioHardware {
    #if !SURVEY_PLAYGROUND && canImport(PushToTalk)
    static let pushToTalk = true
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
