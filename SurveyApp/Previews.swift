import SwiftUI
import SurveyCore

#Preview("段階0 iPhone") {
    let environment = AppEnvironment.preview(source: SimulatedPositionSource.iphonePreview())
    return RootView(
        source: environment.source,
        tiles: environment.tiles,
        packDirectory: environment.packs,
        controlPoints: environment.points,
        controlPointNotice: environment.notice,
        siteDirectory: environment.site
    )
}

#Preview("段階1 CLAS") {
    let environment = AppEnvironment.preview(source: SimulatedPositionSource.clasPreview())
    return RootView(
        source: environment.source,
        tiles: environment.tiles,
        packDirectory: environment.packs,
        controlPoints: environment.points,
        controlPointNotice: environment.notice,
        siteDirectory: environment.site
    )
}

#Preview("段階2 RTK Fix") {
    let environment = AppEnvironment.preview(source: SimulatedPositionSource.rtkFixPreview())
    return RootView(
        source: environment.source,
        tiles: environment.tiles,
        packDirectory: environment.packs,
        controlPoints: environment.points,
        controlPointNotice: environment.notice,
        siteDirectory: environment.site
    )
}
