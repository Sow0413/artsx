# ViDoc RTK 統合記録（Claude → artsx / Grok 引き継ぎ）

artsx の位置源抽象（`PositionSource`）に、ViDoc(viGram)RTK ローバーを BLE 直結で挿し込み、
ドコモ高精度GNSS(NTRIP)の補正で RTK Fix(cm) にするための記録と、追加したコードの一覧・配線手順。
社内で ViDoc の BLE を解読した結果（Pix4Dcatch の複製ではなく、自社機材の相互運用）。

## 1. ViDoc BLE プロトコル（解読済み・実機で NMEA 取得まで確認）

- GATT: **Service `0xFFF0`**
  - `0xFFF1` **Notify** … ViDoc の出力。待機中は `<STX>df Ver_0.0.4` を反復。開始後は標準 NMEA。
  - `0xFFF2` **Write / WriteWithoutResponse** … 入力。開始コマンドと RTK 補正(RTCM3)を流す口。
- **開始コマンド**: FFF2 へ `<STX>nmea<ETX>` = バイト列 `02 6E 6D 65 61 03` を書くと NMEA 配信が始まる（実証済み）。
- **出力(NMEA)**: `$GNGGA`（緯度経度/quality/衛星数/HDOP/標高/ジオイド高/補正遅れ/基準局ID）、
  `$GNGST`（誤差: semiMajor/Minor 1σ・lat/lon/altStd）、`$GNGSA`（PDOP）等の標準 NMEA。
  - quality: `1`=単独 / `2`=DGPS / `4`=RTK Fix / `5`=RTK Float。
- **RTK 補正**: NTRIP の RTCM3 を FFF2 に流すと quality が 2→4(Fix) に上がる。
- 信号は弱め(約 -96dBm)。iPhone/iPad の BLE は問題なく届く（P510 の安物 USB ドングルでは不可だった）。
  → **iOS では中継(T-Beam 等)は不要。CoreBluetooth で ViDoc に直結する。**
- Pix4Dcatch 解析(正規 APK, androguard)で裏取り: `com.pix4dcatch.vigram.*`（SatelliteMessage{Pvt,Dop}）は
  上記 NMEA のフィールドと一致。カメラ=ARCore＋写真測量エンジン、レーザー=先端オフセット、IMU=傾斜補正は
  ViDoc 内部で処理され、結果は NMEA に乗る。生 GATT 最下層は難読化依存lib内（相互運用には不要）。

## 2. ドコモ高精度GNSS(NTRIP)補正

- 接続: NTRIP v1/v2・Basic 認証・**`d-gnss.jp:2101`**。アカウントは契約者ごと（ID/パスワード）。
- マウントポイント（最寄り局自動選択）: `RRSGD2024`(測地成果2024・推奨) / `RRSGD`(2011) ほか。
  - ★**2024 と 2011 を混ぜると座標がずれる**（ドコモ注意）。案件の測地系に合わせる。
- データ: RTCM3.2（MSM7: GPS1075/GLO1085/GAL1095/QZS1115/BDS1125 ＋基準点1006/1033）、1秒周期。
- 移動局→caster: **概略位置の GGA を 1 秒以上間隔で送る**（最寄り基準点の選択に要る）。ViDoc の GGA をそのまま使える。

## 3. 追加したファイル（artsx の型に合わせた drop-in）

| ファイル | 役割 |
|---|---|
| `SurveyApp/ViDocPositionSource.swift` | **`PositionSource` 準拠**。CoreBluetooth で FFF0 接続→`<STX>nmea<ETX>`→FFF1 購読→NMEA を `NMEAParser` へ渡し、`GeodeticPosition`(fixQuality/accuracy/satelliteCount/pdop/correctionAge)を `AsyncStream` で発行。`injectRTCM(_:)` で FFF2 へ補正を注入。 |
| `SurveyCore/Sources/SurveyCore/NMEA.swift` | GGA / GST / GSA の純解析。BLE を含まないので `swift test` が Linux でも回る。GST の誤差は次の GGA から精度に入る。 |
| `SurveyApp/NTRIPClient.swift` | ドコモ NTRIP(`Network.framework`)。Basic 認証で GET、RTCM3 を受けて `ViDocPositionSource.injectRTCM` へ。ViDoc の最新 GGA を、接続の 1 秒後から 2 秒ごとに返す。 |
| `SurveyApp/RTKPositionSession.swift` | **iPhone⇄ViDoc を実行時に切り替える `PositionSource`＋`ObservableObject`**。NTRIP の起動/停止、状態(`fix`/`horizontalAccuracyMeters`/`satelliteCount`/`correctionAge`/`message`)を `@Published`。パスワードは `RTKKeychain`(Keychain)。 |
| `SurveyCore/.../RTKSettings.swift` | 接続設定(host/port/mountpoint/user)の Codable モデル＋端末内 JSON 保存(`RTK設定.json`)。マウントポイント列挙。パスワードは含めない。 |
| `SurveyApp/RTKSettingsView.swift` | 設定・接続画面。1行の解（FIX / FLOAT / DGPS / 単独 と精度）。測地系の注意は「測地系」の (i)。 |

`RTKPositionSession` と `RTKSettingsView` は `#if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)`。
`ViDocPositionSource` は `canImport(CoreBluetooth)`、`NTRIPClient` は `canImport(Network) && canImport(CoreBluetooth)`。
iPad の Swift Playgrounds は `SURVEY_PLAYGROUND` が定義されるので、切替セッションと設定画面はコンパイルされない。位置源は従来の iPhone のまま。

Xcode のターゲットは `project.yml` が `SurveyApp/` 全体（Info.plist 以外）と SurveyCore パッケージを取る。生成物の `Survey.xcodeproj` はコミットしない。ファイルを追加で pbxproj を手編集する必要はない。

`SurveyApp/Info.plist` には、この配線の前から次が入っている。追加はしていない。

- `NSBluetoothAlwaysUsageDescription`
- `NSBluetoothPeripheralUsageDescription`

どちらも「GNSS 受信機とつなぐ」。

## 4. 配線

1. **位置源を切替セッションにする** — `SurveyApp/RootView.swift` の `AppEnvironment.live()`。
   戻り値の `source` は `any PositionSource`。Playgrounds では `CoreLocationPositionSource` のまま。
   ```swift
   #if !SURVEY_PLAYGROUND && canImport(CoreBluetooth) && canImport(Network)
   let source: any PositionSource = RTKPositionSession()
   #else
   let source: any PositionSource = CoreLocationPositionSource()
   #endif
   ```
   既定はセッション内の iPhone 単独なので、RTK を設定するまで地図の挙動は変わらない。

2. **セッションを画面から触れるようにする** — `SurveyApp/FieldModel.swift`。
   `source` は private のまま。計算プロパティ `rtkSession` と `openRTK()` は、上と同じ `#if` の中。
   `openRTK()` はレガシーの `GNSSLink`（位置を読まない BLE スキャン）を止めてからシートを出す。
   `resumeGNSS()` は、シートが開いているあいだ、またはモードが RTK のあいだは何もしない。前面に戻ったときに古いスキャンが ViDoc を奪わないため。
   RTK 中は `scanGNSS()` / `chooseGNSS()` も何もしない。

3. **設定画面の入口** — 地図の「おまけ」の横と、記録タブの GNSS 見出しに「RTK」ボタン。`showsRTK` でシートを出す。
   ```swift
   .sheet(isPresented: $field.showsRTK) {
       if let session = field.rtkSession {
           RTKSettingsView(session: session, siteDirectory: field.siteDirectory)
       }
   }
   ```
   シートを閉じたとき、まだ iPhone 単独なら `resumeGNSS()` で古いリンクを戻す。

4. **バッジの1行** — `GeodeticPosition.solutionLabel` と帳票の `FixQualityLabel` は、外部受信機の quality 2 を「DGPS」と出す。iPhone は従来どおり「単独」。地図の既存バッジが `FIX　2cm` / `DGPS　約1m` の形になる。説明文はバッジの要求精度ガイドのまま、RTK 画面では (i) の中だけ。

`AsyncStream` は1本を1回しか読めない。セッションは iPhone と ViDoc を start 時に各1回だけ読み、選んでいる側だけを `FieldModel` へ流す。切替のたびに読み直すと、iPhone に戻したあと位置が止まる。

## 5. 運用

受信機(ViDoc)の電源 ON → 地図か記録の「RTK」→ ID/パスワード/マウントポイントを入れて「接続」。
地図/測る画面の精度バッジが DGPS→FLOAT→**FIX(緑)** に上がる（開けた空が要る）。
以後、基準点記録・丁張・出来形・AR 位置出しがそのまま cm 精度で動く（artsx 既存の消費側はそのまま）。
補正元・補正遅れ・衛星数・PDOP は `GeodeticPosition`/`ObservationCondition` に入り、帳票に出る。

パスワードと ID はソースに置かない。ID・接続先・マウントポイントは `RTK設定.json`、パスワードは Keychain（`arts.survey.ntrip`）だけ。

## 6. 実機でまだ見ること

この環境では iOS をビルドしていない。Linux の `swift test` は NMEA と設定 JSON だけ。

- ViDoc の広告名が `vidoc` / `vida` に合うか。合わなければスキャンが素通りする。
- `<STX>nmea<ETX>` のあと FFF1 に GGA/GST/GSA が来て、バッジが単独→DGPS→FLOAT→FIX と変わるか。
- ドコモ caster が HTTP/1.0 の GET と、2秒ごとの GGA で最寄り局を選ぶか。認証 NG はシートに出る。
- RTCM を FFF2 へ MTU 分割で書いたとき、quality が 4 になるか。補正遅れは GGA の age を優先し、空欄のときだけ最後に書いた時刻から数える。
- GST は次の GGA から水平・高さの精度に入る。1エポック遅れる。
- 記録タブの「近くの GNSS を探す」は位置を読まない古い BLE。ViDoc 接続中は無視する。
