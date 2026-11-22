import Foundation

/// このビルドの範囲。`basicMode` が true のあいだは、地図、RTK、現在地、測る、書き出しだけにする。
/// ほかの機能のコードは残し、画面にもセンサにも出さない。false に戻すと今までの全部になる。
enum SurveyBuild {
    static let basicMode = true
}
