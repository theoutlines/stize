# Stigla — Fleet Identification

Goal: from the garage number in the real-time API (`P80209`, `P93052`, …), show
the rider **which vehicle they're about to board** — model, age, air
conditioning, low floor — and let them compare options. Data source:
`assets/data/fleet_models.json`, assembled from public enthusiast rosters and
cross-checked against API observations (~1141 vehicles).

## 1. How the number works

`P` + an integer. The decoding was confirmed vehicle-by-vehicle:

- **8xxxx — GSP electric fleet**: `n − 80000` = fleet number (KT4 trams since
  2016 carry a painted `2000 + fleet`, so car "2209" = P80209).
- **9xxxx — GSP buses**: `n − 90000` = painted number (bus "3052" = P93052;
  minibuses "7174" = P97174).
- **2xxxx, 3xxxx, 45xxx, 7xxxx — private operators.** Granularity is blocks of
  100–500 numbers, each = one operator (e.g. 70xxx–71xxx is the largest, 500+
  vehicles).
- **P1–P999 — junk**: placeholder ids the source emits when there's no real
  number. Never match, dedupe, or show a "model" for these. (Junk normalization
  already exists in the backend analytics collection — the matcher follows the
  same rule.)

## 2. Matching algorithm (v2)

Three levels, exact to coarse:

```
resolve(garageNo):
  n = int(strip 'P')
  if n < 1000 → return UNKNOWN_JUNK

  # 1) exact per-vehicle map (~1089 private vehicles)
  if str(n) in fleet.vehicles:
     modelKey = fleet.vehicles[str(n)]
     return fleet.models_catalog[modelKey]   # full model attributes

  # 2) class ranges; on nesting the NARROWER range wins
  best = argmin(b-a) over classes.ranges where a <= n <= b
  if best → return best

  # 3) UNKNOWN (show only the API type, no model)
```

The "narrower range wins" rule matters: some electric-bus classes are nested
inside operator blocks. Cache the `resolve` result per number — numbers are
immutable within a session.

Two kinds of answer: **model-hit** (level 1 — attributes from `models_catalog`)
and **class-hit** (level 2 — class attributes; for private operator classes these
are averaged values with `confidence: per-vehicle`, marked "~" in the UI). The
matcher must be **total**: any number yields a model, a class, or an honest
UNKNOWN. Never crash, never guess.

## 3. Comparison attributes (what a rider sees)

By passenger value, descending — use this same order in the card UI:

| Field | Type | Why the rider cares |
|---|---|---|
| `ac` | bool | The main question of a Belgrade summer. ❄️ / "sauna" icon |
| `low_floor` | bool | Strollers, luggage, elderly. ♿ icon |
| `years_built` | [from,to] | Shown as age, from the range midpoint |
| `comfort_score` | 1–5 | Summary scale (see §4) — for sort/badge |
| `nickname_sr` | string | Local colour ("Kata", "Španac", "trola") — big; model small |
| `capacity`, `articulated`, `length_m` | — | "Articulated — you'll fit even at rush hour" |
| `powertrain` | enum | diesel / cng / trolleybus / tram / electric_battery / electric_ultracap — for the eco badge |
| `usb` | bool | Only on the newest vehicles |
| `human_note` | string | Ready one-sentence card text with character |
| `confidence.*` | verified/assumed | Render assumed fields with "~" or grey; don't pass them off as fact |

`operator` exists on non-GSP classes — show it in details.

## 4. Comfort scale (comfort_score)

Precomputed in the JSON, but the formula is fixed so it can be recomputed on
updates:

```
score = 1
+2 if ac
+1 if low_floor
+1 if year_to >= 2019
−1 if year_to <= 1990
clamp(1..5)
```

Anchors: 1 = old KT4/BKM (hot, steps), 3 = solid middle (Solaris 2013,
Ikarbus), 5 = the newest classes. In the UI it's not a number but five dots or a
"retro / ok / comfort" badge.

## 5. UI behaviour

- In the arrivals list, compact next to the time: type icon + ❄️/♿ + age badge.
  Tap → model card with a visual (see §8), nickname, note, full attributes.
- If UNKNOWN, invent nothing: just type and number. For UNKNOWN_JUNK, don't show
  the number at all.
- "Which one to ride" comparison: when ≥2 vehicles of different classes are
  approaching a stop, offer a "by comfort" sort. Real case: line 12 — "the Kata
  in 3 min or the Bozankaya in 9" is a genuine choice; that's the whole point.
- Graceful degradation: the catalog is a static asset; if the JSON fails to
  parse, the feature silently switches off and transit functions are unaffected.

## 6. Known gaps (do not block release)

After adding private operators, the only uncovered vehicles are ~40 suburban
"Lasta" vehicles across a few number blocks — the matcher returns UNKNOWN and the
UI shows only the type. Closed by saving the relevant roster pages. Trailer cars
attached to GT6 trams don't appear in the API — ignore.

A passenger insight worth surfacing: the private fleet is younger than GSP's —
mostly 2017–2026, whereas GSP's core is Solaris 2013 and trams from 1967–1990. In
Belgrade, "a private operator is coming" often means "something new is coming".

## 7. Data updates

Quarterly (or on delivery news): re-save the rosters, run the parser, rebuild the
ranges and the vehicle map. Expected near-term changes: more new-generation
buses, retirement of mid-2000s trolleybuses, and a batch of new electric buses.

**Semi-automation via the analytics vehicle aggregate**: first/last-seen fields
from the "vehicle × line" aggregate act as a fleet-life detector. A vehicle that
stops appearing in the API → a retirement candidate; a new number range appearing
→ a delivery arrived. The quarterly check starts from that diff, not from a
manual roster comparison.

## 8. Card visual

The card's main visual is **the vehicle model, not a photo**. Production is
AI-assisted, not hand-drawn:

- **Step 1 — interior diagram**: top view (seats, doors, low-floor zone,
  articulation, wheelchair space), SVG from manufacturer floor plans + the app
  style guide. Light interactivity: tap a zone → label, zoom. Top classes by
  fleet size first.
- **Step 2 (later, gated)** — a "spin around" view: photo → AI-3D → glTF viewer
  or sprite frames with drag-to-rotate. Top classes only, after a single-class
  pilot.

Photos are an optional secondary layer: roster photos are under their authors'
rights and can't be shipped in the app; own photography or Wikimedia Commons with
attribution are acceptable. Build the visual key from the class `id`:
`assets/fleet/{id}.webp` (diagram) / `assets/fleet/{id}/` (spin frames).
