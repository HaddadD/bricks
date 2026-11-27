#!/usr/bin/env python3
"""Checks the app's translations: that nothing on screen is missing a language, that no
translation mangles a format specifier, and that App Store Connect will accept the Game
Center text. Run it from the top of the repo.

    appstore/tools/strings-check.py                  # every locale in knownRegions
    appstore/tools/strings-check.py de fr            # just these
    appstore/tools/strings-check.py --gamecenter     # only the Game Center metadata

Exits non-zero on the first kind of problem it finds, so it can gate a commit.

What it checks:

  reachable   Every string the code looks up is a key in Localizable.xcstrings. A string
              that isn't can never be translated, however many languages ship.
  coverage    Every locale has a translation for every key. Five keys are deliberately
              untranslated (SKIP below): a bare "%lld", the app's own name, and so on.
  specifiers  A translation carries exactly the same %lld / %@ / %1$@ specifiers as its
              English key. Swapping or dropping one crashes at format time or prints
              rubbish, and the compiler cannot catch it.
  reordered   A key with two or more specifiers of different types must use positional
              specifiers (%1$@, %2$lld) in any language that reorders them.
  names       Achievement names fit App Store Connect's 30 characters in every language.
  gamecenter  metadata/gamecenter/<locale>.json matches the catalog in Achievements.swift
              exactly: no missing entries, no orphans, every row with all its fields.
"""
import json
import re
import sys
from pathlib import Path

CATALOG = Path("BRICKS/Localizable.xcstrings")
PBX = Path("BRICKS.xcodeproj/project.pbxproj")
SOURCES = sorted(Path("BRICKS").glob("*.swift"))
GAMECENTER = Path("metadata/gamecenter")

# Strings that reach the screen but must not be translated: the empty placeholder, a bare
# number, the app's own name, Apple's own feature name, and an en dash used as a spacer.
SKIP = {"", "%lld", "BRICKS!", "Game Center", "–"}

SPEC = re.compile(r"%(?:(\d+)\$)?(?:lld|ld|d|@|lf|f)")

LOOKUPS = [
    r'String\(localized:\s*"((?:[^"\\]|\\.)*)"',
    r'\bText\(\s*"((?:[^"\\]|\\.)*)"\s*\)',
    r'showToast\(\s*"((?:[^"\\]|\\.)*)"',
    r'Button\(\s*"((?:[^"\\]|\\.)*)"',
    r'Label\(\s*"((?:[^"\\]|\\.)*)"',
    r'LocalizedStringKey\(\s*"((?:[^"\\]|\\.)*)"',
    # HowToPlayView's deck: `title:` / `blurb:` on a LocalizedStringKey field.
    r'title:\s*"((?:[^"\\]|\\.)*)"',
    r'blurb:\s*"((?:[^"\\]|\\.)*)"',
]

problems = []


def fail(kind, detail):
    problems.append((kind, detail))


def known_regions():
    text = PBX.read_text()
    block = re.search(r"knownRegions = \(\n(.*?)\n\t+\);", text, re.S)
    if not block:
        sys.exit("could not find knownRegions in the project file")
    out = []
    for line in block.group(1).splitlines():
        code = line.strip().rstrip(",").strip('"')
        if code and code not in ("Base", "en"):
            out.append(code)
    return out


def multiline_literals(src):
    """`blurb: \"\"\"...\"\"\"` as Swift would build it: dedented, continuations joined."""
    out = []
    for m in re.finditer(r'(?:blurb|title):\s*"""\n(.*?)\n(\s*)"""', src, re.S):
        body, closing = m.group(1), m.group(2)
        lines = [l[len(closing):] if l.startswith(closing) else l.lstrip()
                 for l in body.split("\n")]
        out.append(re.sub(r"\\\n", "", "\n".join(lines)))
    return out


def looked_up():
    found = set()
    for path in SOURCES:
        src = path.read_text()
        for pat in LOOKUPS:
            for m in re.finditer(pat, src):
                found.add(m.group(1).replace("\\n", "\n").replace('\\"', '"'))
        found |= set(multiline_literals(src))
    return found


def split_interpolations(literal):
    """Splits a Swift literal on its `\\(…)` interpolations, counting nested parentheses
    so that `\\(Int(game.s).formatted())` is one interpolation and not two."""
    parts, buf, i = [], "", 0
    while i < len(literal):
        if literal.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(literal) and depth:
                if literal[j] == "(":
                    depth += 1
                elif literal[j] == ")":
                    depth -= 1
                j += 1
            parts.append(buf)
            buf, i = "", j
        else:
            buf += literal[i]
            i += 1
    parts.append(buf)
    return parts


def specifiers(s):
    """The specifier types in order, and whether they are positional."""
    kinds, positional = [], False
    for m in SPEC.finditer(s):
        if m.group(1):
            positional = True
        kinds.append("str" if m.group(0).endswith("@") else "num")
    return kinds, positional


def achievement_names():
    src = Path("BRICKS/Achievements.swift").read_text()
    return [m.group(1) for m in
            re.finditer(r'return i\("([^"]+)",\s*"[^"]*",\s*"[^"]*",\s*\d+,', src)]


def achievement_ids():
    src = Path("BRICKS/Achievements.swift").read_text()
    decl = src[src.index("enum Achievement: String"):src.index("static let prefix")]
    prefix = re.search(r'static let prefix = "([^"]+)"', src).group(1)
    return {prefix + raw for raw in re.findall(r'=\s*"([^"]+)"', decl)}


def check_catalog(locales):
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    keys = set(strings)

    for literal in sorted(looked_up()):
        if literal in SKIP:
            continue
        if literal in keys:
            continue
        # An interpolated literal becomes a format key; accept any specifier mix.
        parts = split_interpolations(literal)
        if len(parts) > 1:
            import itertools
            forms = {"".join(a + b for a, b in zip(parts, list(c) + [""]))
                     for c in itertools.product(["%@", "%lld"], repeat=len(parts) - 1)}
            if forms & keys:
                continue
        fail("reachable", f"the code looks up {literal[:70]!r} but it is not a catalog key")

    translatable = sorted(keys - SKIP)
    names = set(achievement_names())

    for locale in locales:
        missing = []
        for key in translatable:
            unit = (strings[key].get("localizations", {})
                    .get(locale, {}).get("stringUnit", {}))
            value = unit.get("value")
            if value is None:
                missing.append(key)
                continue

            want, _ = specifiers(key)
            got, positional = specifiers(value)
            if sorted(want) != sorted(got):
                fail("specifiers",
                     f"{locale}: {key[:50]!r} has {want} but its translation has {got}")
            elif want != got and not positional:
                fail("reordered",
                     f"{locale}: {key[:50]!r} reorders {want} to {got} without "
                     f"positional specifiers (%1$@, %2$lld)")

            if key in names and len(value) > 30:
                fail("names", f"{locale}: achievement name {value!r} is "
                              f"{len(value)} characters, over App Store Connect's 30")

        if missing:
            shown = ", ".join(repr(m[:40]) for m in missing[:4])
            fail("coverage", f"{locale}: {len(missing)} of {len(translatable)} keys "
                             f"untranslated ({shown}{', …' if len(missing) > 4 else ''})")
        else:
            print(f"  ok   {locale}: all {len(translatable)} keys translated")

    return translatable


def check_gamecenter():
    ids = achievement_ids()
    for path in sorted(GAMECENTER.glob("*.json")):
        doc = json.loads(path.read_text())
        have = set(doc.get("achievements", {}))
        for missing in sorted(ids - have):
            fail("gamecenter", f"{path.name}: no entry for {missing}")
        for orphan in sorted(have - ids):
            fail("gamecenter", f"{path.name}: {orphan} is not in Achievements.swift")
        for key, row in doc.get("achievements", {}).items():
            for field in ("name", "goal", "earned"):
                if not row.get(field):
                    fail("gamecenter", f"{path.name}: {key} has no {field}")
        for key, row in doc.get("leaderboards", {}).items():
            for field in ("name", "description", "one", "many"):
                if not row.get(field):
                    fail("gamecenter", f"{path.name}: {key} has no {field}")
        if not problems:
            print(f"  ok   {path.name}: {len(have)} achievements, "
                  f"{len(doc.get('leaderboards', {}))} leaderboards")


def main():
    only = [a for a in sys.argv[1:] if not a.startswith("--")]
    gc_only = "--gamecenter" in sys.argv

    if not gc_only:
        locales = only or known_regions()
        print(f"Localizable.xcstrings — {len(locales)} locale(s)")
        check_catalog(locales)

    print("\nGame Center metadata")
    check_gamecenter()

    if problems:
        print(f"\n{len(problems)} problem(s):")
        for kind, detail in problems:
            print(f"  {kind:<11} {detail}")
        sys.exit(1)
    print("\nAll translation checks passed")


if __name__ == "__main__":
    main()
