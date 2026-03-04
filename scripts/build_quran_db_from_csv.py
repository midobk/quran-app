#!/usr/bin/env python3
"""Build assets/db/quran.db from a Quran CSV (or zipped CSV).

Usage:
  python3 scripts/build_quran_db_from_csv.py \
    --input "/path/to/The Quran Dataset.csv.zip" \
    --output "assets/db/quran.db"
"""

from __future__ import annotations

import argparse
import csv
import io
import re
import sqlite3
import zipfile
from pathlib import Path


HARAKAT_AND_QURAN_MARKS_RE = re.compile(
    r"[\u0610-\u061A\u0640\u064B-\u065F\u0670\u06D6-\u06ED\u08D3-\u08FF]"
)
NON_ARABIC_OR_WHITESPACE_RE = re.compile(r"[^\u0621-\u063A\u0641-\u064A\s]")
MULTI_WHITESPACE_RE = re.compile(r"\s+")

BASE_LETTER_MAP = str.maketrans(
    {
        "أ": "ا",
        "إ": "ا",
        "آ": "ا",
        "ٱ": "ا",
        "ؤ": "و",
        "ئ": "ي",
        "ى": "ي",
        "ة": "ه",
    }
)


def normalize_arabic(text: str) -> str:
    if not text:
        return ""
    normalized = HARAKAT_AND_QURAN_MARKS_RE.sub("", text)
    normalized = normalized.translate(BASE_LETTER_MAP)
    normalized = NON_ARABIC_OR_WHITESPACE_RE.sub(" ", normalized)
    normalized = MULTI_WHITESPACE_RE.sub(" ", normalized).strip()
    return normalized


def tokenize_normalized(text: str) -> list[str]:
    if not text:
        return []
    return [token for token in text.split() if token]


def open_csv_text(input_path: Path) -> io.StringIO:
    suffix = input_path.suffix.lower()
    if suffix == ".zip":
        with zipfile.ZipFile(input_path) as archive:
            csv_names = [name for name in archive.namelist() if name.lower().endswith(".csv")]
            if not csv_names:
                raise ValueError("Zip file does not contain a CSV file.")
            csv_name = csv_names[0]
            csv_bytes = archive.read(csv_name)
            text = csv_bytes.decode("utf-8-sig")
            return io.StringIO(text)

    text = input_path.read_text(encoding="utf-8-sig")
    return io.StringIO(text)


def create_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        PRAGMA journal_mode = WAL;
        PRAGMA synchronous = NORMAL;

        CREATE TABLE IF NOT EXISTS ayah(
          id INTEGER PRIMARY KEY,
          surah_no INTEGER NOT NULL,
          ayah_no INTEGER NOT NULL,
          surah_name_ar TEXT NOT NULL,
          surah_name_en TEXT NOT NULL DEFAULT '',
          text_uthmani TEXT NOT NULL,
          text_norm TEXT NOT NULL,
          text_plain TEXT NOT NULL DEFAULT '',
          text_plain_norm TEXT NOT NULL DEFAULT '',
          translation_en TEXT NOT NULL DEFAULT '',
          text_en TEXT NOT NULL DEFAULT ''
        );

        CREATE TABLE IF NOT EXISTS token_index(
          token TEXT NOT NULL,
          ayah_id INTEGER NOT NULL,
          PRIMARY KEY(token, ayah_id)
        );

        CREATE INDEX IF NOT EXISTS idx_token_index_token ON token_index(token);
        """
    )


def main() -> int:
    parser = argparse.ArgumentParser(description="Build Quran SQLite DB from CSV/ZIP.")
    parser.add_argument("--input", required=True, help="Path to CSV or ZIP containing CSV.")
    parser.add_argument(
        "--output",
        default="assets/db/quran.db",
        help="Output SQLite DB path (default: assets/db/quran.db).",
    )
    args = parser.parse_args()

    input_path = Path(args.input).expanduser().resolve()
    output_path = Path(args.output).expanduser().resolve()

    if not input_path.exists():
        raise FileNotFoundError(f"Input file not found: {input_path}")

    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    csv_stream = open_csv_text(input_path)
    reader = csv.DictReader(csv_stream)

    required_fields = {
        "ayah_no_quran",
        "surah_no",
        "ayah_no_surah",
        "surah_name_ar",
        "ayah_ar",
    }
    missing = required_fields - set(reader.fieldnames or [])
    if missing:
        raise ValueError(f"Missing required CSV columns: {sorted(missing)}")

    conn = sqlite3.connect(output_path)
    try:
        create_schema(conn)
        ayah_rows: list[
            tuple[int, int, int, str, str, str, str, str, str, str, str]
        ] = []
        token_rows: list[tuple[str, int]] = []

        for row in reader:
            ayah_id = int(row["ayah_no_quran"])
            surah_no = int(row["surah_no"])
            ayah_no = int(row["ayah_no_surah"])
            surah_name_ar = (row["surah_name_ar"] or "").strip()
            surah_name_en = (
                row.get("surah_name_en")
                or row.get("sura_name_en")
                or row.get("surah_en")
                or ""
            ).strip()
            text_uthmani = (row["ayah_ar"] or "").strip()
            text_norm = normalize_arabic(text_uthmani)
            text_plain = text_norm
            text_plain_norm = text_norm
            translation_en = (
                row.get("ayah_en")
                or row.get("translation_en")
                or row.get("text_en")
                or ""
            ).strip()

            ayah_rows.append(
                (
                    ayah_id,
                    surah_no,
                    ayah_no,
                    surah_name_ar,
                    surah_name_en,
                    text_uthmani,
                    text_norm,
                    text_plain,
                    text_plain_norm,
                    translation_en,
                    translation_en,
                )
            )

            for token in sorted(set(tokenize_normalized(text_norm))):
                token_rows.append((token, ayah_id))

        with conn:
            conn.executemany(
                """
                INSERT INTO ayah(
                  id,
                  surah_no,
                  ayah_no,
                  surah_name_ar,
                  surah_name_en,
                  text_uthmani,
                  text_norm,
                  text_plain,
                  text_plain_norm,
                  translation_en,
                  text_en
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                ayah_rows,
            )
            conn.executemany(
                "INSERT OR IGNORE INTO token_index(token, ayah_id) VALUES (?, ?)",
                token_rows,
            )

        ayah_count = conn.execute("SELECT COUNT(*) FROM ayah").fetchone()[0]
        token_count = conn.execute("SELECT COUNT(*) FROM token_index").fetchone()[0]
        print(f"Built DB: {output_path}")
        print(f"Ayahs: {ayah_count}")
        print(f"Token index rows: {token_count}")
    finally:
        conn.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
