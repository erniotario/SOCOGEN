"""Read a Sage Gestion Commerciale `.gcm` file and write the article
catalogue as a workbook the SOCOGEN app can import.

Usage:
    python scripts/gcm_to_excel.py GESCOM_SOCOGEN_2025.gcm [-o catalogue.xlsx]

What this does and does not do
------------------------------
`.gcm` is Sage's own binary format (its records carry a "COLU"/"COLS"
marker and Sage's fixed-width fields), not a documented one. Reading it
back was done by matching known articles from the app's database against
the file and confirming the field layout around them, so only the parts
that could actually be confirmed are written out:

  * article reference, designation and family  -- confirmed, written.
  * stock per depot -- a candidate field exists on the per-depot records
    but its values could not be reconciled with any known figure, so it
    is NOT written. A wrong opening stock silently corrupts every balance
    the app derives from it, which is worse than no figure at all.
  * movements (entries and exits) -- the document lines are readable and
    do carry article, quantity and piece number, but their date and depot
    are not in the line record and the encoding used by the document
    headers could not be determined. Without a date and a depot a
    movement cannot be filed, so no movement sheet is written.

For stock and movements, export them from Sage itself (Fichier >
Exporter, or the Sage 100 ODBC driver) into a workbook whose sheets are
named Produits, Entrees and Sorties -- that is the shape the app's
importer already reads.

The sheet written here matches that importer: a `Produits` sheet with
`Stock initial` and `Magasin` left blank for the operator to fill in.
Re-importing is safe -- the app skips a product/store pair that already
carries an opening stock.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from typing import Iterator, NamedTuple

# Sage's fixed field widths, in bytes after the leading length byte.
REF_WIDTH = 19
DESIGN_WIDTH = 69
FAMILY_WIDTH = 19

# Offsets of the following fields, relative to the reference's length byte.
DESIGN_OFFSET = REF_WIDTH + 1        # 20
FAMILY_OFFSET = DESIGN_OFFSET + DESIGN_WIDTH + 1  # 90

DEFAULT_UNIT = "unité"

# Sage stores text in Mac Roman, not Latin-1: "Coût" is C-o-0x9E-t and the
# degree sign in "N°118" is 0xA1. Decoding as Latin-1 turns those into
# mojibake, and treating high bytes as non-text drops every designation
# that carries one.
TEXT_ENCODING = "mac_roman"


class Article(NamedTuple):
    reference: str
    designation: str
    family: str


def read_field(buf: bytes, offset: int, width: int) -> str | None:
    """Reads one Sage string field: a length byte, then `width` bytes of
    text padded with NULs. Returns None when the bytes are not one."""
    if offset < 0 or offset + 1 + width > len(buf):
        return None
    length = buf[offset]
    if length == 0 or length > width:
        return None
    text = buf[offset + 1 : offset + 1 + length]
    for byte in text:
        if byte < 32 or byte == 127:
            return None
    for byte in buf[offset + 1 + length : offset + 1 + width]:
        if byte != 0:
            return None
    return text.decode(TEXT_ENCODING)


# The designation field is the distinctive part of an article record: a
# length byte followed by that many printable characters. Finding those
# with a regex keeps the scan in C -- a byte-at-a-time Python loop over a
# 685 MB file takes tens of minutes.
_DESIGNATION_RE = re.compile(rb"[\x03-\x45][\x20-\x7e\x80-\xff]{3,69}")


def scan_articles(data: bytes) -> Iterator[Article]:
    """Yields every article record in the file.

    A record is recognised by its shape rather than by walking Sage's
    page structure: a reference field followed immediately by a
    designation field is specific enough that no other record type in
    the file matches it.
    """
    for match in _DESIGNATION_RE.finditer(data):
        design_at = match.start()
        # The regex run must be exactly the length the field declares,
        # or this is ordinary text rather than a field.
        if match.end() - design_at - 1 != data[design_at]:
            continue
        designation = read_field(data, design_at, DESIGN_WIDTH)
        if designation is None or len(designation) < 3:
            continue
        ref_at = design_at - DESIGN_OFFSET
        reference = read_field(data, ref_at, REF_WIDTH)
        if reference is None or len(reference) < 2:
            continue
        family = read_field(data, ref_at + FAMILY_OFFSET, FAMILY_WIDTH) or ""
        yield Article(reference.strip(), designation.strip(), family.strip())


def collect(path: str) -> list[Article]:
    """All distinct articles, newest description wins.

    Sage keeps superseded copies of a record in the file; later copies
    sit at higher offsets, so taking the last one seen per reference
    gives the current designation.
    """
    with open(path, "rb") as handle:
        data = handle.read()

    by_reference: dict[str, Article] = {}
    for article in scan_articles(data):
        by_reference[article.reference] = article
    return [by_reference[key] for key in sorted(by_reference)]


def write_workbook(articles: list[Article], out_path: str) -> None:
    try:
        from openpyxl import Workbook
    except ImportError:
        sys.exit(
            "openpyxl is required: pip install openpyxl "
            "(or run this with the project's .venv)"
        )

    book = Workbook()
    sheet = book.active
    # The app routes sheets by name; "Produits" is read as the catalogue.
    sheet.title = "Produits"
    sheet.append(
        ["Référence", "Désignation", "Famille", "Unité", "Stock initial", "Magasin"]
    )
    for article in articles:
        sheet.append(
            [article.reference, article.designation, article.family, DEFAULT_UNIT, None, None]
        )

    widths = {"A": 22, "B": 46, "C": 12, "D": 10, "E": 13, "F": 20}
    for column, width in widths.items():
        sheet.column_dimensions[column].width = width
    sheet.freeze_panes = "A2"

    book.save(out_path)


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Extract the article catalogue from a Sage .gcm file."
    )
    parser.add_argument("gcm", help="path to the .gcm file")
    parser.add_argument(
        "-o",
        "--output",
        help="workbook to write (default: <gcm name>_produits.xlsx)",
    )
    args = parser.parse_args()

    if not os.path.isfile(args.gcm):
        sys.exit(f"no such file: {args.gcm}")

    out_path = args.output or (
        os.path.splitext(os.path.basename(args.gcm))[0] + "_produits.xlsx"
    )

    articles = collect(args.gcm)
    if not articles:
        sys.exit(
            "no article records found -- this file may not be a Sage "
            "Gestion Commerciale catalogue."
        )

    write_workbook(articles, out_path)
    print(f"{len(articles)} article(s) -> {out_path}")
    print(
        "Stock initial and Magasin are blank on purpose: neither could be "
        "read from the .gcm with confidence. Fill them in, or export stock "
        "and movements from Sage into Produits/Entrees/Sorties sheets."
    )


if __name__ == "__main__":
    main()
