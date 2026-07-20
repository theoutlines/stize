# Tram-jam detection ("stalled segment")

*Design doc. Feature flag `jam_detection_show` (OFF prod / ON staging). Backend +
Flutter client. Report with the measurement numbers:
`docs/reports/2026-07-20-jam-detection.md`.*

## What it does

Belgrade trams sometimes stall — a breakdown or an incident stops one, and the
whole line stacks up behind it on a single stretch of track. This feature:

1. **detects** when several trams of one line/direction are genuinely stopped on
   an adjacent segment,
2. **shows the stalled segment** on the map as a soft amber, gently-pulsing alert
   with a glow on the affected stops, and
3. **warns downstream riders** with a quiet banner on the stops ahead of the jam,
   and on a followed vehicle heading into it.

The guiding principle is **"better to stay silent than to lie."** Everything below
is built to avoid false alarms; the tone in the UI is always an observation
("possibly stopped", "possible delay"), never a claim of a breakdown.

## The core problem: a jam vs. a data gap

The live feed refreshes each vehicle's position on its own cadence, not
continuously. So at any moment many vehicles legitimately show the *same* position
as a moment ago — simply because their board hasn't refreshed yet. Naively reading
"hasn't moved since last poll = stuck" would flag most of the fleet most of the
time.

The measurement (see the report) made this concrete: in the sampled window the
"everything frozen" surface pattern was almost entirely this **feed-refresh
cadence**, not congestion — vehicles that looked frozen for ~60–90 s were just
waiting for their next update, and buses and trolleybuses "froze" in lockstep with
trams. A real jam looks completely different: one tram *line* stops while every
other line keeps moving.

So the detector never trusts a single snapshot. It measures **how long a vehicle
has actually failed to move**, and it cross-checks the whole fleet's health before
believing any of it.

## Signals

### 1. Freeze clock per vehicle (GPS **and** stop progress)

The backend keeps a tiny last-fix table — one row per vehicle, overwritten in
place, holding its latest position and **the moment it last actually moved**. A
vehicle "moved" when EITHER its GPS shifted more than ~30 m OR its
`stops_remaining` (its position in the ordered route) advanced. The freeze age is
simply *now − last-moved*.

Requiring **both** GPS-static **and** stop-progress-static is deliberate:

- GPS alone is noisy; `stops_remaining` is a clean, coarse "did it cross a stop"
  signal that almost never twitches falsely.
- A slowly *crawling* caravan (bunched-up trams still creeping forward and crossing
  stops) keeps resetting its freeze clock, so it never reads as stalled. Bunching
  is an interval/headway problem, not a stall — it's left to the analytics
  headway-regularity metric, not alerted here.

The table is updated **opportunistically** — it rides the position refreshes the
app already makes, so detection adds no extra load. Keeping this on the backend
means a user who *just opened the app* sees an ongoing jam immediately, instead of
waiting minutes to accumulate history locally.

### 2. Feed-health gate (global suppression)

Before reporting anything, the detector checks what fraction of *all* recently-seen
vehicles (every type, every line) has moved lately. If most of the fleet is frozen
at once, that's a feed data-gap, not a city-wide jam — and the detector **stays
silent entirely**. Only when the feed is clearly healthy (things are generally
moving) does a stalled tram cluster mean something.

### 3. Terminal exclusion

A tram sitting at the first or last stop of its direction is on a normal layover,
not stuck. Vehicles within a short radius of a direction's terminus are excluded.

### 4. Cluster, not a lone vehicle

A single stopped tram is never a jam — it might be a driver break, a short hold, a
quirk. A jam requires **≥ 2 trams of the same direction**, stopped on an
**adjacent segment** (within a few hundred metres of each other). The cluster
threshold is deliberately **2, never 3** — 3 would miss real jams on short or
sparse lines.

### 5. Cascading time thresholds (KV-configurable)

How long a tram must be frozen before it counts scales with how strong the
surrounding evidence is:

| situation | freeze threshold | KV key |
|---|---|---|
| lone vehicle (never surfaced on its own) | 300 s | `config:jam_t_single` |
| ≥ 2 same-direction on an adjacent segment | 180 s | `config:jam_t_cluster` |
| …plus a confirmed substitute bus on the line | 90 s | `config:jam_t_substitute` |

Plus:

| what | default | KV key |
|---|---|---|
| minimum vehicles in a cluster | 2 | `config:jam_cluster_min` |
| how far downstream the banner reaches, in **travel time** | 600 s | `config:jam_downstream_horizon_s` |

All thresholds live in remote config (KV), not in code, so they can be tuned
without a redeploy — which matters because they are **preliminary** (see the
limitation below).

### 6. Substitute buses on a tram line

When trams are pulled from a line, replacement buses run in their place. The
vehicle type is read from its fleet id, so a bus running a tram line is
recognisable. This gets **its own neutral notice** ("buses are running instead of
trams on line N") — a substitution is not necessarily a breakdown (planned track
works also cause it). When it coincides with stalled trams of the same line, it
**corroborates** a jam and relaxes the freeze threshold for that line (the 90 s row
above).

### 7. Cross-check with official route alerts

The app already ingests official route-change announcements. If an active alert
names the jammed line, that alert is the **authoritative cause** — the UI shows the
alert's own wording instead of our inference. Without a matching alert, our signal
always stays in the softer observation tone.

## What the user sees

- **The stalled segment** on the map: an amber, softly-pulsing line drawn along the
  route between the stopped trams, sitting above the route line but beneath the
  stop pins, with the affected stops glowing the same amber. The pulse is a cheap
  opacity animation that runs *only while a jam is on screen*.
- **Geometry honesty gate:** the red segment is only drawn where the route's map
  geometry faithfully carries the stopped vehicles. On the minority of lines whose
  map shape runs well off the real stops, drawing a segment would paint the wrong
  street — so there we show **only the stop glow**, which is a first-class visual,
  not a downgrade.
- **A delay banner** on the affected stops (those under the segment and the ones
  downstream within ~10 minutes of travel), in the app's language (EN/RU/SR).
- **A jam-mode button** that appears on the map only while there are active jams. It
  toggles the map between "fit to all jams" and the normal view (no navigation, no
  back button). It shows a **red count badge only when a jam is actually relevant to
  you** — near you, on the line you're following, or at the stop you have open;
  jams elsewhere in the city keep the button present but quiet, so it never nags.
- **A Nearby row** and a **follow-bar warning** when a jam touches your current
  context or lies ahead of the vehicle you're following (same direction, still
  ahead of it — not one you've already passed or one going the other way).

## Storage & cost

The detector's memory is a single small last-fix table, kept **separate** from the
transport-history analytics. It's written only from position refreshes the app
already performs — no extra polling — and the map's heavy geometry (drawing and
gating the segment) runs on the client, not the server.

## Known limitation — thresholds are preliminary

The window in which this was measured captured the feed-cadence baseline **but not
a live jam** (jams are intermittent, and the sampled window happened not to contain
one). So the thresholds are validated for one thing — *they do not fire on the
normal feed cadence or a lone layover* — but **not yet calibrated against the
magnitude of a real jam**. That is exactly why every threshold is a remote config
value: the first time a genuine jam is captured, they'll be re-tuned from the real
numbers without shipping a new build.
