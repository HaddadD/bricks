#!/usr/bin/env python3
"""Adds one language's Game Center text to App Store Connect: achievements, leaderboards,
challenges and the activity, with the same artwork as English. The text comes from
metadata/gamecenter/<locale>.json; the records must already exist (gamecenter-setup.py).

    swiftc -O -parse-as-library BRICKS/Achievements.swift appstore/tools/gamecenter.swift -o /tmp/gamecenter
    /tmp/gamecenter render appstore/gamecenter
    /tmp/gamecenter catalog > /tmp/catalog.json
    python3 appstore/tools/gamecenter-localize.py /tmp/catalog.json zh-Hans           # dry run
    python3 appstore/tools/gamecenter-localize.py /tmp/catalog.json zh-Hans --apply

Safe to run again: a localization that already exists for the locale is left alone.
Game Center text on live items reaches players with the next App Store version, so run
--apply as part of a release (docs/RELEASE-PLAYBOOK.md), after the user says yes. In
TestFlight (the Game Center sandbox) it shows straight away.
"""
import json
import subprocess
import sys

APP = "6828698183"


def asc(*args):
    out = subprocess.run(["asc", *args, "--output", "json"], capture_output=True, text=True)
    if out.returncode != 0:
        sys.exit(f"asc {' '.join(args[:4])} failed:\n{out.stderr.strip() or out.stdout.strip()}")
    text = out.stdout.strip()
    return json.loads(text) if text else {}


def listed(*args):
    return (asc(*args, "--paginate") or {}).get("data", [])


def has_locale(locs, locale):
    return any(l["attributes"].get("locale") == locale for l in locs)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    apply = "--apply" in sys.argv
    if len(args) != 2:
        sys.exit(__doc__)
    catalog = json.load(open(args[0]))
    locale = args[1]
    text = json.load(open(f"metadata/gamecenter/{locale}.json"))
    todo = 0

    def step(label, exists, create):
        nonlocal todo
        if exists:
            print(f"  = {label}")
        elif not apply:
            print(f"  + {label} (dry run)")
            todo += 1
        else:
            create()
            print(f"  + {label}")
            todo += 1

    print("Achievements")
    ids = {a["attributes"]["vendorIdentifier"]: a["id"]
           for a in listed("game-center", "achievements", "list", "--app", APP)}
    for a in catalog["achievements"]:
        t, aid = text["achievements"][a["vendorId"]], ids[a["vendorId"]]
        locs = listed("game-center", "achievements", "localizations", "list", "--achievement-id", aid)

        def create(a=a, t=t, aid=aid):
            loc = asc("game-center", "achievements", "localizations", "create", "--achievement-id", aid,
                      "--locale", locale, "--name", t["name"],
                      "--before-earned-description", t["goal"],
                      "--after-earned-description", t["earned"])["data"]["id"]
            asc("game-center", "achievements", "images", "upload", "--localization-id", loc, "--file", a["image"])
        step(f"{a['name']} → {t['name']}", has_locale(locs, locale), create)

    print("Leaderboards")
    ids = {l["attributes"]["vendorIdentifier"]: l["id"]
           for l in listed("game-center", "leaderboards", "list", "--app", APP)}
    for l in catalog["leaderboards"]:
        t, lid = text["leaderboards"][l["vendorId"]], ids[l["vendorId"]]
        locs = listed("game-center", "leaderboards", "localizations", "list", "--leaderboard-id", lid)

        def create(l=l, t=t, lid=lid):
            loc = asc("game-center", "leaderboards", "localizations", "create", "--leaderboard-id", lid,
                      "--locale", locale, "--name", t["name"], "--description", t["description"],
                      "--formatter-suffix", t["many"], "--formatter-suffix-singular", t["one"])["data"]["id"]
            asc("game-center", "leaderboards", "images", "upload", "--localization-id", loc, "--file", l["image"])
        step(f"{l['name']} → {t['name']}", has_locale(locs, locale), create)

    print("Challenges")
    ids = {c["attributes"]["vendorIdentifier"]: c["id"]
           for c in listed("game-center", "challenges", "list", "--app", APP)}
    for c in catalog["challenges"]:
        t = text["challenges"][c["vendorId"]]
        version = listed("game-center", "challenges", "versions", "list", "--challenge-id", ids[c["vendorId"]])[0]["id"]
        locs = listed("game-center", "challenges", "localizations", "list", "--version-id", version)

        def create(c=c, t=t, version=version):
            loc = asc("game-center", "challenges", "localizations", "create", "--version-id", version,
                      "--locale", locale, "--name", t["name"], "--description", t["description"])["data"]["id"]
            asc("game-center", "challenges", "images", "upload", "--localization-id", loc, "--file", c["image"])
        step(f"{c['name']} → {t['name']}", has_locale(locs, locale), create)

    print("Activity")
    a, t = catalog["activity"], text["activity"]
    aid = {x["attributes"]["vendorIdentifier"]: x["id"]
           for x in listed("game-center", "activities", "list", "--app", APP)}[a["vendorId"]]
    version = listed("game-center", "activities", "versions", "list", "--activity-id", aid)[0]["id"]
    locs = listed("game-center", "activities", "localizations", "list", "--version-id", version)

    def create():
        loc = asc("game-center", "activities", "localizations", "create", "--version-id", version,
                  "--locale", locale, "--name", t["name"], "--description", t["description"])["data"]["id"]
        asc("game-center", "activities", "images", "upload", "--localization-id", loc, "--file", a["image"])
    step(f"{a['name']} → {t['name']}", has_locale(locs, locale), create)

    print(f"{todo} {'added' if apply else 'to add (rerun with --apply)'} for {locale}")


if __name__ == "__main__":
    main()
