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
