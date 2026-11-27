"""Restore JSON files under the given path whose only change is `built_at`.

The GTFS build writes a fresh built_at into its metadata on every run, so
without this a feed that did not change still looks changed to git.
"""
import json
import subprocess
import sys


def strip(o):
    if isinstance(o, dict):
        return {k: strip(v) for k, v in o.items() if k != "built_at"}
    if isinstance(o, list):
        return [strip(x) for x in o]
    return o


path = sys.argv[1]
changed = subprocess.run(
    ["git", "diff", "--name-only", "--", path], capture_output=True, text=True, check=True
).stdout.split()
for f in changed:
    if not f.endswith(".json"):
        continue
    old = subprocess.run(["git", "show", f"HEAD:{f}"], capture_output=True, text=True)
    if old.returncode != 0:
        continue
    try:
        with open(f, encoding="utf-8") as fh:
            same = strip(json.loads(old.stdout)) == strip(json.load(fh))
    except (ValueError, OSError):
        continue
    if same:
        subprocess.run(["git", "checkout", "--", f], check=True)
        print(f"only built_at changed: {f}")
