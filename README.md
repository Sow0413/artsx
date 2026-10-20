# 測量

手軽に観測、手軽に測設。いつでも何処でも、測って出せる。

iPhone / iPad 向けの測量アプリです。地図タブと、三角点で検証する記録が動きます。図面、測る、出すは置き場所だけあります。

## 今できること

- 地図に現在地と精度の円を出す。段階0は iPhone の GPS だけ。
- 画面の上に精度バッジを常に出す。色は下の規則。
- 国土地理院の標準地図を重ねる。見たタイルは端末に残り、表示中の範囲は「この範囲を保存」で圏外用に取っておける。
- 近くの基準点を地図に出し、点をタップして 1 秒に 1 点、既定 10 分の記録を取る。平均位置、既知点との水平・高さの差、ばらつき、報告精度が楽観的かを出し、CSV で書き出す。
- 下のタブは 地図 / 図面 / 測る / 出す。地図以外は次のスライスの案内。
- 座標、精度の色、タイル、検証の統計は `SurveyCore` にあり、Linux で `swift test` できる。

## まだできないこと

- CLAS と RTK の受信機はつながない。型と色の規則だけ先に置いてある。
- 図面の DXF、任意の点の取得、PDF / DXF / SIMA の書き出しはない。
- 地点と軌跡の型はある。記録する画面はまだない。
- 全国の三角点台帳は入っていない。同梱は見本だけ。
- 地理院タイルはアプリに同梱しない。最初の表示と、範囲の保存には通信が要る。
- この環境には Xcode がない。iOS アプリ本体はここではビルドしていない。

## 精度の色

緑は、外部受信機が RTK Fix と報告したときだけ。iPhone の GPS は何 m でも緑にしない。CLAS も緑にしない。

| 色 | 意味 | 例 |
| --- | --- | --- |
| 琥珀 | 下見。測設の合否には使わない | iPhone GPS 約3m、CLAS 約5cm、RTK Float 約20cm |
| 緑 | 測設に使ってよい | RTK Fix 2cm（「約」は付けない） |
| 灰色 | 位置がない、許可がない、精度が数値になっていない | 位置情報を許可してください、精度不明 |

内部の段階は 0 が iPhone、1 が CLAS、2 が RTK、3 が併用。今の実装は段階0だけ。

## 座標

端末の中は WGS84/ITRF の緯度、経度、楕円体高。画面下の注記は「JGD2024・下見／概略用」。測地系の変換は、出すときの一度だけにする。設定画面も、測地系の選択もない。

## 三角点で検証

iPhone を、座標が分かっている三角点の上に置く。地図の三角印をタップし、1分・10分・30分から選ぶ（既定は10分）。1秒に1点、緯度経度と水平・高さの精度を残す。

終わると次を出す。

- 平均位置。既知点を原点にした東西・南北の平均で、GRS80 の Vincenty 測地線から戻す。
- 水平の差。平均位置と既知点の測地線距離。
- 高さの差。既知の高さも楕円体高のときだけ、精度の判定に使う。成果が標高のときは、楕円体高から標高を引いた値を出す。ジオイドが含まれるので、楽観かどうかは判定しない。
- ばらつき。東西・南北の標本標準偏差を合成した値と、平均位置からの距離の95%。
- 報告精度。水平精度の平均が、平均位置の実際のずれより小さいとき「楽観的」。あわせて、68%の円（iPhone の `horizontalAccuracy`）の外に出た点の数。

CSV は記録の各行と、先頭の summary 行。共有シートから書き出す。

距離は GRS80（赤道半径 6378137 m、扁平率の逆数 298.257222101）の Vincenty。対蹠点で収束しないときはその点を捨てる。Karney の式は対蹠点向けなので、ここには移植していない。カメラの追従だけは、これまで通り球面の近似を使う。

見本は `SurveyApp/Resources/sample-control-points.json`（同じ内容の CSV もある）。日本経緯度原点の緯度経度と日本水準原点の標高は測量法施行令の値。富士山は公表されている緯度経度と令和7年の標高。机上の見本点は実在しない。全国の成果表は同梱しない。測量成果の複製には承認が要ることがある。

現場パックは、アプリの Application Support にある `SitePack/control-points.json`（無ければ `control-points.csv`）。`fgd_points.sqlite` から自分で切り出したファイルを、この形で置く。JSON の点は `id`、`name`、`kind`、`grade`、`latitudeDegrees`、`longitudeDegrees`、`heightMeters`、`heightKind`（`ellipsoidal` / `orthometric` / `unspecified`）、任意の `ellipsoidalHeightMeters`、`sourceNote`。楕円体高が入っていれば、高さの判定にそれを使う。ファイルが無いときは見本に戻る。

## 地図タブの参考

UX は **ジオグラフィカ（Geographica）** をモデルにした。株式会社エヌ・シィ・ティの日本向け地図アプリで、範囲を指定して地理院タイルを先に保存する、現在地を大きく出す、地点と軌跡を扱う、という使い方を借りている。コードは使っていない。

オフラインタイルの保存と、iOS で速く描く構成は **Organic Maps**（Apache-2.0）を参考にした。地域をひとまとまりにする、手元のデータを通信より先に見る、短いメモリキャッシュを置く、描画と保存を分ける、という考え方だけを Swift で書き直している。C++ と OpenGL の実装は移植していない。M0 の描画は MapKit。

OsmAnd と QField は GPL。それらのコードは読んでいないし、コピーしていない。

## 地理院タイル

- 実行時に `https://cyberjapandata.gsi.go.jp/xyz/std/{z}/{x}/{y}.png` から取る。
- 一度見たタイルはディスクキャッシュに残す。利用者が「この範囲を保存」した範囲は、現場パックとして別に残す。
- タイル画像はリポジトリに置かない。測量法上の複製をアプリへ同梱しないため。
- 地図の上に「地理院タイル」と「出典：国土地理院」を出す。

## 置き場所

- `SurveyCore/` — 純 Swift の計算。位置、精度、タイル、範囲保存、地点と軌跡の型。
- `SurveyApp/` — SwiftUI。iOS 17 以降、iPhone と iPad の1つのアプリ。
- `project.yml` — XcodeGen の定義。`Survey.xcodeproj` は生成物なのでコミットしない。

## Linux でテスト

Swift 6.4.1（`.swift-version`）を入れる。

```bash
cd SurveyCore
swift test
```

33件。精度が緑になる条件、地理院タイルの番号、ディスクキャッシュ、範囲保存、地点と軌跡の長さを見ている。

## Mac でビルド

Xcode 15 以降と、iOS 17 の SDK が要る。

```bash
brew install xcodegen
xcodegen generate
open Survey.xcodeproj
```

署名なしで確認するとき:

```bash
xcodebuild \
  -project Survey.xcodeproj \
  -scheme SurveyApp \
  -destination 'generic/platform=iOS' \
  -configuration Release \
  CODE_SIGNING_ALLOWED=NO \
  build
```

実機と TestFlight の前に、Apple Developer Program（年額の目安は約13,000円）へ加入し、Xcode の Signing で Development Team を選ぶ。`project.yml` にはチーム ID を書いていない。

## クラウド Mac と TestFlight

GitHub Actions（`.github/workflows/ci.yml`）は次の3つ。

1. Ubuntu で `SurveyCore` の `swift test`
2. macOS で署名なしの `xcodebuild`
3. 手動実行で `upload_testflight` を選んだときだけ、Archive して App Store Connect へ上げる

3に使う Secrets はリポジトリへ自分で置く。値はこの README にもワークフローにも書かない。

| Secret | 中身 |
| --- | --- |
| `DEVELOPMENT_TEAM` | Apple Developer の Team ID |
| `APPSTORE_ISSUER_ID` | App Store Connect API の Issuer ID |
| `APPSTORE_KEY_ID` | API キーの Key ID |
| `APPSTORE_PRIVATE_KEY` | API キーの `.p8` の中身 |

## 次のスライス

- 図面: DXF を重ね、2点で合わせる。RTK Fix になるまで、合わせは緑にしない。
- 測る: 点を取る。地点と軌跡の記録はここへ足す。
- 出す: PDF、DXF、SIMA。JGD2024 への変換は、この出口で一度だけ行う。
- 現場パック: `fgd_points.sqlite` から近くの三角点を切り出し、楕円体高に直して `control-points.json` にする作業は事務所側。アプリは置かれたファイルを読む。
- その先: CLAS を Bluetooth で受ける。三角点での検証は、その受信機でも同じ画面で使う。
