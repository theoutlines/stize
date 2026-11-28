import 'package:flutter/material.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';

/// Whether the staging diagnostics box shows over the map. Off by default;
/// a tap on the STAGING badge turns it on and off (owner, 2026-11-28: the box
/// covered the map and its per-frame work made panning stutter).
final stagingDiagnosticsOn = ValueNotifier<bool>(false);

/// A small, unmistakable "STAGING" marker overlaid on every screen of the
/// staging build, so the test environment is never confused with production.
/// Pinned top-centre, level with the round map buttons (12 px from the top,
/// 48 px tall), clear of the corner controls. Tapping it shows or hides the
/// diagnostics box; it is outlined while the box is on.
class StagingBadge extends StatelessWidget {
  const StagingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Align(
          alignment: Alignment.topCenter,
          child: PointerInterceptor(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () =>
                  stagingDiagnosticsOn.value = !stagingDiagnosticsOn.value,
              child: SizedBox(
                height: 48,
                // widthFactor 1: as wide as the badge, so the tap area never
                // covers the map buttons beside it.
                child: Center(
                  widthFactor: 1,
                  child: ValueListenableBuilder<bool>(
                    valueListenable: stagingDiagnosticsOn,
                    builder: (context, on, _) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE6A817),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: on ? Colors.black : Colors.transparent,
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 4,
                            offset: Offset(0, 1),
                          ),
                        ],
                      ),
                      // ds-ok: staging-only marker, never in production.
                      child: const Text(
                        'STAGING',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          letterSpacing: 2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
