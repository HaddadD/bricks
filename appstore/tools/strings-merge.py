#!/usr/bin/env python3
"""Merges translations into BRICKS/Localizable.xcstrings.

The string catalog is the source of truth for every word in the app, and Xcode rewrites
it on build, so translations are merged in rather than hand-edited: one pass per language
keeps the diff readable and makes a missing string obvious.

    appstore/tools/strings-merge.py translations/de.json              # dry run
    appstore/tools/strings-merge.py translations/de.json --apply
    appstore/tools/strings-merge.py translations/*.json --apply       # several at once

Input is JSON in either shape:

    {"locale": "de", "strings": {"<English key>": "<translation>", ...}}
    {"strings": {"<English key>": {"de": "...", "fr": "...", ...}}}

An English key that is not already in the catalog is added (its English text is the key,
as everywhere else in this project). A translation that is already there is left alone
unless --overwrite is passed, so re-running is safe.

--add-key only is useful before any translation exists: it seeds new English keys with no
localizations, which is what Xcode's own extraction would do on a build.
"""
import json
import sys
from pathlib import Path

CATALOG = Path("BRICKS/Localizable.xcstrings")


def load_pairs(path):
    """Yields (key, locale, value) from either input shape."""
    doc = json.loads(Path(path).read_text())
    default = doc.get("locale")
    for key, value in doc["strings"].items():
        if isinstance(value, str):
            if not default:
                sys.exit(f"{path}: {key!r} is a bare string but the file has no \"locale\"")
            yield key, default, value
        else:
            for locale, text in value.items():
                yield key, locale, text


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv
    overwrite = "--overwrite" in sys.argv
    add_key_only = "--add-key-only" in sys.argv
    if not args:
        sys.exit(__doc__)
    if not CATALOG.exists():
        sys.exit(f"no {CATALOG} — run this from the top of the repo")

    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]
    added_keys, added, replaced, kept = [], 0, 0, 0

    for path in args:
        for key, locale, text in load_pairs(path):
            if key not in strings:
                strings[key] = {}
                added_keys.append(key)
            entry = strings[key]
            if add_key_only:
                continue
            locs = entry.setdefault("localizations", {})
            existing = locs.get(locale, {}).get("stringUnit", {}).get("value")
            if existing is not None and not overwrite:
                kept += 1
                continue
            locs[locale] = {"stringUnit": {"state": "translated", "value": text}}
            if existing is None:
                added += 1
            else:
                replaced += 1

    verb = "writing" if apply else "would write"
    print(f"{verb}: {len(added_keys)} new key(s), {added} translation(s) added, "
          f"{replaced} replaced, {kept} already present and left alone")
    for k in added_keys:
        print(f"  + key {k!r}")

    if apply:
        # Xcode writes the catalog with sorted keys, 2-space indent and a space before
        # every colon. Matching it byte for byte keeps the diff to the strings that
        # actually changed, instead of reformatting all 150 of them.
        CATALOG.write_text(json.dumps(catalog, ensure_ascii=False, indent=2,
                                      sort_keys=True, separators=(",", " : ")) + "\n")
        print(f"wrote {CATALOG}")
    else:
        print("dry run — pass --apply to write")


if __name__ == "__main__":
    main()
