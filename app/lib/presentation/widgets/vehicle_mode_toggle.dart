import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

import '../../core/vehicle_map_mode.dart';
import '../../data/analytics/event_logger.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';

/// The map's quick toggle between on-demand vehicles and the background
/// "aquarium" — the single control for the mode (there is deliberately no
/// Settings item). Renders nothing while the `vehicles_on_demand` flag is off:
/// that's the killswitch, and the map is then the aquarium regardless.
///
/// The choice is persisted, so it survives a restart, and the map switches on
/// the fly — no restart, no reload.
class VehicleModeToggle extends ConsumerStatefulWidget {
  const VehicleModeToggle({super.key});

  /// SharedPreferences key: the one-time label has been shown on this device.
  static const hintSeenKey = 'vehicle_mode_hint_seen';

  @override
  ConsumerState<VehicleModeToggle> createState() => _VehicleModeToggleState();
}

class _VehicleModeToggleState extends ConsumerState<VehicleModeToggle> {
  // One-time label next to the button (owner, 2026-11-23): a blind panel read
  // the corner button as "map layers", so the first time it appears it says
  // what it is. Shown once per device, hides after a few seconds or on tap.
  bool _hint = false;
  bool _hintChecked = false;
  Timer? _hintTimer;

  Future<void> _maybeShowHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(VehicleModeToggle.hintSeenKey) ?? false) return;
    await prefs.setBool(VehicleModeToggle.hintSeenKey, true);
    if (!mounted) return;
    setState(() => _hint = true);
    _hintTimer = Timer(const Duration(seconds: 6), _hideHint);
  }

  void _hideHint() {
    _hintTimer?.cancel();
    if (mounted && _hint) setState(() => _hint = false);
  }

  @override
  void dispose() {
    _hintTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(vehiclesOnDemandEnabledProvider)) {
      return const SizedBox.shrink();
    }
    // The flag arrives with the async config, so the first-show check runs on
    // the first build where the button is actually visible.
    if (!_hintChecked) {
      _hintChecked = true;
      _maybeShowHint();
    }
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mode = ref.watch(vehicleMapModeProvider);
    // Inverted (light button, dark glyph) = all transport is on. The default
    // (on-demand) leaves the button plain, so a highlighted button always means
    // "you asked for more than the default". Same inversion as the menu's close
    // button.
    final aquarium = mode == VehicleMapMode.aquarium;
    final fg = aquarium
        ? theme.colorScheme.surface
        : theme.colorScheme.onSurface;

    // The gap to the button below is ours, so that hiding this widget hides the
    // spacing with it and the control stack reads exactly as it does today.
    final button = PointerInterceptor(
      child: Material(
        color: aquarium
            ? theme.colorScheme.onSurface
            : theme.colorScheme.surface,
        elevation: 3,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          // Bus with signal arcs = live vehicles (owner pick 2026-11-23 after a
          // blind comprehension panel; replaces the misleading layers glyph).
          icon: SvgPicture.asset(
            'assets/icons/live_transport.svg',
            width: 24,
            height: 24,
            colorFilter: ColorFilter.mode(fg, BlendMode.srcIn),
          ),
          tooltip: l10n.vehicleModeTooltip,
          onPressed: () {
            _hideHint();
            _flip(context, ref, mode, l10n);
          },
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _hint
                ? Padding(
                    key: const ValueKey('hint'),
                    padding: const EdgeInsets.only(right: 8),
                    // A speech-bubble tail pointing at the button, so the
                    // label reads as "this button is Live transport".
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: theme.colorScheme.inverseSurface,
                          borderRadius: BorderRadius.circular(16),
                          elevation: 3,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            child: Text(
                              l10n.vehicleModeHint,
                              style: theme.textTheme.labelLarge?.copyWith(
                                color: theme.colorScheme.onInverseSurface,
                              ),
                            ),
                          ),
                        ),
                        CustomPaint(
                          size: const Size(7, 14),
                          painter: _TailPainter(
                            theme.colorScheme.inverseSurface,
                          ),
                        ),
                      ],
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('none')),
          ),
          button,
        ],
      ),
    );
  }

  void _flip(
    BuildContext context,
    WidgetRef ref,
    VehicleMapMode mode,
    AppLocalizations l10n,
  ) {
    final next = mode == VehicleMapMode.onDemand
        ? VehicleMapMode.aquarium
        : VehicleMapMode.onDemand;
    ref.read(settingsControllerProvider.notifier).setVehicleMapMode(next);
    // User's explicit map-mode switch — logged here (not in the controller,
    // which also fires on programmatic changes) so it reflects a real choice.
    ref
        .read(eventLoggerProvider)
        .log(
          Ev.modeToggle,
          props: {
            'to': next == VehicleMapMode.aquarium
                ? Ev.modeAquarium
                : Ev.modeOnDemand,
          },
        );
    // Name the mode we just switched to — the button state alone is easy to
    // misread, and the map's own change (vehicles appearing/vanishing) can be
    // off-screen behind a sheet.
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(l10n.vehicleModeSwitched(vehicleModeLabel(next, l10n))),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
  }
}

String vehicleModeLabel(VehicleMapMode mode, AppLocalizations l10n) =>
    switch (mode) {
      VehicleMapMode.onDemand => l10n.vehicleModeOnDemand,
      VehicleMapMode.aquarium => l10n.vehicleModeAll,
    };

/// Right-pointing triangle: the label's tail towards the button.
class _TailPainter extends CustomPainter {
  const _TailPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, size.height / 2)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_TailPainter old) => old.color != color;
}
