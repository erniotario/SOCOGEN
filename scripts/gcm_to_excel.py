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
  * purchase and sale price -- confirmed, written. They are big-endian
    doubles, the opposite byte order to the rest of the file, which is
    why an ordinary little-endian scan finds nothing. Read back against
    articles whose price is self-evident (rice at 15 900 for the 50 kg
    sack and exactly half for the 25 kg; a carton of matches at 20 500
    against 1 700 for the cartouche of ten), and 96 % of the articles
    this file shares with the app have a sale price at or above the
    purchase price.
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
carries an opening stock, and it fills a missing price without ever
overwriting one already on file.

A word on coverage. This file holds 3 083 articles, but only 87 of the
app's 723 references appear in it, and matching on designation instead
finds fewer still (73) -- the app's catalogue was recoded at some point
and largely no longer lines up with this 2025 export. The prices below
are therefore right for what they cover and cover far less than a whole
catalogue. For a full set, export the article list from Sage itself with
its price columns; the app's importer reads `Prix d'achat` and `Prix de
vente` under the usual French aliases.
"""

from __future__ import annotations

import argparse
import os
import re
import struct
import sys
from typing import Iterator, NamedTuple

# Sage's fixed field widths, in bytes after the leading length byte.
REF_WIDTH = 19
DESIGN_WIDTH = 69
FAMILY_WIDTH = 19

# Offsets of the following fields, relative to the reference's length byte.
DESIGN_OFFSET = REF_WIDTH + 1        # 20
FAMILY_OFFSET = DESIGN_OFFSET + DESIGN_WIDTH + 1  # 90

# Prices are IEEE 754 doubles stored BIG-endian -- the opposite byte
# order to everything else on an x86 file, which is why a little-endian
# scan finds nothing here. Purchase sits 16 bytes before sale.
#
# Confirmed by reading them back against articles whose price is
# self-evident: RIZ BUTTER BRAND 50KG at 15 900 / 16 500 and the 25KG at
# exactly half, a carton of matches at 20 500 against 1 700 for the
# cartouche of ten. Across the articles this file shares with the app,
# 96 % have a sale price at or above the purchase price -- the three
# that do not are real cases (oil sold off below cost), not a misread
# field.
PURCHASE_PRICE_OFFSET = 152
SALE_PRICE_OFFSET = 168

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
    purchase_price: float | None
    sale_price: float | None


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


def read_price(buf: bytes, offset: int) -> float | None:
    """Reads one price field: a big-endian double.

    Returns None rather than 0.0 for an article Sage never priced. The
    two say different things -- "no price on file" and "free" -- and the
    app draws the same distinction, so flattening them here would lose
    it before the importer ever sees the value.
    """
    if offset < 0 or offset + 8 > len(buf):
        return None
    (value,) = struct.unpack_from(">d", buf, offset)
    if value != value or value in (float("inf"), float("-inf")):
        return None
    if value <= 0:
        return None
    return value


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
        yield Article(
            reference.strip(),
            designation.strip(),
            family.strip(),
            read_price(data, ref_at + PURCHASE_PRICE_OFFSET),
            read_price(data, ref_at + SALE_PRICE_OFFSET),
        )


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
        [
            "Référence",
            "Désignation",
            "Famille",
            "Unité",
            "Prix d'achat",
            "Prix de vente",
            "Stock initial",
            "Magasin",
        ]
    )
    for article in articles:
        sheet.append(
            [
                article.reference,
                article.designation,
                article.family,
                DEFAULT_UNIT,
                article.purchase_price,
                article.sale_price,
                None,
                None,
            ]
        )

    widths = {
        "A": 22, "B": 46, "C": 12, "D": 10,
        "E": 13, "F": 14, "G": 13, "H": 20,
    }
    for column, width in widths.items():
        sheet.column_dimensions[column].width = width
    sheet.freeze_panes = "A2"

    book.save(out_path)
    _relativise_sheet_targets(out_path)


def _relativise_sheet_targets(path: str) -> None:
    """Rewrites the workbook relationships so the app can open the file.

    openpyxl records each sheet as `Target="/xl/worksheets/sheet1.xml"`,
    an absolute path. The Dart `excel` package the app imports with
    resolves a target by prefixing it -- `findFile('xl/' + target)` --
    which turns that into `xl//xl/worksheets/sheet1.xml`, finds nothing,
    and dies on a null check deep in its parser. Excel and LibreOffice
    accept both forms, so nothing looks wrong until the app refuses the
    file.

    Stripping the leading `/xl/` makes the target relative, which both
    readers accept. This is the whole reason the .gcm route had never
    actually worked end to end.
    """
    import shutil
    import tempfile
    import zipfile

    rels = "xl/_rels/workbook.xml.rels"
    with zipfile.ZipFile(path) as source:
        items = [(info, source.read(info.filename)) for info in source.infolist()]

    handle, temporary = tempfile.mkstemp(suffix=".xlsx")
    os.close(handle)
    with zipfile.ZipFile(temporary, "w", zipfile.ZIP_DEFLATED) as target:
        for info, payload in items:
            if info.filename == rels:
                payload = payload.replace(b'Target="/xl/', b'Target="')
            target.writestr(info, payload)
    shutil.move(temporary, path)


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
