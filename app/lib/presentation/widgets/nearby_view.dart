import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/api_config.dart';
import '../../core/nearby_focus.dart';
import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart' show ServiceStatus;
import '../../domain/models/nearby_arrival.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'empty_state.dart';
import 'live_unavailable_banner.dart';
import 'nearby_list.dart';

/// How far the user must move before the Nearby list refetches its set of stops.
/// Big enough to ignore GPS jitter (and any incidental map movement, which never
/// feeds in here anyway), inside the 50–100 m band we want.
const double kNearbyRefetchDistanceMeters = 75.0;

/// Whether the Nearby list should refetch, given the user's position moved from
/// [last] to [current]. Anchored **only** to the user's own location — never the
/// map viewport — so panning/zooming the map can never trigger a request.
bool shouldRefetchNearby({
  required ll.LatLng? last,
  required ll.LatLng current,
  double thresholdMeters = kNearbyRefetchDistanceMeters,
}) {
  if (last == null) return true;
  return const ll.Distance().as(ll.LengthUnit.Meter, last, current) >=
      thresholdMeters;
}

/// The reusable "nearby" view — a live list of the lines catchable around the
/// user, with no assumption about its container. Hosted BY the mobile bottom
/// sheet ([NearbySheet], the legacy shell) and by the context-slot shells
/// (mobile [ContextSheet] / desktop [ContextPanel]), so the nearby fetch/order/
/// empty-state logic lives in ONE place (the "no duplication" contract).
///
/// Owns its own data: fetches from the user's location, auto-refreshes every 30s
/// (matched to the backend cache — never faster), and pull-to-refreshes.
class NearbyView extends ConsumerStatefulWidget {
  const NearbyView({
    super.key,
    required this.userLocation,
    required this.locationDenied,
    required this.active,
    required this.onEnableLocation,
    this.onTapGroup,
    this.scrollController,
    this.showLocalSearch = true,
  });

  final ll.LatLng? userLocation;
  final bool locationDenied;

  /// The surface is visible and the app foregrounded — pause polling when not.
  final bool active;
  final VoidCallback onEnableLocation;
  final void Function(NearbyGroup group)? onTapGroup;

  /// Provided by a scrolling container (the sheet); null lets the view scroll
  /// itself (the fixed-height desktop panel).
  final ScrollController? scrollController;

  /// The local "Filter lines nearby…" field. Mobile keeps it; the desktop panel
  /// hides it (the persistent global search above the panel replaces it —
  /// decision #6).
  final bool showLocalSearch;

  @override
  ConsumerState<NearbyView> createState() => NearbyViewState();
}

class NearbyViewState extends ConsumerState<NearbyView> {
  List<NearbyGroup>? _groups; // null = never loaded
  bool _loading = false;
  bool _offline = false;
  // Live feed down but the timetable answered: show a banner, not an empty list.
  bool _liveUnavailable = false;
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
  void didUpdateWidget(covariant NearbyView oldWidget) {
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
    // bare parent rebuild (e.g. the map camera moved).
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
      final result = await ref
          .read(nearbyArrivalsRepositoryProvider)
          .nearby(lat: loc.latitude, lon: loc.longitude);
      if (!mounted || seq != _seq) return;
      setState(() {
        _groups = result.groups;
        _liveUnavailable = result.serviceStatus == ServiceStatus.unavailable;
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
    // Global two-section order: live cards first, schedule-only after.
    return orderNearbyGroups(matched);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.showLocalSearch) _localSearch(Theme.of(context)),
        Expanded(child: _content(widget.scrollController)),
      ],
    );
  }

  Widget _localSearch(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _query = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          hintText: l10n.nearbySearchHint,
          filled: true,
          fillColor:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide.none,
          ),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
    );
  }

  Widget _content(ScrollController? controller) {
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
      header: _liveUnavailable ? const LiveUnavailableBanner() : null,
    );
  }

  // Wrap a non-list state so a sheet still drags (it needs a scrollable child)
  // and pull-to-refresh still works where relevant.
  Widget _scrollable(ScrollController? controller, Widget child) {
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
