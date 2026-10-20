import sqlite3
import tempfile
import unittest
from pathlib import Path

import aggregate_incidents as agg


HEADER = ",".join(agg.COLUMNS)


def row(**overrides: str) -> str:
    values = {
        "schema": agg.SCHEMA,
        "source": "incident",
        "record_id": "1",
        "project_id": "p",
        "project_name": "国道",
        "occurred_at": "2026-10-20T01:00:00Z",
        "work_kind": "下見",
        "time_band": "午前",
        "weather": "雨",
        "distance_m": "12.4",
        "machine_kind": "20t",
        "role": "重機×作業員",
        "latitude": "36.00000000",
        "longitude": "139.80000000",
        "level": "ヒヤリ",
        "party": "田中",
    }
    values.update(overrides)
    return ",".join(values[name] for name in agg.COLUMNS)


class AggregateTests(unittest.TestCase):
    def test_month_uses_tokyo_and_anonymize_drops_the_name(self) -> None:
        with tempfile.TemporaryDirectory() as raw:
            folder = Path(raw)
            csv_path = folder / "統計.csv"
            csv_path.write_text(
                HEADER
                + "\n"
                + row()
                + "\n"
                + row(record_id="2", occurred_at="2026-09-30T14:00:00Z", party="佐藤")
                + "\n"
                + row(record_id="3", occurred_at="2026-10-31T15:00:00Z", party="鈴木")
                + "\n",
                encoding="utf-8",
            )
            db_path = folder / "stats.db"
            connection = sqlite3.connect(db_path)
            connection.execute(
                "CREATE TABLE incident_stat (" + ", ".join(f"{name} TEXT" for name in agg.COLUMNS) + ")"
            )
            connection.execute(
                "INSERT INTO incident_stat VALUES (" + ",".join("?" for _ in agg.COLUMNS) + ")",
                row(record_id="4", occurred_at="2026-09-30T16:00:00Z", work_kind="丁張", party="高橋").split(","),
            )
            connection.commit()
            connection.close()
            out = folder / "out"
            code = agg.main([str(csv_path), str(db_path), "--month", "2026-10", "--out", str(out), "--anonymize"])
            self.assertEqual(code, 0)
            pdf = (out / "2026-10-月次.pdf").read_bytes()
            self.assertTrue(pdf.startswith(b"%PDF"))
            self.assertIn(agg.utf16("月次ヒヤリハット集計").encode("ascii"), pdf)
            self.assertNotIn("田中".encode("utf-8"), pdf)
            self.assertNotIn("高橋".encode("utf-8"), pdf)
            svg = (out / "2026-10-地図.svg").read_text(encoding="utf-8")
            self.assertIn("<circle", svg)
            counts = (out / "2026-10-件数.csv").read_text(encoding="utf-8")
            self.assertIn("work_kind,下見,1", counts)
            self.assertIn("work_kind,丁張,1", counts)
            self.assertNotIn("田中", counts)
            hidden = agg.anonymize([{"party": "田中", "role": "作業員"}])
            self.assertEqual(hidden[0]["party"], "作業員")

    def test_september_evening_in_utc_is_october(self) -> None:
        parsed = agg.parse_time("2026-09-30T16:00:00Z")
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.strftime("%Y-%m-%d %H"), "2026-10-01 01")
        self.assertTrue(agg.in_month({"occurred_at": "2026-09-30T16:00:00Z"}, "2026-10"))
        self.assertFalse(agg.in_month({"occurred_at": "2026-10-31T15:00:00Z"}, "2026-10"))


if __name__ == "__main__":
    unittest.main()
