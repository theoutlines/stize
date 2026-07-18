import 'package:flutter/widgets.dart';

/// Pure model for the adaptive "context slot" (the `context_panel` feature).
///
/// The slot is a single surface with three views navigated as a chain —
/// **nearby → stop → vehicle** (and back down the same chain). This formalises
/// the state already implicit in `HomeMapScreen` (a stop-context id, a followed
/// vehicle) into one explicit selector shared by BOTH layouts, so the state
/// machine is provably identical at either breakpoint:
///
///  * desktop (≥ [kContextPanelBreakpoint]) — a persistent left panel;
///  * mobile  (< [kContextPanelBreakpoint]) — bottom sheets.
///
/// Only the *container* changes between layouts; the view content and this
/// machine do not. Everything here is pure (no Flutter widgets beyond
/// [EdgeInsets]) so the camera-geometry maths is unit-testable on its own.
enum ContextView { nearby, stop, vehicle }

/// The parent one step up the chain — where the "back" affordance goes. Nearby
/// is the root (its back = "close the slot", still landing on nearby).
ContextView? parentView(ContextView v) => switch (v) {
  ContextView.nearby => null,
  ContextView.stop => ContextView.nearby,
  ContextView.vehicle => ContextView.stop,
};

// ---- Breakpoint ------------------------------------------------------------

/// Material-3 breakpoint. At or above this the slot is the left panel; below it,
/// bottom sheets. A portrait tablet (width < 840) is therefore mobile layout —
/// exactly the owner's decision #1.
const double kContextPanelBreakpoint = 840.0;

/// Whether [width] gets the persistent-panel (desktop) layout.
bool isWideLayout(double width) => width >= kContextPanelBreakpoint;

// ---- Desktop panel width (rubber-band) -------------------------------------

/// Panel width band (owner decision #2): min 360 / preferred ~28% of the window
/// / max 440.
const double kPanelMinWidth = 360.0;
const double kPanelMaxWidth = 440.0;
const double kPanelWidthFraction = 0.28;

/// The resolved panel width for a given window [width] — the preferred fraction
/// clamped into the band. At the breakpoint (840) the fraction (235) is below
/// the floor, so the panel is 360 until the window is wide enough for 28% to
/// exceed it (~1286px), and it stops growing at 440 (~1572px+).
double panelWidthFor(double width) =>
    (width * kPanelWidthFraction).clamp(kPanelMinWidth, kPanelMaxWidth);

// ---- Mobile sheet detents --------------------------------------------------

/// The unified sheet detents (owner rule): a single vocabulary of heights that
/// does NOT jump between screens. `large` is deliberately not fullscreen — a
/// strip of map always stays on top so the tracked target has somewhere to be.
enum SheetDetent { peek, half, large }

/// peek — handle + title + ~1.5 cards (the nearby / follow default).
const double kDetentPeek = 0.32;

/// half — roughly the middle.
const double kDetentHalf = 0.56;

/// large — the full board, still leaving a map strip on top (not fullscreen).
const double kDetentLarge = 0.86;

/// The fraction of the available height a detent occupies.
double detentFraction(SheetDetent d) => switch (d) {
  SheetDetent.peek => kDetentPeek,
  SheetDetent.half => kDetentHalf,
  SheetDetent.large => kDetentLarge,
};

/// The ordered snap fractions, smallest first — the set a drag snaps to.
const List<double> kDetentStops = [kDetentPeek, kDetentHalf, kDetentLarge];

/// The detent whose fraction is nearest [fraction] — where a drag settles.
SheetDetent nearestDetent(double fraction) {
  var best = SheetDetent.peek;
  var bestDelta = double.infinity;
  for (final d in SheetDetent.values) {
    final delta = (detentFraction(d) - fraction).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = d;
    }
  }
  return best;
}

// ---- Camera view insets (the "visible track" contract) ---------------------

/// The insets of the map area that the panel / sheet does **not** cover — the
/// region a followed vehicle (or focused stop) must be kept inside so tracking
/// is never visually interrupted (owner decision #3). These map directly onto
/// the maplibre camera `padding`, so a centred/followed target is placed in the
/// visible strip:
///
///  * desktop — the panel covers the left [panelWidth];
///  * mobile  — the sheet covers the bottom [sheetHeight] (its height in the
///    CURRENT detent, so the insets follow a drag).
///
/// Pure geometry: no widget or controller access, so it is unit-tested directly
/// (the "visible area calc" the DoD asks for).
EdgeInsets contextViewInsets({
  required bool wide,
  required double panelWidth,
  required double sheetHeight,
}) => wide
    ? EdgeInsets.only(left: panelWidth)
    : EdgeInsets.only(bottom: sheetHeight);

/// The pixel height a sheet occupies at [detent] given the available
/// [availableHeight] (already net of the top safe-area / map strip if the
/// caller wants). Convenience for turning a detent into [contextViewInsets]'s
/// `sheetHeight`.
double sheetHeightFor(SheetDetent detent, double availableHeight) =>
    availableHeight * detentFraction(detent);
