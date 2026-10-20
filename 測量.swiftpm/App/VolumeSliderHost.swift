import SwiftUI

#if !SURVEY_PLAYGROUND && canImport(MediaPlayer)
import MediaPlayer

/// 音量ボタンをアプリが受け取るための隠しスライダ。画面の外に置く。
struct VolumeSliderHost: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        let view = MPVolumeView(frame: .zero)
        view.showsRouteButton = false
        return view
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#else
struct VolumeSliderHost: View {
    var body: some View { Color.clear.frame(width: 0, height: 0) }
}
#endif
