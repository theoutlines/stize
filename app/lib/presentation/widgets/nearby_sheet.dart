import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:pointer_interceptor/pointer_interceptor.dart';

import '../../core/api_config.dart';
import '../../core/nearby_focus.dart';
import '../../data/api/api_exceptions.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'empty_state.dart';
import 'nearby_list.dart';

/// How far the user must move before the Nearby list refetches its set of stops.
/// Big enough to ignore GPS jitter (and any incidental map movement, which never
/// feeds in here anyway), inside the 50–100 m band we want.
const double kNearbyRefetchDistanceMeters = 75.0;

/// Whether the Nearby list should refetch, given the user's position moved from
/// [last] to [current].
///
/// The list is anchored **only** to the user's own location — never the map
/// viewport/centre — so this is the single gate on issuing a request. The first
/// fix always fetches; after that we refetch only once the user has actually
/// walked at least [thresholdMeters]. Panning/zooming the map does not change
/// [current] (it's the GPS fix, not the camera), so it can never trigger a
/// request through here.
bool shouldRefetchNearby({
  required ll.LatLng? last,
  required ll.LatLng current,
  double thresholdMeters = kNearbyRefetchDistanceMeters,
}) {
  if (last == null) return true;
  return const ll.Distance().as(ll.LengthUnit.Meter, last, current) >= thresholdMeters;
}

/// The experimental "Nearby" surface: a draggable bottom sheet over the map
/// (Google Maps / Transit pattern). Collapsed, it peeks a search field and the
/// top of the list; expanded, it's the full line+direction list. Behind the
/// `nearby_list` flag — the host decides whether to mount it.
///
/// Owns its own data: it fetches from the user's location, auto-refreshes every
/// 30s (matched to the backend cache — never faster), and pull-to-refreshes. The
/// list itself is a separate [NearbyList] widget; this only orchestrates state.
class NearbySheet extends ConsumerStatefulWidget {
  const NearbySheet({
    super.key,
    required this.userLocation,
    required this.locationDenied,
    required this.active,
    required this.onEnableLocation,
    this.onTapGroup,
  });

  /// The user's latest position fix, or null when there's no fix yet.
  final ll.LatLng? userLocation;

  /// Location permission was refused/revoked this session.
  final bool locationDenied;

  /// The map tab is visible and the app is foregrounded — pause polling when not.
  final bool active;

  /// Ask for a location fix (prompts on first use) — wired to the map's
  /// recenter action, the only place we request permission from a gesture.
  final VoidCallback onEnableLocation;

  final void Function(NearbyGroup group)? onTapGroup;

  @override
  ConsumerState<NearbySheet> createState() => _NearbySheetState();
}

class _NearbySheetState extends ConsumerState<NearbySheet> {
  List<NearbyGroup>? _groups; // null = never loaded
  bool _loading = false;
  bool _offline = false;
  String _query = '';
  Timer? _timer;
  ll.LatLng? _lastFetchLoc;
  int _seq = 0;

  final _searchController = TextEditingController();


  @override
  void initState() {
    super.initState();
    if (widget.userLocation != null) _fetch();
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant NearbySheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) {
      if (widget.active) {
        _startTimer();
        _fetch();
      } else {
        _timer?.cancel();
        _timer = null;
      }
    }
    // Refetch only when the user's own position has moved enough — never on a
    // bare parent rebuild (e.g. the map camera moved), which leaves
    // [userLocation] unchanged.
    final loc = widget.userLocation;
    if (loc != null && shouldRefetchNearby(last: _lastFetchLoc, current: loc)) {
      _fetch();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    // Fixed 30s cadence, matched to the backend SWR cache (never poll faster).
    _timer = Timer.periodic(kLiveRefreshInterval, (_) {
      if (widget.active) _fetch();
    });
  }

  Future<void> _fetch() async {
    final loc = widget.userLocation;
    if (loc == null) return;
    final seq = ++_seq;
    _lastFetchLoc = loc;
    if (mounted && _groups == null) setState(() => _loading = true);
    try {
      final groups = await ref
          .read(nearbyArrivalsRepositoryProvider)
          .nearby(lat: loc.latitude, lon: loc.longitude);
      if (!mounted || seq != _seq) return;
      setState(() {
        _groups = groups;
        _loading = false;
        _offline = false;
      });
    } on NetworkException {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _offline = true;
      });
    } catch (_) {
      if (!mounted || seq != _seq) return;
      setState(() => _loading = false);
    }
  }

  List<NearbyGroup> get _filtered {
    final all = _groups ?? const <NearbyGroup>[];
    final q = _query.trim().toLowerCase();
    final matched = q.isEmpty
        ? all
        : [
            for (final g in all)
              if (g.line.toLowerCase().contains(q) ||
                  (g.destination ?? '').toLowerCase().contains(q) ||
                  g.stopName.toLowerCase().contains(q))
                g,
          ];
    // Global two-section order: live cards first, schedule-only cards after
    // (arrivals-dedup) — a schedule-only line never sits above a catchable one.
    return orderNearbyGroups(matched);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.30,
      minChildSize: 0.12,
      maxChildSize: 0.92,
      snap: true,
      snapSizes: const [0.30, 0.92],
      builder: (context, scrollController) {
        // PointerInterceptor stops scroll/drag/taps on the sheet from falling
        // through to the MapLibre platform view underneath (which would pan/zoom
        // the map) on web — the same guard the stop/vehicle sheets use. It wraps
        // only the sheet's own extent, so the map still pans in the area above it.
        // No-op on mobile.
        return PointerInterceptor(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -2)),
              ],
            ),
            child: Column(
              children: [
                _header(theme),
                Expanded(child: _content(scrollController)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _header(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Grab handle.
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.nearbySearchHint,
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(24),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _content(ScrollController controller) {
    final l10n = AppLocalizations.of(context);

    // No location yet: invite the user to enable it (we never prompt on our own).
    if (widget.userLocation == null) {
      return _scrollable(
        controller,
        EmptyState(
          icon: Icons.my_location,
          title: l10n.nearbyNeedsLocationTitle,
          subtitle: widget.locationDenied
              ? l10n.locationDenied
              : l10n.nearbyNeedsLocationSubtitle,
          onRetry: widget.onEnableLocation,
          retryLabel: l10n.nearbyEnableLocation,
        ),
      );
    }

    if (_loading && _groups == null) {
      return _scrollable(
        controller,
        EmptyState(icon: Icons.near_me_outlined, title: l10n.nearbyLoading),
      );
    }

    if (_offline && (_groups == null || _groups!.isEmpty)) {
      return _scrollable(
        controller,
        EmptyState(
          icon: Icons.wifi_off_rounded,
          title: l10n.noNetworkTitle,
          subtitle: l10n.noNetworkSubtitle,
          onRetry: _fetch,
          retryLabel: l10n.retry,
        ),
      );
    }

    final groups = _filtered;
    if (groups.isEmpty) {
      // Distinguish "search matched nothing" from "genuinely nothing nearby".
      final searching = _query.trim().isNotEmpty;
      return _scrollable(
        controller,
        EmptyState(
          icon: searching ? Icons.search_off : Icons.near_me_disabled_outlined,
          title: searching ? l10n.searchNoResults : l10n.nearbyEmptyTitle,
          subtitle: searching ? null : l10n.nearbyEmptySubtitle,
        ),
      );
    }

    return NearbyList(
      groups: groups,
      scrollController: controller,
      onRefresh: _fetch,
      onTapGroup: widget.onTapGroup,
    );
  }

  // Wrap a non-list state so the sheet still drags (it needs a scrollable child
  // attached to [controller]) and pull-to-refresh still works where relevant.
  Widget _scrollable(ScrollController controller, Widget child) {
    return ListView(
      controller: controller,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 220),
          child: child,
        ),
      ],
    );
  }
}
