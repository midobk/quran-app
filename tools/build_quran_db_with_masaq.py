#!/usr/bin/env python3
"""Augment a Quran SQLite DB with MASAQ plain-text columns and rebuilt index.

Usage:
  python3 tools/build_quran_db_with_masaq.py \
    --source-db assets/db/quran.db \
    --masaq-csv assets/data/MASAQ.csv \
    --output-db assets/db/quran.db
"""

from __future__ import annotations

import argparse
import csv
import re
import shutil
import sqlite3
import tempfile
from collections import defaultdict
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


def read_masaq_plain_text(masaq_csv_path: Path) -> dict[tuple[int, int], str]:
    with masaq_csv_path.open("r", encoding="utf-8-sig", newline="") as file_handle:
        reader = csv.DictReader(file_handle)
        required = {"Sura_No", "Verse_No", "Column5", "Without_Diacritics"}
        missing = required - set(reader.fieldnames or [])
        if missing:
            raise ValueError(
                f"Missing required MASAQ columns: {sorted(missing)}. "
                "Expected: Sura_No, Verse_No, Column5, Without_Diacritics."
            )

        first_non_empty_by_word: dict[tuple[int, int, int], str] = {}

        for row in reader:
            try:
                surah_no = int((row.get("Sura_No") or "").strip())
                ayah_no = int((row.get("Verse_No") or "").strip())
                word_order = int((row.get("Column5") or "").strip())
            except ValueError:
                continue

            without_diacritics = (row.get("Without_Diacritics") or "").strip()
            if not without_diacritics:
                continue

            word_key = (surah_no, ayah_no, word_order)
            # MASAQ includes multiple morphology rows per logical word.
            # Keep the first non-empty Without_Diacritics for each Column5 slot.
            if word_key not in first_non_empty_by_word:
                first_non_empty_by_word[word_key] = without_diacritics

    words_by_ayah: dict[tuple[int, int], dict[int, str]] = defaultdict(dict)
    for (surah_no, ayah_no, word_order), word_text in first_non_empty_by_word.items():
        words_by_ayah[(surah_no, ayah_no)][word_order] = word_text

    plain_text_by_ayah: dict[tuple[int, int], str] = {}
    for ayah_key, words_map in words_by_ayah.items():
        ordered_words = [words_map[index] for index in sorted(words_map.keys()) if words_map[index]]
        if ordered_words:
            plain_text_by_ayah[ayah_key] = " ".join(ordered_words)

    return plain_text_by_ayah


def ensure_ayah_columns(conn: sqlite3.Connection) -> None:
    columns = {row[1] for row in conn.execute("PRAGMA table_info(ayah)").fetchall()}

    if "text_plain" not in columns:
        conn.execute("ALTER TABLE ayah ADD COLUMN text_plain TEXT NOT NULL DEFAULT ''")

    if "text_plain_norm" not in columns:
        conn.execute("ALTER TABLE ayah ADD COLUMN text_plain_norm TEXT NOT NULL DEFAULT ''")


def ensure_index_tables(conn: sqlite3.Connection) -> None:
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS token_index(
          token TEXT NOT NULL,
          ayah_id INTEGER NOT NULL,
          PRIMARY KEY(token, ayah_id)
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_token_index_token ON token_index(token)")

    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS vocab(
          token TEXT PRIMARY KEY,
          freq INTEGER NOT NULL
        )
        """
    )
    conn.execute("CREATE INDEX IF NOT EXISTS idx_vocab_token ON vocab(token)")


def rebuild_index_and_vocab(conn: sqlite3.Connection) -> tuple[int, int]:
    conn.execute("DELETE FROM token_index")

    token_rows: list[tuple[str, int]] = []
    for ayah_id, text_plain_norm, text_norm in conn.execute(
        "SELECT id, text_plain_norm, text_norm FROM ayah ORDER BY id ASC"
    ):
        normalized_text = (text_plain_norm or "").strip() or (text_norm or "").strip()
        if not normalized_text:
            continue

        for token in sorted(set(tokenize_normalized(normalized_text))):
            token_rows.append((token, ayah_id))

    if token_rows:
        conn.executemany(
            "INSERT OR IGNORE INTO token_index(token, ayah_id) VALUES (?, ?)",
            token_rows,
        )

    conn.execute("DELETE FROM vocab")
    conn.execute(
        """
        INSERT INTO vocab(token, freq)
        SELECT token, COUNT(DISTINCT ayah_id)
        FROM token_index
        GROUP BY token
        """
    )

    token_count = conn.execute("SELECT COUNT(*) FROM token_index").fetchone()[0]
    vocab_count = conn.execute("SELECT COUNT(*) FROM vocab").fetchone()[0]
    return token_count, vocab_count


def resolve_target_copy(source_db: Path, output_db: Path) -> tuple[Path, bool]:
    if source_db.resolve() != output_db.resolve():
        shutil.copy2(source_db, output_db)
        return output_db, False

    with tempfile.NamedTemporaryFile(prefix="quran_masaq_", suffix=".db", delete=False) as handle:
        temp_path = Path(handle.name)
    shutil.copy2(source_db, temp_path)
    return temp_path, True


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Build/update quran.db with MASAQ plain text and plain-normalized token index."
    )
    parser.add_argument(
        "--source-db",
        default="assets/db/quran.db",
        help="Existing SQLite Quran DB path (default: assets/db/quran.db)",
    )
    parser.add_argument(
        "--masaq-csv",
        default="assets/data/MASAQ.csv",
        help="MASAQ CSV path (default: assets/data/MASAQ.csv)",
    )
    parser.add_argument(
        "--output-db",
        default="assets/db/quran.db",
        help="Output SQLite DB path (default: assets/db/quran.db)",
    )
    args = parser.parse_args()

    source_db = Path(args.source_db).expanduser().resolve()
    masaq_csv = Path(args.masaq_csv).expanduser().resolve()
    output_db = Path(args.output_db).expanduser().resolve()

    if not source_db.exists():
        raise FileNotFoundError(f"Source DB not found: {source_db}")
    if not masaq_csv.exists():
        raise FileNotFoundError(f"MASAQ CSV not found: {masaq_csv}")

    output_db.parent.mkdir(parents=True, exist_ok=True)

    plain_text_by_ayah = read_masaq_plain_text(masaq_csv)
    target_db, should_replace_output = resolve_target_copy(source_db, output_db)

    conn = sqlite3.connect(target_db)
    missing_plain_count = 0
    updated_rows = 0

    try:
        ensure_ayah_columns(conn)
        ensure_index_tables(conn)

        ayah_rows = conn.execute(
            "SELECT id, surah_no, ayah_no, text_norm FROM ayah ORDER BY id ASC"
        ).fetchall()

        updates: list[tuple[str, str, int]] = []
        for ayah_id, surah_no, ayah_no, text_norm in ayah_rows:
            plain_text = plain_text_by_ayah.get((surah_no, ayah_no), "").strip()
            if not plain_text:
                missing_plain_count += 1
                plain_text = (text_norm or "").strip()

            plain_norm = normalize_arabic(plain_text)
            updates.append((plain_text, plain_norm, ayah_id))

        with conn:
            conn.executemany(
                "UPDATE ayah SET text_plain = ?, text_plain_norm = ? WHERE id = ?",
                updates,
            )
            updated_rows = conn.total_changes
            token_count, vocab_count = rebuild_index_and_vocab(conn)

        ayah_count = conn.execute("SELECT COUNT(*) FROM ayah").fetchone()[0]

    finally:
        conn.close()

    if should_replace_output:
        shutil.move(str(target_db), str(output_db))

    print(f"Source DB: {source_db}")
    print(f"MASAQ CSV: {masaq_csv}")
    print(f"Output DB: {output_db}")
    print(f"Ayahs: {ayah_count}")
    print(f"Updated ayah rows: {updated_rows}")
    print(f"Ayahs missing MASAQ plain text (fallback used): {missing_plain_count}")
    print(f"Token index rows: {token_count}")
    print(f"Vocab rows: {vocab_count}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
