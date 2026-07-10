import 'package:flutter/material.dart';

/// A small, unmistakable "STAGING" marker overlaid on every screen of the
/// staging build, so the test environment is never confused with production.
/// Pinned top-centre (clear of the corner map controls) and non-interactive.
class StagingBadge extends StatelessWidget {
  const StagingBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topCenter,
          child: Container(
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE6A817),
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
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
    );
  }
}
