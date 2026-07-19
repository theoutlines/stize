import 'package:flutter/painting.dart' show EdgeInsets;

/// Pure model for the desktop context panel (the `context_panel` feature).
///
/// The panel is a single surface with three views navigated as a chain —
/// **nearby → stop → vehicle** (and back down the same chain), plus a model
/// leaf off the vehicle view. It is a DESKTOP-ONLY surface: below
/// [kContextPanelBreakpoint] the app keeps today's independent bottom sheets
/// untouched, so none of the panel code runs there.
///
/// Everything here is pure so the breakpoint / width maths is unit-testable on
/// its own.
enum ContextView { nearby, stop, vehicle }

// ---- Breakpoint ------------------------------------------------------------

/// Material-3 breakpoint. At or above this the panel shows; below it, the legacy
/// bottom sheets. A portrait tablet (width < 840) is therefore mobile layout —
/// owner decision #1.
const double kContextPanelBreakpoint = 840.0;

/// Whether [width] gets the persistent-panel (desktop) layout.
bool isWideLayout(double width) => width >= kContextPanelBreakpoint;

// ---- Desktop panel width (rubber-band) -------------------------------------

/// Panel width band (owner decision #2, ceiling lowered to 400 on 2026-07-19):
/// min 360 / preferred ~28% of the window / max 400.
const double kPanelMinWidth = 360.0;
const double kPanelMaxWidth = 400.0;
const double kPanelWidthFraction = 0.28;

/// The resolved panel width for a given window [width] — the preferred fraction
/// clamped into the band. At the breakpoint (840) the fraction (235) is below
/// the floor, so the panel is 360 until the window is wide enough for 28% to
/// exceed it (~1286px), and it stops growing at 400 (~1429px+).
double panelWidthFor(double width) =>
    (width * kPanelWidthFraction).clamp(kPanelMinWidth, kPanelMaxWidth);

// ---- Mobile sheet detents (shared, enforced in the common sheet container) --
//
// One vocabulary of heights for EVERY mobile bottom sheet (nearby, stop, model,
// follow), so a sheet never jumps between screens AND never covers the whole
// map: `large` is deliberately NOT fullscreen — a strip of map always stays on
// top (owner R2 #4). Fractions of the available height.
const double kSheetPeek = 0.30;
const double kSheetHalf = 0.55;

/// The tallest a sheet may grow — a clear strip of map stays above it.
const double kSheetLarge = 0.86;

/// The snap detents, smallest first.
const List<double> kSheetDetents = [kSheetPeek, kSheetHalf, kSheetLarge];

// ---- Map geometry (the single source of truth for camera padding) ----------

/// The overlap the UI puts over the map, in logical pixels — the ONE geometry
/// every programmatic camera move reads (see `HomeMapScreen._mapInsets`). The
/// desktop panel covers the left ([panelWidth]); the mobile sheet covers the
/// bottom ([mobileSheetPx]); nothing → zero. Pure so it can be unit-tested for
/// every layout without a live map (owner R3 #1/#2: one owner, all paths).
EdgeInsets mapInsetsFor({
  required bool panelActive,
  required double panelWidth,
  required double mobileSheetPx,
}) {
  if (panelActive) return EdgeInsets.only(left: panelWidth);
  if (mobileSheetPx > 0) return EdgeInsets.only(bottom: mobileSheetPx);
  return EdgeInsets.zero;
}
