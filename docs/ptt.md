# 押して話す（PTT）

現場の無線。Apple の PushToTalk（iOS 16 以降）で、ロック中も受信し、システムのボタンを使う。音声そのものの中継は、現場の P510 に置く小さなサーバーを想定する。この版は、その差し込み口とスタブ、そして近くの端末どうしの口まで。サーバーは動かさない。

実機での送受信、APNs、ロック画面、Bluetooth の発見は、ここでは確認していない。

## チャンネル

チャンネルはプロジェクトと一対一。`RadioChannel.project(id:name:)` が UUID を決める。プロジェクト ID が UUID ならそれを使い、そうでなければ同じ文字列から常に同じ UUID を作る。別のプロジェクトの発話は受け取らない。

## 通り道

半二重。相手が話しているあいだは、こちらのボタンは効かない。

1. P510 の中継が届くときは、中継だけを使う。
2. 中継が届かないときは、MultipeerConnectivity（Wi-Fi か Bluetooth の直接）で、同じチャンネルの近くの端末へ渡す。
3. どちらも届かないときは、発話と測点を端末内の `無線.json` に残す。相手には届いていない印を付ける。

音声のパケットは、中継でも近距離でも同じ `RadioPacket`。

| フィールド | 意味 |
| --- | --- |
| kind | `begin` / `audio` / `end` |
| utteranceID | その発話の UUID |
| channel | プロジェクトのチャンネル |
| speaker | 話した人の表示名 |
| sentAt | 送信時刻 |
| station | 任意。測点の文字列と緯度経度。`audio` と `end` では空 |
| audio | `audio` のときだけ。16 kHz、16 bit、モノラル、20 ms の PCM を想定 |

測点を添えるかは、話す側の設定。切ってあれば `station` は付けない。

## P510 の中継

サーバーはまだ無い。アプリ側の口は `RadioLink` で、仮の実装は `P510RelayStub`。届くかどうかの印と、送ったパケットの控えだけを持つ。

想定する動きは次のとおり。

1. 端末は PushToTalk でチャンネルに入る。フレームワークが ephemeral push token を渡す。
2. 端末はそのトークンと、プロジェクト ID、表示名を P510 の `POST /v1/join` に送る。
3. 話し始めると、アプリは `begin` を `POST /v1/utterances` に送り、続けて音声を `POST /v1/utterances/{id}/audio`（生の PCM）で流す。話し終わりは `POST /v1/utterances/{id}/end`。
4. P510 は、同じプロジェクトの他の端末へ APNs を出す。
   - `apns-push-type: pushtotalk`
   - `apns-topic: <bundle id>.voip-ptt`
   - `apns-priority: 10`
   - `apns-expiration: 0`
   - 本文は `{"activeSpeaker":"表示名","utterance":"<uuid>"}`。話し終わりで話す人がいないときは `activeSpeaker` を付けない。
5. 受けた端末は `incomingPushResult` で `PTPushResult.activeRemoteParticipant` を返し、システムの画面に名前を出す。音声セッションが有効になってから再生する。話し終わりは `setActiveRemoteParticipant(nil)`。
6. 通信圏の外では APNs が届かない。そのときは近距離の口に切り替える。P510 は使わない。

PushToTalk がシステムに頼むこと:

- 資格 `com.apple.developer.push-to-talk` と、Background Modes の Push to Talk、Push Notifications。
- `NSMicrophoneUsageDescription`。
- 起動直後に `PTChannelManager.channelManager(delegate:restorationDelegate:)`。
- 前景で、利用者の操作から `requestJoinChannel(channelUUID:descriptor:)`。チャンネルの UUID はプロジェクトのもの。
- 送信モードは `halfDuplex`。
- ボタン、またはシステムのボタンから `requestBeginTransmitting`。音声の録音は `channelManager(_:didActivate:)` のあと。
- 復元は `channelDescriptor(restoredChannelUUID:)` が、保存してあるプロジェクト名をすぐ返す。

アプリのクラス `SystemPushToTalk` がこの呼び出しを持つ。Playgrounds ではコンパイルしない。

## 近距離

サービス名は `survey-ptt`。発見情報 `channel` にチャンネル UUID を入れる。同じ値の端末だけ招待する。パケットは `RadioPacket` の JSON を、MCSession の reliable で送る。

アプリのクラス `SystemNearbyRadio` が MultipeerConnectivity を使う。相手が見つかるまでは、近距離は「届かない」。Playgrounds ではコンパイルしない。

## インシデント

ヒヤリハットは端末の `記録簿/インシデント/` に確定してから、P510 が届くときだけ渡す。口は `IncidentRelayStub`。サーバーはまだ無い。想定は `POST /v1/incidents` に `ヒヤリハット報告書.pdf` と `記録.json`。届かないあいだは `送信済.json` を書かず、あとから同じ口で一度だけ送る。確定した記録は書き換えない。渡す軌跡は、そのインシデントの前後 60 秒だけ。普段の軌跡も、常時の軌跡も、P510 には残さない。位置を送ってよい条件は `docs/privacy.md`。

## 受信中の方向

話しているあいだ、相手の共有位置（位置の交換。測点の添え字ではない）から、画面の端に矢印と距離を出す。例は「左まえ 80m 田中」。地図と図面は自分の向き（動いていれば進行、止まっていれば方位）。オペ画面は重機の方位を先に使い、方位が無ければ進行。共有が 30 秒より古い、位置が無い、向きが無いときは「方向不明」。

音声をその方向から聞かせるのは任意で、既定はオフ。`AVAudioEnvironmentNode` に、このアプリが受け取った PCM を置く。PushToTalk がシステムで再生する音は向けられない。実機は未確認。

## 記録

発話が終わると、プロジェクトの `無線.json` に `RadioUtterance` を足す。測点、経路（中継 / 近く / なし）、届いたかどうか、音声のバイト数。音声の中身は残さない。

## Playgrounds

`SURVEY_PLAYGROUND` が付いているビルドは、PushToTalk も MultipeerConnectivity も組み込まない。マイクの使用目的も、Push to Talk の背景モードも、Playgrounds の権限には出さない。ボタンは残り、発話と測点は端末内の記録だけになる。

## 転倒

転倒と衝撃の通知は、同じ近距離セッションの `LinkFrame`（kind `fall`）に載せる。P510 が届くときは `FallRelay` に控え、届かないあいだは端末内に留めて、あとから同じ口で送る。サーバーの受け口はまだ無い。通知の例は「右うしろ15m 転倒」。これは緊急通報の代わりではない。

## SOS

SOS はスライドか長押しで始め、出したあいだ自分の位置を送り続ける。同じプロジェクトの端末へ、近距離の `LinkFrame`（kind `sos`）か、圏内なら `SOSRelay` で渡す。圏外で受け取った端末が圏内なら、そのビーコンを一度だけ P510 へ中継する。受けた側は「向かう」を返す。文言の例は「右まえ120m 佐藤 SOS」。位置が古いときは「方向不明」。

これは 119 通報の代わりではない。iPhone の緊急SOSはサイドボタンと音量ボタンの長押しで、アプリからは起動できない。画面にはその手順と、押したときだけ `tel:119` を開くボタンを置く。マナーモードを越える音は Critical Alerts を要求するが、資格は未取得なので実機では鳴らないことがある。

## 初動

SOS か転倒が確定した端末が、同じプロジェクトの新しい位置から最寄りを一人選ぶ。選ばれた人の画面は「あなたが最寄り 右まえ40m」。応答すると「担当確定」になり、他の人には「佐藤が担当です」と渡す。状態は `LinkFrame`（kind `aid`）に載せる。圏内は `AidRelay`、圏外は近くの端末で、受け取った側が圏内なら一度だけ P510 へ中継する。

現場の住所、目印、進入口、救急病院、連絡先、AED・担架・救急箱の位置は project.json の `siteAid`。119 の読み上げは文字列を出すだけで、`tel:119` はボタンを押したときだけ開く。意識・呼吸・出血は見るメモで、手当の手順は無い。時刻は確定前のインシデントに足し、60秒後の報告書に「初動」として残す。確定した記録には足さない。

## 対外説明

確定した `記録.json` から `対外説明` の PDF を作る。確定時に `ハッシュ.txt` へ SHA-256 を一度だけ書く。生成のとき、今のファイルとそのハッシュを比べて、一致か不一致かを PDF に書く。生成時刻も書く。`記録.json` はあとから変えない。救急到着など確定後の事実は `追記.jsonl` に足す。各行は前のハッシュを持つ。労働者死傷病報告の様式は作らず、転記に使える項目だけを別ページに出す。提出はしない。

## 中継

どの端末も、見通しの届く範囲で、話した音声を kind `radio` のバケツに一度だけ包み、自分宛てでない通も次へ渡す。同じ断片の封筒 ID は揃える。4096 バイトを超える音声は転送しない。存在時間は 2 分、ホップ上限は 6、SOS よりあとに送る。電池が 20% を下回ると再送を 60 秒にし、位置などの転送は止める。音声と SOS と文字は渡す。

アプリが前面に無いあいだ、近くの端末への中継は止まる。画面は「中継停止中」。位置情報のバックグラウンドは GPS だけで、PTT の待受は P510 の音声を起こすだけで、どちらも近くのセッションは維持しない。固定の中継と LoRa は、この版では動かさない。設計の控えは `docs/mesh.md` の将来拡張。

## 災害派遣

圏外を前提にする。位置、SOS、文字、被災箇所、通行は `LinkFrame`（kind `bucket`）で近くの端末へ渡し、受け取った端末が次へ中継する。存在時間は作った時刻からで、中継では延ばさない。ホップの上限は 6。仕様は `docs/disaster.md`。

通信が戻ったとき、未送信の記録を `DisasterRelay` で一括に送る。Starlink などの衛星回線は、P510 まで IP が通る経路の一つで、アプリは衛星モデムを操作しない。経路が戻った印は `NWPathMonitor` の satisfied。P510 の無線中継そのものの届く印とは分けている。

## 未確認

- 実機の PushToTalk、ロック中の受信、システムのボタン。
- APNs の `pushtotalk` と、P510 のプロセス。
- MultipeerConnectivity の発見と、Wi-Fi / Bluetooth の届く距離。
- マイクの録音と再生。この版は PCM の枠だけ。
- 転倒通知の近距離送信と、P510 の `FallRelay`。
- CoreMotion の加速度と、Apple Watch の `CMFallDetectionManager`。資格は未取得。
- 受信中の方向矢印を、実機の発話と一緒に出すこと。空間オーディオ。
- SOS の長押し、Apple Watch、振動、Critical Alerts、近距離と P510 の中継。資格は未取得。
- 初動の共有、地図の矢印、119 の発信。
- 対外説明 PDF を労基署や警察へ渡すこと。この版は端末内に書くだけ。
- 災害派遣のバケツリレー、通信復帰、衛星回線経由の P510。受け口はまだ無い。
- 見通し範囲の全端末中継、前面を離れたときの「中継停止中」、複数台の音声中継。
