#!/usr/bin/env python3
"""Creates BRICKS!'s Game Center catalog in App Store Connect with the asc CLI:
achievements, leaderboards (all-time and recurring), challenges and the activity, each
with its English text and artwork.

    swiftc -O -parse-as-library BRICKS/Achievements.swift appstore/tools/gamecenter.swift -o /tmp/gamecenter
    /tmp/gamecenter render appstore/gamecenter
    /tmp/gamecenter catalog > /tmp/catalog.json
    python3 appstore/tools/gamecenter-setup.py /tmp/catalog.json

Safe to run again: anything that already exists (by vendor id, or a localization that's
already there) is left alone, so a second run only fills in what's missing. Vendor ids
can never be reused in App Store Connect, even after deleting, so check the catalog
before the first run.
"""
import json
import subprocess
import sys

APP = "6828698183"
# Recurring leaderboards start at midnight Pacific, the Monday after launch.
RECURRENCE_START = "2026-11-02T08:00:00Z"


def asc(*args, ok_fail=False):
    out = subprocess.run(["asc", *args, "--output", "json"], capture_output=True, text=True)
    if out.returncode != 0:
        if ok_fail:
            return None
        sys.exit(f"asc {' '.join(args[:3])} failed:\n{out.stderr.strip() or out.stdout.strip()}")
    text = out.stdout.strip()
    return json.loads(text) if text else {}


def listed(*args):
    return (asc(*args, "--paginate") or {}).get("data", [])


def detail_id():
    data = asc("game-center", "details", "list", "--app", APP)["data"]
    return (data[0] if isinstance(data, list) else data)["id"]


def achievements(catalog):
    existing = {a["attributes"]["vendorIdentifier"]: a["id"]
                for a in listed("game-center", "achievements", "list", "--app", APP)}
    for a in catalog["achievements"]:
        aid = existing.get(a["vendorId"])
        if not aid:
            aid = asc("game-center", "achievements", "create", "--app", APP,
                      "--reference-name", a["name"], "--vendor-id", a["vendorId"],
                      "--points", str(a["points"]),
                      f"--show-before-earned={'false' if a['hidden'] else 'true'}")["data"]["id"]
        if listed("game-center", "achievements", "localizations", "list", "--achievement-id", aid):
            print(f"  = {a['name']}")
            continue
        loc = asc("game-center", "achievements", "localizations", "create", "--achievement-id", aid,
                  "--locale", "en-US", "--name", a["name"],
                  "--before-earned-description", a["goal"],
                  "--after-earned-description", a["earned"])["data"]["id"]
        asc("game-center", "achievements", "images", "upload", "--localization-id", loc, "--file", a["image"])
        print(f"  + {a['name']} ({a['points']})")


def leaderboards(catalog, detail):
    existing = {l["attributes"]["vendorIdentifier"]: l["id"]
                for l in listed("game-center", "leaderboards", "list", "--app", APP)}
    ids = {}
    for l in catalog["leaderboards"]:
        lid = existing.get(l["vendorId"])
        submission = "BEST_SCORE" if l["keepsBest"] else "MOST_RECENT_SCORE"
        if not lid and "recurrence" in l:
            body = {"data": {"type": "gameCenterLeaderboards", "attributes": {
                "referenceName": l["name"], "vendorIdentifier": l["vendorId"],
                "defaultFormatter": "INTEGER", "scoreSortType": "DESC", "submissionType": submission,
                "recurrenceStartDate": RECURRENCE_START, "recurrenceDuration": l["recurrence"]["duration"],
                "recurrenceRule": l["recurrence"]["rule"],
            }, "relationships": {"gameCenterDetail": {"data": {"type": "gameCenterDetails", "id": detail}}}}}
            lid = asc("api", "POST", "/v1/gameCenterLeaderboards", "--confirm", "--body", json.dumps(body))["data"]["id"]
        elif not lid:
            lid = asc("game-center", "leaderboards", "create", "--app", APP,
                      "--reference-name", l["name"], "--vendor-id", l["vendorId"],
                      "--formatter", "INTEGER", "--sort", "DESC", "--submission-type", submission)["data"]["id"]
        ids[l["vendorId"]] = lid
        if listed("game-center", "leaderboards", "localizations", "list", "--leaderboard-id", lid):
            print(f"  = {l['name']}")
            continue
        loc = asc("game-center", "leaderboards", "localizations", "create", "--leaderboard-id", lid,
                  "--locale", "en-US", "--name", l["name"], "--description", l["description"],
                  "--formatter-suffix", l["many"], "--formatter-suffix-singular", l["one"])["data"]["id"]
        asc("game-center", "leaderboards", "images", "upload", "--localization-id", loc, "--file", l["image"])
        print(f"  + {l['name']}")
    return ids


def first_version(kind, flag, parent):
    versions = listed("game-center", kind, "versions", "list", flag, parent)
    return versions[0]["id"] if versions else None


def challenges(catalog, leaderboard_ids):
    existing = {c["attributes"]["vendorIdentifier"]: c["id"]
                for c in listed("game-center", "challenges", "list", "--app", APP)}
    for c in catalog["challenges"]:
        cid = existing.get(c["vendorId"]) or asc(
            "game-center", "challenges", "create", "--app", APP, "--reference-name", c["name"],
            "--vendor-id", c["vendorId"], "--leaderboard-id", leaderboard_ids[c["leaderboard"]],
            "--repeatable", "true")["data"]["id"]
        version = first_version("challenges", "--challenge-id", cid) or asc(
            "game-center", "challenges", "versions", "create", "--challenge-id", cid)["data"]["id"]
        if listed("game-center", "challenges", "localizations", "list", "--version-id", version):
            print(f"  = {c['name']}")
            continue
        loc = asc("game-center", "challenges", "localizations", "create", "--version-id", version,
                  "--locale", "en-US", "--name", c["name"], "--description", c["description"])["data"]["id"]
        asc("game-center", "challenges", "images", "upload", "--localization-id", loc, "--file", c["image"])
        print(f"  + {c['name']}")


def activity(catalog, leaderboard_ids):
    a = catalog["activity"]
    existing = {x["attributes"]["vendorIdentifier"]: x["id"]
                for x in listed("game-center", "activities", "list", "--app", APP)}
    aid = existing.get(a["vendorId"]) or asc(
        "game-center", "activities", "create", "--app", APP, "--reference-name", a["name"],
        "--vendor-id", a["vendorId"])["data"]["id"]
    asc("game-center", "activities", "leaderboards", "set", "--activity-id", aid,
        "--ids", ",".join(leaderboard_ids[v] for v in a["leaderboards"]))
    version = first_version("activities", "--activity-id", aid) or asc(
        "game-center", "activities", "versions", "create", "--activity-id", aid,
        "--fallback-url", "https://www.wilsonlam.ca/bricks/")["data"]["id"]
    if listed("game-center", "activities", "localizations", "list", "--version-id", version):
        print(f"  = {a['name']}")
        return
    loc = asc("game-center", "activities", "localizations", "create", "--version-id", version,
              "--locale", "en-US", "--name", a["name"], "--description", a["description"])["data"]["id"]
    asc("game-center", "activities", "images", "upload", "--localization-id", loc, "--file", a["image"])
    print(f"  + {a['name']}")


def main():
    catalog = json.load(open(sys.argv[1]))
    detail = detail_id()
    print("Achievements")
    achievements(catalog)
    print("Leaderboards")
    ids = leaderboards(catalog, detail)
    print("Challenges")
    challenges(catalog, ids)
    print("Activity")
    activity(catalog, ids)


if __name__ == "__main__":
    main()
