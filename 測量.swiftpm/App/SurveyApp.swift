import SwiftUI

@main
struct SurveyApp: App {
    private let environment = AppEnvironment.live()

    var body: some Scene {
        WindowGroup {
            RootView(
                source: environment.source,
                tiles: environment.tiles,
                packDirectory: environment.packs,
                controlPoints: environment.points,
                controlPointNotice: environment.notice,
                siteDirectory: environment.site
            )
        }
    }
}
