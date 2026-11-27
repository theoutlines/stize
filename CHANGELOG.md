# Changelog

Notable, human-readable changes to Stiže. Newest first. This is the product
history (what changed for riders and developers), not a commit log.

The format loosely follows [Keep a Changelog](https://keepachangelog.com).

## 2026-11-27

### Changed (afternoon)
- **One search on phone and desktop.** Desktop search now shows the same
  results as the phone: nearby matches first, then lines with their coloured
  badge, stops, and streets and places. Phones now find streets and places
  too (Knez Mihailova, Kalemegdan); tapping one centres the map on it. A
  found place shows the same badge it has on the map (museum, park, cafe…);
  a street or address shows a neutral grey one, and a stop shows its map
  pin (type colour and glyph) instead of a generic pin.
- **"Live unavailable" sits where live vehicles would be.** On a stop board
  the note now heads the timetable itself (one line with the offline mark)
  instead of a separate strip at the top over "By timetable".
- **Feedback opens the form.** "Share feedback" in the menu goes straight to
  the message form; the extra screen with a GitHub Issues link is gone.
- **Stop links open on the map.** A `/stop/<id>` link opens the home map with
  that stop in its sheet (phone) or panel (desktop), the same view as a tap
  on the map. The old standalone stop page with its own small map is gone.
- **A skeleton while a stop loads.** The stop board shows the shape of its
  cards while arrivals load, instead of an icon and "Checking what's on the
  way…".
- **One locate button.** The button left of the search is always the
  crosshair; it no longer turns into an arrow after the map is moved.

- **A line from search opens on the map.** Its route and stops are drawn on
  the home map with the line bar to close it, like a followed line, instead
  of a separate route screen. Closing returns to where you were.

- **Nearby loads with a skeleton too.** While the Nearby list loads it shows
  the shape of its cards, like the stop board, instead of an arrow and a line
  of text.
- **"Back" is a left chevron** everywhere.

- **Coverage lives on the map.** Coverage (behind its flag) is no longer a
  separate screen with its own map: it opens from the menu as a level, like
  Settings, and the home map itself switches to the transit heat, takes in the
  whole city and hides stops and vehicles; back returns the camera. The level
  holds the type filters (All, Tram, Trolleybus, Bus, now with the vehicle
  icons and the app's chip style, scrolling sideways) and a short density key.
- **Coverage as flow lines.** City routes are cut into stop-to-stop
  segments (stations pair up both directions), each drawn once from a
  route's own shape and pinned to its stations, with the weekday trips of
  every route along it: a few trips is a hairline in the type's deep tone, a
  busy segment a thick stroke running to a light tint (bus blue to cyan,
  trolleybus orange to yellow, tram red to coral). A narrow heatmap of the
  routes' points glows under the strokes: it adds up where routes share a
  street but its radius and ramp cap how far and how bright. The basemap
  turns into a quiet grey data-viz variant while Coverage is open; tram rails
  hide. Data: backend `build-coverage-flow.mjs` → `/api/v1/coverage/flow`
  (~150 KB gzip) and `/api/v1/coverage/glow` (~700 KB gzip).
- **One mark for "no stop here".** "No stops nearby" and "Can't find that
  stop" now share a crossed-out stop sign instead of a crossed-out arrow and
  a crossed-out crosshair; a stop that can't be found shows no ⋯ menu.
- **"Back to 29" in one pill.** On desktop the off-screen hint and the
  "Back to vehicle" button are one pill: an arrow toward the vehicle, "Back
  to" and the line badge.

### Fixed (afternoon)
- **City shows the offline mark on a network error,** not a crossed-out
  location arrow.
- **Closing the search lowers the sheet again.** On phones the Nearby sheet
  used to stop near the top after the search was closed; it now settles back
  to its resting height.

### Removed (afternoon)
- Pinning a line from search (pinned lines were saved but never shown
  anywhere), the "zoom in to see transport" hint, the vehicle model card that
  had lost its entry point, and 30 icons nothing used any more. The font now
  holds 47 icons; codepoints are pinned in `tool/icons/codes.json`, so
  adding or removing an icon never shifts the others.

### Changed
- **Faster web app.** The site is now built for WebAssembly: on Safari 18.2+
  and current Chrome and Firefox the map's sheets and menus animate more
  smoothly and the app loads faster. Older browsers get the same app as
  before.

### Fixed (backend)
- **KV reads cut about tenfold.** Flags and settings now live in one KV value
  as well as their own keys, so the per-minute cron reads one key instead of
  about fifteen. On 26 Nov the account used half of the free 100k KV reads a
  day; now a day of cron costs a couple of thousand. Keys changed by hand in
  the dashboard apply within an hour, or at once via
  `POST /api/v1/admin/config/rebuild`.

### Changed (developers)
- **A check that keeps the code small.** CI now reports files over 500
  lines (existing ones may not grow), dead files, widgets, exports and UI
  strings, and copy-pasted blocks, and prints how many lines a branch adds.
  See "Keep the code small" in CONTRIBUTING. First pass: about 1,000 lines of
  dead code and 25 unused strings removed; the map's floating controls,
  diagnostics box and vehicle layout moved out of the 6,000-line map screen
  into small widgets and a tested class. Nothing changes for riders.
- **Big files split by job.** Backend analytics (913 lines) and the stop
  sweep (650) are now folders of small modules; vehicle movement, the follow
  sheet and the Nearby list each lost 200 to 300 lines to their own files.
  The old import paths still work. Nothing changes for riders.
- **No backend file over 500 lines.** The worker's routes moved out of
  `index.ts` into `routes/` (transit, write, city, admin) and jam detection
  into `lib/jam/`; the map's images, vehicle marker and style palettes are
  their own files. The size check skips generated files (the design tokens).
- **The structure check is now strict.** CI fails on a new oversize file,
  dead code, an unused string or a copy-pasted block, and on a baseline that
  still lists debt already paid off.
- **Zero analyzer issues, no unused packages or assets.** The 27 analyzer
  notes are fixed and CI now fails on any new one. One was a real crash risk:
  the jam overlay read the theme after an await, so closing the map while it
  drew could throw; it now reads the colour first. The check also reports
  unused packages and asset files: `fl_chart`, `cupertino_icons`, the direct
  `geolocator_web` pin and an unused photo are gone, so the build is smaller.

## 2026-11-26

### Added (late night)
- **Where you are facing.** On a phone your location dot shows a soft cone
  in the direction the phone is pointing, like Yandex Maps, and it stays true
  when the map is rotated. On iPhone the compass is asked for once, on the
  same Locate tap as location; Android needs no ask. No compass (desktop, or
  permission declined), no cone: the dot looks as before.

### Fixed (late night, vehicles)
- **Vehicles stay on the road.** Until a route's shape had loaded, a vehicle
  was driven in straight lines from stop to stop, across the blocks between
  them; a vehicle on a stop board stayed on that line for up to 30 s even
  after the shape arrived, and a shape that failed to load once was never
  retried. Now a vehicle without its shape stands at its GPS fix, every
  vehicle of a direction moves onto the road the moment its shape loads, and
  a failed shape is fetched again.

### Changed (late night)
- **Notices open the list.** The delay notice in Nearby, the delay and bus
  substitution notices on a stop board and the GSP route alerts are one flat
  strip, edge to edge on mobile and rounded in the desktop island, like the
  guide strip. They scroll with the list instead of sitting over it as an
  inset card; a tap on a delay shows the affected stops.

### Changed (evening)
- **Our own icon.** The browser tab, home-screen and app-install icons show the
  Stiže mark (a rounded signal-green square) instead of the Flutter logo.

### Fixed (night)
- **Address search stays in Belgrade.** Desktop search no longer mixes in
  addresses from other countries ("830" used to bring Taiwan and the US):
  places come only from the area our lines serve, Mladenovac to Borča.

### Added (night)
- **Search by stop number.** Type the number from the stop's sign (830) and
  that stop comes first; from three digits, stops whose number starts with
  them follow (830 also finds 8300), then stops whose name has the digits.
  A line whose number is exactly what you typed (83) stays above the stops.
  Works offline too. Every stop in search results shows its number on the
  right, on mobile and desktop.

### Fixed (late evening)
- **No "Finding lines" flash when the sheet moves.** Raising the Nearby sheet
  to the top rebuilt the list and fetched it again; it keeps its data now.
- **A flick down only puts the sheet away.** A quick flick at the top of the
  full sheet collapses it without refreshing; a slow pull refreshes.

### Changed (late evening)
- **Own refresh icon.** The pull to refresh button uses a refresh arrow from
  the Stiže icon set; no Material icons are left in the app.

### Fixed (evening)
- **Pull to refresh works again.** The stiffer stretch had made the refresh
  point unreachable with a trackpad and hard by finger; a deliberate pull now
  refreshes, and the spinner shows for at least a moment. The stop board and
  the stop link page refresh on a pull too. The refresh button is a white
  circle that reads on any row.

### Changed (evening, design system pass)
- **Route alerts are calm.** No more red: a disruption shows on a stronger
  grey with a warning icon, an ordinary notice on the light grey with an info
  icon. The jam banner takes the system jam colour; the empty state icon and
  the search pill icons sit on the system sizes.

### Changed (evening)
- **Stiffer stretch everywhere.** Every list and sheet, outside sheets too,
  bounces with one stiffer resistance, by touch and by trackpad; a flick no
  longer stretches half the screen. The stop link page and the vehicle sheet
  use the same list, with pull to refresh in the first card's colour instead
  of the Material spinner.
- **Follow view on the type scale.** Route times and the line about the
  vehicle are 16/24, the vehicle's nickname and the photo credit 12/16, the
  chips are pills with 12/16 text. The guide strip's text and icons use the
  system greys. The menu's backdrop is the system scrim; the stop sheet has
  no backdrop, the map stays live.

### Changed (afternoon)
- **One list on every platform.** The desktop island now scrolls with the
  same list as the mobile sheet: Nearby, a stop board, a followed vehicle,
  My stops, the guide, settings and feedback. The first and last cards
  stretch past the ends and spring back on desktop too, including with a
  trackpad, without the browser's own frozen page bounce.
- **Close button lines up.** On desktop the close in the follow card and in
  the level header sits on the same right edge as the times and cards below.

### Fixed
- **Follow sheet drags by its body again.** Since the levels started rising as
  high as Nearby, the sheet re-snapped on every follow refresh, so only the
  handle could move it.
- **Map point drag on iPhone.** The centre dot is now drawn by the map itself:
  dragging the map no longer keeps dropping the dot after a short move, and a
  dropped dot stays on its spot when the sheet moves.
- **Pull to refresh on the full Nearby sheet.** At the top detent a pull down
  at the top of the list now stretches the first card and refreshes instead
  of shrinking the sheet; a quick flick down collapses it. The pull is also
  shorter.

## 2026-11-25

### Fixed (night)
- **One locate button on desktop.** "Where am I" lives only in the search
  pill, as on mobile; the extra round button on the right is gone.
- **Skeleton while the app loads.** Instead of a "Loading Stiže…" line on a
  green-tinted screen, the first screen appears as a skeleton in its real
  layout (buttons, search pill and sheet on phones; the left panel and right
  controls on desktop) over the map background, in the theme the rider chose.
- **Theme switch keeps the map working.** Switching light/dark with the new
  basemap no longer aborts the map setup: stop pins, vehicles and the
  location dot are replaced and re-tinted for the new theme.

### Changed (night)
- **New basemap: Stiže Standard.** Our own map style replaces MapTiler
  Streets in both themes: warm built-up areas, calm blue-grey streets, street
  names in Serbian Latin, buildings that rise into soft 3D when the map is
  tilted. Places show as icons in coloured circles by kind: landmarks
  (museums, theatres, churches, hospitals, stations, universities, malls)
  from zoom 15, everyday places (hotels, pharmacies, supermarkets, cinemas)
  from 16, every named café, bar, shop and street artwork from 17. Bus and tram stops come
  only from our own stop layer. Place colours never use the tram, bus or
  trolleybus hues.

### Changed (evening)
- **Levels open as high as Nearby.** A stop, the guide and the other levels
  on mobile now rise to just under the close button, like the Nearby list;
  before they stopped about a tenth of the screen lower.
- **Nearby edges stretch.** On mobile, pulling the list past its top stretches
  the first card and shows the refresh button inside the stretch; it holds
  there while the list refreshes. Pulling past the bottom stretches the last
  card, which springs back. The stop board's last card stretches the same
  way, and a stretching card hides its bottom divider.
- **Desktop search is the mobile pill.** Locate | where the list is |
  search, above the panel; a click turns it into the field.
- **Guide strip in Nearby.** On mobile and desktop alike the guide nudge is a
  flat row that opens the list flush with the sheet's (island's) top, in the timetable cards' neutral
  fill; it stretches and refreshes like the first card. The first-launch
  nudge has a × that hides it for good; the airport, station and night
  strips carry a chevron and leave on their own.
- **Carousel dots** sit in their own band above the card's data again, over
  both cards while you swipe.
- **Route alerts in English.** Alerts stored before translations existed are
  translated on the next daily refresh, so an English interface no longer
  shows a Serbian notice.
- **Route alerts match and age properly.** Lines and stops from Cyrillic
  notices are matched in Latin ("КЦ1" is KC1, "ECO 1" is EKO1), and a
  permanent change with no end date stops showing a month after it starts.

### Changed
- **Stop board cards.** The line number sits on a white plate; the time has
  "min" beside it; under the time is where the vehicle is now ("1 stop away",
  "At the stop"), led by a small dot that pulses while it moves. The next
  vehicles of the same direction follow in one line ("next 13 · 26 · 40 min",
  "još" in Serbian). Fleet badges, age, interval and the ↑↓ change badge are
  gone from the board: model and amenities live on the follow screen.
- **A vehicle that stopped moving** (its position unchanged for 2 minutes)
  loses the dot, and its time dims with "≈": we no longer trust it.
- **Vehicles waiting at the terminus** say "Starts here" ("Polazi odavde").
- **Timetable section.** Timetable times sit below the live cards under one
  "By timetable" header, never mixed into the live run; each card shows the
  line, the destination, the clock time and the next two.
- **Nearby** uses the same card, with the stop and its distance under the
  destination. On desktop a line's directions page with a trackpad swipe, the
  dots or the arrows that appear on hover.
- **Follow screen in one sheet** (mobile): the followed vehicle heads the sheet
  as a card in its line colour ("2 stops to Batutova"), then the route as a
  line with stops, the vehicle on it and your stop marked, then the vehicle
  itself: photo, model and nickname, short chips, a line about it, maker and
  operator. A stuck vehicle says so on its stop ("Stuck · 3 min", "U zastoju")
  and the times after it turn approximate.
- **Close button.** On mobile the sheet's close rides above its right edge and
  pushes the map buttons up when it reaches them; on desktop it stays in the
  header. Every close is the same round button. In My stops a filled star
  replaces the × that removed a stop.
- **Desktop island** hugs its content up to the window height instead of
  leaving an empty strip below the list.

- **Line plate shows the vehicle type** (tram, trolleybus, bus icon before the
  number) on the board, timetable, Nearby and the follow head; colour alone
  doesn't tell a visitor tram from bus. Icons redrawn on one grid: the tram is
  low-floor with a straight pantograph, trolleybus and bus stand on wheels.
- **Follow head switcher:** the vehicles of the line and direction on your
  stop's board ("1 · 3 · 7 min"); a tap follows another one.
- **Line filter grouped by type:** trams, trolleybuses, buses, each led by
  its icon.
- **Nearby around a point on the map:** drag the map and your dot sits on
  its centre; let go and Nearby recomputes there. The locate button brings it
  back to you. The home sheet rests lower, about one and a half cards.
- **Nearby** has the board's "By timetable" split, its cards line up, and a
  line's live directions never share a card with timetable-only ones.
- "Starts here" cards are at full brightness; the follow route always has
  times and shows a vehicle standing at a stop as at it.

### Fixed
- The map follows a tapped vehicle again (follow engages even when the entry
  camera flight is interrupted).

## 2026-11-24

### Changed
- **No phantom arrivals.** A timetable departure is shown only if its trip has
  not left the terminus yet. A trip already on the road without a live vehicle
  either runs untracked or doesn't run, so it is no longer listed ("tram 5 in
  1 min" at a stop 11 min from the terminus). Scheduled vehicles are no longer
  drawn on the map at all, for the same reason.
- **Stop header:** the star button and the "Something wrong with this stop?"
  row are gone. A More button right after the stop name holds Add to My Stops
  and Report a problem; a small star after the name shows the stop
  is in My Stops. The list ends with its last card.
- **Line filter:** "All lines" is picked by default; unpicked line chips are
  neutral and a picked one takes its line colour. From "All lines" a tap picks
  just that line, further taps add or remove lines. Only lines with an arrival
  get a chip.

### Removed
- **By time / By comfort sort** on the stop board. Comfort badges stay on the
  cards.

## 2026-11-22

### Added
- **Stiže design system (behind the `ds_stize` flag)** — the app's own design
  system, forked from the Growth Test Planner's: Uncut Sans everywhere, a 4px
  grid, dark and light themes, a signal-green accent and a separate transit
  colour layer. Tokens live in `design/tokens/` and generate the Flutter theme.

### Changed
- **Trolleybus orange** is slightly darker (`#E8701A`) so white line numbers
  read on it.

### Removed
- **Russian UI.** The app now ships English and Serbian (Latin). Devices set to
  Russian fall back to English; a saved Russian choice resets to "System".
- **Legacy `theoutlines.xyz` addresses retired** — Stiže now lives entirely on
  its own domain (web `stize.app`, API `api.stize.app`, staging API
  `api-staging.stize.app`). All three old `theoutlines.xyz` hosts —
  `stigla.theoutlines.xyz` (redirect), `stigla-api.theoutlines.xyz` (prod API)
  and `stigla-api-staging.theoutlines.xyz` (staging API) — no longer resolve.
  There are no external clients, so nothing migrates. (Infrastructure names stay
  `stigla-*`; only the public `theoutlines.xyz` hostnames were removed.)

## 2026-07-21

### Added
- **Drawer "about & contact" footer** — an in-app feedback form (a message + an
  optional contact; the email is never exposed), a link to public GitHub issues,
  open-source licenses (AGPL-3.0), an in-app privacy policy, an optional donate
  link, and a dimmed version line. The feedback form ships behind a flag, off on
  prod until reviewed.
- **Desktop panel collapse** — a Google-Maps-style tab collapses the context
  panel to the screen edge and back; the search and burger float above it as
  separate islands, and the map reclaims the space when collapsed.

### Changed
- **Rebrand: Stigla → Stiže, live on [stize.app](https://stize.app)** — the
  product is now **Stiže** (Serbian for "arrives"). The app name updates
  everywhere it's shown (EN/RU/SR, title, PWA install name, About), and prod
  serves from `stize.app` (API `api.stize.app`). The old
  `stigla.theoutlines.xyz` address keeps working and 301-redirects to `stize.app`
  with the path preserved, so existing bookmarks and deep links migrate cleanly.
  Internal infrastructure names are unchanged.
- **Global search everywhere** — the mobile nearby sheet uses the same search as
  desktop: nearby matches first, then stops/lines; it works even before location
  is enabled.
- **Unified bottom sheets** — stop, vehicle-info and "About the vehicle" are one
  full-width sheet with a shared handle and detents; "About the vehicle" opens
  in-place with a back arrow (no separate modal); the map shifts up so the stop
  stays visible above the sheet.

## 2026-07-20

### Added
- **Vehicle-mode toggle** — on-demand vehicles (shown only in context: a tapped
  stop's arrivals and a followed vehicle) is now the default, with a single map
  toggle to switch back to the background "aquarium." The choice persists locally.
- **Adaptive context panel** — on desktop the nearby / stop / vehicle views become
  a persistent left panel beside a full-height map with a global search; on mobile
  they stay as unified bottom sheets with one back-navigating flow.
- **ETA-change badge** — the stop shutter flags when a vehicle's predicted arrival
  time shifts, diffed against the absolute arrival time (not ticking minutes).

### Changed
- **Arrivals list dedup** — live and scheduled rows of the same line no longer
  double-count; scheduled entries collapse into one cell, and the list is ordered
  so nothing scheduled ever sits above a live arrival.

### Behind the scenes (not yet rider-visible)
- **Anonymous product analytics** — a small set of enumerated, identity-free usage
  events (see the Privacy section of the README), collection off by default.
- **Citywide reliability history** — a background sentinel sweep so accumulated
  history covers every line, not just the stops riders open; plus a v2 analytics
  aggregate (per direction, headway histograms, best-effort schedule delay). The
  screens that surface it are still off.
- **Tram-jam detection groundwork** — the backend now records the data needed to
  detect a whole tram line stalling on one segment; the rider-facing warnings stay
  behind a flag until the thresholds are calibrated on a real jam.

## 2026-07-14

### Added
- **GPU vehicle rendering** — moving vehicles are drawn as a single batched
  MapLibre symbol layer (sub-linear in vehicle count) instead of per-vehicle
  widgets.
- **Smooth vehicle movement** — markers extrapolate forward along the route
  between fixes (no 30-second freezes), stay anchored to the real GPS fix (no
  drift), and follow a backend-provided timed trajectory.
- **Schedule fallback** — the arrivals list backfills GTFS scheduled departures
  when live data is thin, so a stop is never blank; scheduled vehicles also
  appear on the map where a line has no live one.
- **Nearby** — a location-first list of catchable lines around you, ordered by
  time-to-board (walk + wait) rather than bare ETA.
- **Suburban lines** merged into the feed alongside city lines.
- **Vehicle type classification** (bus / trolleybus / tram) unified across
  stops, lines, and markers.
- **Coverage heatmap** on the main map when zoomed out.

### Fixed
- **Vehicle direction** — vehicles are stitched to the shape of the direction
  they're actually travelling, so they no longer appear to drive "through
  houses."
- **Stop rendering** — bus stops with quotes in their names no longer break the
  map source (GeoJSON is now escaped correctly); tram stops always show the tram
  icon.
- **Placeholder vehicles** — schedule-derived placeholder rows (no real GPS)
  stay in the arrivals list but no longer clutter the map.

### Changed
- Six stabilized rendering/data behaviors (GPU layer, timed movement, direction
  stitching, live-only map, schedule list + map) became the default and are no
  longer behind feature flags.

## 2026-07-12

### Added
- **Fleet identification** — from a vehicle's garage number, show its model,
  age, and comfort attributes (A/C, low-floor), so riders know what they're
  about to board.
- Coverage-map view (route-density heatmap).

### Fixed
- **Live geolocation** — the "my location" marker follows a continuous position
  stream and eases to each fix.
- **iOS web thermals** — the web app renders zero frames when nothing is moving
  (no more constant repaint).

## 2026-07-11

### Fixed
- Map/UX batch: correct route-leg projection for vehicles, honest geolocation
  errors, both directions of a line surfaced in search, empty-line filtering,
  and a fixed 30s refresh cadence.

## 2026-07-10

### Added
- Initial public transit app: live arrivals, stop/line search, map with stop
  markers, vehicle tracking, in-app feedback board, EN/RU/SR localization.
- Background arrival-history collection (for future analytics).
