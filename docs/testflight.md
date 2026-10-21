# TestFlight

表示名は artsx。バンドル ID は `com.artshome.artsx`。チームは `9PT57JQMVT`。バージョンは App Store Connect の 1.0 に合わせる。ビルド番号は、アップロードのとき GitHub Actions の実行番号にする。

## CI

GitHub Actions の macOS 15 ランナーで署名してアップロードする。リポジトリにワークフローを置けて、API キーを Secret にできる。Xcode Cloud は署名を Apple が持つが、このリポジトリの Origin にはつながない。Cursor のクラウドエージェントは Linux で、iOS のアーカイブはできない。

macOS の分数は Linux の 10 倍で数える。署名なしビルドは、pull request と `main` への push、手動実行のときだけ走る。TestFlight への送信は、Actions の手動実行で「upload_testflight」をオンにしたときだけ。

秘密が無い状態では、Linux の `scripts/check-ios-release.sh` と、Mac の署名なしビルドまで進む。アップロードのジョブは、秘密が無いと失敗して名前を出す。

## 秘密

GitHub のリポジトリで、Settings → Secrets and variables → Actions → Repository secrets。

必須:

- `ASC_KEY_ID` … `W83MDR6446`
- `ASC_ISSUER_ID` … `b26132eb-fdfd-4c87-b8a8-b39270554e8f`
- `ASC_KEY_P8` … `.p8` の中身を base64 にした1行。PEM のまま改行を `\n` にした文字列でも読める。

任意:

- `ASC_TEAM_ID` … 空なら `9PT57JQMVT`。
- `BUILD_CERTIFICATE_BASE64` と `BUILD_CERTIFICATE_PASSWORD` … Apple Distribution の `.p12`。App Manager の API キーでは証明書を新規に作れないことがある。そのときだけ、アカウントホルダーが一度書き出した p12 をこの2つに置く。置かなければ、API キーの自動署名だけを使う。

`.p8`、証明書、プロビジョニングプロファイルはリポジトリに置かない。

## 手動で残っていること

1. このリポジトリを GitHub に載せ、Actions を有効にする。Origin だけではこのワークフローは走らない。
2. 上の Secret を GitHub に入れる。
3. App Store Connect のアプリ `artsx`（Apple ID 6825094424）のバージョン 1.0 が開いていることを確認する。
4. Actions → CI → Run workflow → upload_testflight をオンにする。
5. 最初の署名で「distribution certificate」と出たら、Developer のアカウントホルダーが Apple Distribution 証明書を1つ作り、p12 を任意の Secret に入れる。App ID `com.artshome.artsx` に capability はまだ付けない。
6. 処理が終わったら、TestFlight で自分の iPhone をテスターにする。位置出しの声はここで実機確認する。
7. Apple Watch 用の `com.artshome.artsx.watch` は未登録なので、このアップロードには含めない。
8. Push to Talk の背面モードは、App ID に capability が無いと処理で落ちるため外してある。無線の常時受信を戻すときは、capability を付けてから Info.plist に戻す。
