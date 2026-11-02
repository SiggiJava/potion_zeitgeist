"""Writes metrics.txt, the font metrics PotionZeitgeist.Invoicing.LetterLayout
measures invoice texts with.

Reads the regular weight of the invoice font (priv/static/fonts/inter) and
the unicode-range of each of its files from
lib/potion_zeitgeist_web/components/invoice.css, so it lists exactly the
characters a browser prints with the invoice font. Run it again after
changing the font files or their unicode-range:

    pip install fonttools brotli
    python3 priv/invoice_font/generate_metrics.py
"""

import os
import re
import unicodedata
from collections import defaultdict

from fontTools.ttLib import TTFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CSS = os.path.join(ROOT, "lib", "potion_zeitgeist_web", "components", "invoice.css")
FONTS = os.path.join(ROOT, "priv", "static", "fonts", "inter")
OUT = os.path.join(os.path.dirname(__file__), "metrics.txt")

# Characters that print nothing of their own or that the letter does not
# allow: controls, format characters, combining marks, line separators,
# private use and unassigned code points.
EXCLUDED = {"Cc", "Cf", "Mn", "Me", "Zl", "Zp", "Co", "Cn", "Cs"}


def faces():
    """The regular @font-face rules of invoice.css as (file, ranges), in order."""
    css = open(CSS, encoding="utf-8").read()
    rules = re.findall(r"@font-face\s*\{(.*?)\}", css, re.S)
    result = []
    for rule in rules:
        if not re.search(r"font-weight:\s*400\b", rule):
            continue
        file = re.search(r'url\("/fonts/inter/([^"]+)"\)', rule).group(1)
        ranges = []
        for part in re.search(r"unicode-range:\s*([^;]+);", rule).group(1).split(","):
            first, _, last = part.strip()[2:].partition("-")
            ranges.append((int(first, 16), int(last or first, 16)))
        result.append((file, ranges))
    return result


def pair_kerning(font):
    """Kerning of the 'kern' feature as {(glyph, glyph): units}.

    Within a lookup the first subtable that covers the first glyph applies;
    the values of several lookups add up, as in HarfBuzz.
    """
    gpos = font["GPOS"].table
    lookups = sorted(
        {i for r in gpos.FeatureList.FeatureRecord if r.FeatureTag == "kern" for i in r.Feature.LookupListIndex}
    )
    glyphs = font.getGlyphOrder()
    total = defaultdict(int)

    for index in lookups:
        lookup = gpos.LookupList.Lookup[index]
        seen = {}
        for table in lookup.SubTable:
            if lookup.LookupType == 9:
                table = table.ExtSubTable
            assert table.LookupType == 2 if hasattr(table, "LookupType") else True
            if table.Format == 1:
                for first, pair_set in zip(table.Coverage.glyphs, table.PairSet):
                    for record in pair_set.PairValueRecord:
                        key = (first, record.SecondGlyph)
                        if key not in seen:
                            seen[key] = getattr(record.Value1, "XAdvance", 0) or 0
            else:
                class1 = table.ClassDef1.classDefs
                class2 = table.ClassDef2.classDefs
                members = defaultdict(list)
                for glyph in glyphs:
                    members[class2.get(glyph, 0)].append(glyph)
                for first in table.Coverage.glyphs:
                    records = table.Class1Record[class1.get(first, 0)].Class2Record
                    for number, record in enumerate(records):
                        value = getattr(record.Value1, "XAdvance", 0) or 0
                        for second in members[number]:
                            seen.setdefault((first, second), value)
        for key, value in seen.items():
            total[key] += value

    return total


def main():
    fonts = {}
    owner = {}
    # The browser tries the last rule first where unicode ranges overlap, and
    # the next one when a file has no glyph for a character.
    for file, ranges in reversed(faces()):
        font = TTFont(os.path.join(FONTS, file))
        fonts[file] = font
        cmap = font.getBestCmap()
        for first, last in ranges:
            for char in range(first, last + 1):
                if char in cmap and char not in owner and unicodedata.category(chr(char)) not in EXCLUDED:
                    owner[char] = (file, cmap[char])

    units = {font["head"].unitsPerEm for font in fonts.values()}
    assert len(units) == 1, units

    widths = {char: fonts[file]["hmtx"].metrics[glyph][0] for char, (file, glyph) in owner.items()}

    kerning = defaultdict(dict)
    for file, font in fonts.items():
        by_glyph = defaultdict(list)
        for char, (owner_file, glyph) in owner.items():
            if owner_file == file:
                by_glyph[glyph].append(char)
        for (first, second), value in pair_kerning(font).items():
            if value > 0 and first in by_glyph and second in by_glyph:
                for a in by_glyph[first]:
                    for b in by_glyph[second]:
                        kerning[a][b] = value

    lines = [
        "# Metrics of the invoice font, Inter Regular as shipped in priv/static/fonts/inter,",
        "# written by generate_metrics.py. Do not edit by hand.",
        "#",
        "# w <code point> <width> <width> ...: advance widths in font units of the",
        "#   characters the font prints, for a run of code points from the first.",
        "# k <code point> <code point>:<units> ...: kerning that moves the second",
        "#   character further from the first. Kerning that moves characters closer",
        "#   is left out, so a measured line is never narrower than printed.",
        f"units_per_em {units.pop()}",
    ]

    run = []
    for char in sorted(widths) + [None]:
        if run and (char is None or char != run[-1] + 1 or len(run) == 16):
            lines.append("w %04X %s" % (run[0], " ".join(str(widths[c]) for c in run)))
            run = []
        if char is not None:
            run.append(char)

    for first in sorted(kerning):
        pairs = " ".join("%04X:%d" % (second, kerning[first][second]) for second in sorted(kerning[first]))
        lines.append("k %04X %s" % (first, pairs))

    with open(OUT, "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")

    print(f"{len(widths)} characters, {sum(len(v) for v in kerning.values())} kerning pairs -> {OUT}")


if __name__ == "__main__":
    main()
