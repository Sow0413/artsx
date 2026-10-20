# P510 のインシデント集計

全プロジェクトのヒヤリハットと接近を、同じ列で足すための雛形です。サーバーはここにはありません。集めた CSV か SQLite を、このスクリプトに渡します。

## 共通スキーマ `incident-stat/1`

| 列 | 意味 |
| --- | --- |
| schema | `incident-stat/1` |
| source | `incident` または `proximity` |
| record_id | 記録の ID |
| project_id | プロジェクト ID |
| project_name | プロジェクト名 |
| occurred_at | UTC の ISO8601 |
| work_kind | 作業種類。接近だけの古い記録は `不明` |
| time_band | 時間帯。日本時間で 深夜 0–5、早朝 5–8、午前 8–12、午後 12–17、夕方 17–19、夜間 19–24 |
| weather | 天候。`晴れ` `曇り` `雨` `雪` `不明` |
| distance_m | 距離。0.1m。無いときは空 |
| machine_kind | 重機種類。プロジェクトの機種（例 `20t`） |
| role | 役割。`重機` `作業員` または `重機×作業員` |
| latitude | 緯度。無い接近は空で、地図には出さない |
| longitude | 経度 |
| level | `ヒヤリ` `接近警報` `警報` `注意` |
| party | 表示名。匿名化するときは役割だけ |

アプリはプロジェクトの `記録簿/統計.csv` に、この列で書き出します。インシデント本体は書き換えません。

## 実行

```bash
python3 tools/p510/aggregate_incidents.py --month 2026-10 --out /tmp/stats --anonymize 現場の統計.csv 別現場.sqlite
```

フォルダを渡すと、中の `*.csv` をすべて読みます。SQLite はテーブル `incident_stat` に同じ列があること。

出力は `{月}-件数.csv`、`{月}-地図.svg`、`{月}-月次.pdf` です。PDF の日本語は HeiseiKakuGo-W5 を参照しているだけで、フォントは埋め込んでいません。地図は位置の点で、地理院タイルではありません。

`--anonymize` は `party` を役割に置き換えます。月の区切りは日本時間です。
