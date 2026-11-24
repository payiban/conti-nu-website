#!/usr/bin/env python3
"""Controle vóór het automatisch publiceren van de blog.

Markdown laat ruwe HTML door. Een artikel met een script of ingesloten inhoud
zou dus ongezien op de site komen. Dit script weigert dat, en controleert dat
elk artikel een leesbaar kopblok heeft en dat er iets te publiceren valt.

Gebruik:  python3 scripts/controleer_blog_bron.py   (exitcode 1 bij een probleem)
"""
import re
import sys
from pathlib import Path

BRON = Path(__file__).resolve().parent.parent / "blog" / "_bron"

VERBODEN = [
    (re.compile(r"<\s*(script|iframe|object|embed|form|link|meta|style|base)\b", re.I),
     "ingesloten code of inhoud (<{0}>)"),
    (re.compile(r"<[^>]+\son[a-z]+\s*=", re.I), "een gebeurtenis-attribuut (on…=) in HTML"),
    (re.compile(r"\b(javascript|vbscript)\s*:", re.I), "een script-link ({0}:)"),
    (re.compile(r"\]\(\s*(data)\s*:", re.I), "een data-link"),
]
KOPBLOK = re.compile(r"^---\s*\n(.*?)\n---\s*\n?(.*)$", re.S)


def controleer(tekst: str) -> list[str]:
    m = KOPBLOK.match(tekst)
    if not m:
        return ["geen kopblok tussen --- en ---"]
    kop = m.group(1)
    fouten = []
    for veld in ("titel", "datum"):
        if not re.search(rf"^{veld}:\s*\S", kop, re.M):
            fouten.append(f"veld '{veld}' ontbreekt")
    for patroon, uitleg in VERBODEN:
        treffer = patroon.search(tekst)
        if treffer:
            fouten.append(uitleg.format(treffer.group(1)) if treffer.groups() else uitleg)
    return fouten


def main() -> int:
    artikelen = [p for p in sorted(BRON.glob("*.md")) if not p.name.startswith(("LEESMIJ", "_"))]
    if not artikelen:
        print("Geen artikelen gevonden in blog/_bron — niets om te publiceren.")
        return 1
    mis = 0
    gepubliceerd = 0
    for pad in artikelen:
        tekst = pad.read_text(encoding="utf-8")
        if re.search(r"^status:\s*gepubliceerd\s*$", tekst, re.M):
            gepubliceerd += 1
        for fout in controleer(tekst):
            mis += 1
            print(f"::error file=blog/_bron/{pad.name}::{pad.name}: {fout}")
    if not gepubliceerd:
        mis += 1
        print("::error::Geen enkel artikel heeft status 'gepubliceerd' — de blog zou leeg raken.")
    print(f"{len(artikelen)} artikel(en) gecontroleerd, {gepubliceerd} gepubliceerd, {mis} probleem/problemen.")
    return 1 if mis else 0


if __name__ == "__main__":
    sys.exit(main())
