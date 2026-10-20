#!/usr/bin/env python3
"""P510 の集計雛形。インシデント統計 CSV または SQLite を読み、月次 PDF と地図を書く。

サーバー本体ではない。現場の箱で、集めたファイルに対して手で走らせる。

入力の列は incident-stat/1。
schema,source,record_id,project_id,project_name,occurred_at,work_kind,time_band,weather,distance_m,machine_kind,role,latitude,longitude,level,party

occurred_at は UTC の ISO8601。月の区切りは日本時間。
--anonymize を付けると、個人名の列は役割に置き換える。
"""

from __future__ import annotations

import argparse
import csv
import sqlite3
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

SCHEMA = "incident-stat/1"
COLUMNS = [
    "schema",
    "source",
    "record_id",
    "project_id",
    "project_name",
    "occurred_at",
    "work_kind",
    "time_band",
    "weather",
    "distance_m",
    "machine_kind",
    "role",
    "latitude",
    "longitude",
    "level",
    "party",
]
TABLE = "incident_stat"
TOKYO = timezone(timedelta(hours=9))


def load_csv(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = [name for name in COLUMNS if reader.fieldnames is None or name not in reader.fieldnames]
        if missing:
            raise SystemExit(f"{path}: 列が足りません: {', '.join(missing)}")
        return [dict(row) for row in reader]


def load_sqlite(path: Path) -> list[dict[str, str]]:
    connection = sqlite3.connect(path)
    try:
        names = [row[1] for row in connection.execute(f"PRAGMA table_info({TABLE})")]
        if not names:
            raise SystemExit(f"{path}: {TABLE} がありません")
        missing = [name for name in COLUMNS if name not in names]
        if missing:
            raise SystemExit(f"{path}: 列が足りません: {', '.join(missing)}")
        query = "SELECT " + ", ".join(COLUMNS) + f" FROM {TABLE}"
        rows = []
        for record in connection.execute(query):
            rows.append({key: "" if value is None else str(value) for key, value in zip(COLUMNS, record)})
        return rows
    finally:
        connection.close()


def load_path(path: Path) -> list[dict[str, str]]:
    if path.is_dir():
        rows: list[dict[str, str]] = []
        for child in sorted(path.glob("*.csv")):
            rows.extend(load_csv(child))
        return rows
    suffix = path.suffix.lower()
    if suffix in {".sqlite", ".db"}:
        return load_sqlite(path)
    return load_csv(path)


def anonymize(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    hidden = []
    for row in rows:
        copy = dict(row)
        role = copy.get("role") or "不明"
        copy["party"] = role
        hidden.append(copy)
    return hidden


def parse_time(text: str) -> datetime | None:
    text = text.strip()
    if not text:
        return None
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(TOKYO)


def in_month(row: dict[str, str], month: str) -> bool:
    parsed = parse_time(row.get("occurred_at", ""))
    if parsed is None:
        return False
    return parsed.strftime("%Y-%m") == month


def counts(rows: list[dict[str, str]], key: str) -> list[tuple[str, int]]:
    totals: dict[str, int] = {}
    for row in rows:
        name = row.get(key) or "不明"
        totals[name] = totals.get(name, 0) + 1
    return sorted(totals.items())


def write_counts(rows: list[dict[str, str]], path: Path) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["kind", "key", "count"])
        for key, count in counts(rows, "work_kind"):
            writer.writerow(["work_kind", key, count])
        for key, count in counts(rows, "time_band"):
            writer.writerow(["time_band", key, count])
        for key, count in counts(rows, "weather"):
            writer.writerow(["weather", key, count])
        for key, count in counts(rows, "machine_kind"):
            writer.writerow(["machine_kind", key, count])
        for key, count in counts(rows, "role"):
            writer.writerow(["role", key, count])


def write_svg(rows: list[dict[str, str]], path: Path) -> None:
    points = []
    for row in rows:
        try:
            latitude = float(row.get("latitude") or "")
            longitude = float(row.get("longitude") or "")
        except ValueError:
            continue
        points.append((longitude, latitude))
    width, height = 640, 480
    lines = [
        '<?xml version="1.0" encoding="UTF-8"?>',
        f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" viewBox="0 0 {width} {height}">',
        '<rect width="100%" height="100%" fill="#101418"/>',
        '<text x="16" y="28" fill="#f5f7fa" font-family="sans-serif" font-size="16">ヒヤリハットの位置</text>',
    ]
    if not points:
        lines.append('<text x="16" y="56" fill="#9aa3ad" font-family="sans-serif" font-size="14">位置のある記録はありません</text>')
    else:
        lons = [item[0] for item in points]
        lats = [item[1] for item in points]
        min_lon, max_lon = min(lons), max(lons)
        min_lat, max_lat = min(lats), max(lats)
        span_lon = max(max_lon - min_lon, 0.0002)
        span_lat = max(max_lat - min_lat, 0.0002)
        for longitude, latitude in points:
            x = 40 + (longitude - min_lon) / span_lon * (width - 80)
            y = 60 + (max_lat - latitude) / span_lat * (height - 100)
            lines.append(f'<circle cx="{x:.1f}" cy="{y:.1f}" r="10" fill="#ef4444" fill-opacity="0.45"/>')
    lines.append("</svg>")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_pdf(rows: list[dict[str, str]], path: Path, month: str, anonymized: bool) -> None:
    lines = [
        "月次ヒヤリハット集計",
        f"対象 {month}",
        f"件数 {len(rows)}",
        "作業種類",
    ]
    lines += [f"{key} {count}" for key, count in counts(rows, "work_kind")] or ["なし"]
    lines.append("時間帯")
    lines += [f"{key} {count}" for key, count in counts(rows, "time_band")] or ["なし"]
    lines.append("天候")
    lines += [f"{key} {count}" for key, count in counts(rows, "weather")] or ["なし"]
    lines.append("重機種類")
    lines += [f"{key} {count}" for key, count in counts(rows, "machine_kind")] or ["なし"]
    lines.append("役割")
    lines += [f"{key} {count}" for key, count in counts(rows, "role")] or ["なし"]
    if anonymized:
        lines.append("個人名は役割に置き換えました")
    lines.append("地図は同じフォルダの SVG です")
    lines.append("補助。安全確認の代わりではない")
    path.write_bytes(pdf_pages(lines))


def pdf_pages(lines: list[str]) -> bytes:
    commands = "BT\n/F2 12 Tf\n40 800 Td\n"
    for line in lines[:40]:
        commands += f"<{utf16(line)}> Tj\n0 -18 Td\n"
    commands += "ET\n"
    stream = (
        f"<< /Length {len(commands.encode('utf-8'))} >>\nstream\n{commands}endstream"
    )
    objects = [
        "<< /Type /Catalog /Pages 2 0 R >>",
        "<< /Type /Pages /Kids [3 0 R] /Count 1 >>",
        "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Contents 4 0 R /Resources << /Font << /F2 5 0 R >> >> >>",
        stream,
        "<< /Type /Font /Subtype /Type0 /BaseFont /HeiseiKakuGo-W5 /Encoding /UniJIS-UTF16-H /DescendantFonts [6 0 R] >>",
        "<< /Type /Font /Subtype /CIDFontType0 /BaseFont /HeiseiKakuGo-W5 /CIDSystemInfo << /Registry (Adobe) /Ordering (Japan1) /Supplement 2 >> >>",
    ]
    body = bytearray(b"%PDF-1.4\n")
    offsets = [0]
    for index, obj in enumerate(objects, start=1):
        offsets.append(len(body))
        body.extend(f"{index} 0 obj\n{obj}\nendobj\n".encode("utf-8"))
    xref = len(body)
    table = f"xref\n0 {len(objects) + 1}\n0000000000 65535 f \n"
    for offset in offsets[1:]:
        table += f"{offset:010d} 00000 n \n"
    body.extend(table.encode("utf-8"))
    body.extend(
        f"trailer << /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode("utf-8")
    )
    return bytes(body)


def utf16(text: str) -> str:
    encoded = text.encode("utf-16-be")
    return "FEFF" + encoded.hex().upper()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="インシデント統計を月次の PDF と地図にする")
    parser.add_argument("inputs", nargs="+", type=Path, help="CSV、SQLite、または CSV のフォルダ")
    parser.add_argument("--month", required=True, help="YYYY-MM。日本時間")
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--anonymize", action="store_true", help="個人名を役割に置き換える")
    args = parser.parse_args(argv)
    rows: list[dict[str, str]] = []
    for path in args.inputs:
        rows.extend(load_path(path))
    rows = [row for row in rows if row.get("schema", SCHEMA) in {"", SCHEMA}]
    rows = [row for row in rows if in_month(row, args.month)]
    if args.anonymize:
        rows = anonymize(rows)
    args.out.mkdir(parents=True, exist_ok=True)
    write_counts(rows, args.out / f"{args.month}-件数.csv")
    write_svg(rows, args.out / f"{args.month}-地図.svg")
    write_pdf(rows, args.out / f"{args.month}-月次.pdf", args.month, args.anonymize)
    print(f"{len(rows)} 件を {args.out} に書きました")
    return 0


if __name__ == "__main__":
    sys.exit(main())
