import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/api_config.dart';
import '../../core/map_support.dart';
import '../../core/nearby_focus.dart';
import '../../core/search.dart';
import '../../data/api/api_exceptions.dart';
import '../../domain/models/arrival.dart' show ServiceStatus;
import '../../domain/models/line_info.dart';
import '../../domain/models/nearby_arrival.dart';
import '../../domain/models/stop.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import 'empty_state.dart';
import 'live_unavailable_banner.dart';
import 'nearby_list.dart';
import 'vehicle_icon.dart';

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
    this.onSelectStop,
    this.onSelectLine,
    this.scrollController,
    this.showLocalSearch = true,
  });

  final ll.LatLng? userLocation;
  final bool locationDenied;

  /// The surface is visible and the app foregrounded — pause polling when not.
  final bool active;
  final VoidCallback onEnableLocation;
  final void Function(NearbyGroup group)? onTapGroup;

  /// Selecting a GLOBAL search result — a stop or a line — opens that context
  /// exactly like the desktop search does (owner C#3). Only wired where the
  /// unified search is shown (the mobile nearby sheet).
  final void Function(Stop stop)? onSelectStop;
  final void Function(LineInfo line)? onSelectLine;

  /// Provided by a scrolling container (the sheet); null lets the view scroll
  /// itself (the fixed-height desktop panel).
  final ScrollController? scrollController;

  /// The search field in the sheet header. Mobile keeps it — now the UNIFIED
  /// global search (owner C): while typing, nearby matches show first, then
  /// global stops/lines. The desktop panel hides it (the persistent global
  /// search above the panel already covers it — decision #6).
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

  // Global (stop/line) results for the current query — the unified-search half
  // that complements the local nearby filter. Fetched debounced via the SHARED
  // `globalSearchProvider` (same fan-out as desktop — one fork, C#4).
  GlobalSearchResults _global = const GlobalSearchResults();
  Timer? _searchDebounce;
  int _searchSeq = 0;

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
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    setState(() => _query = v);
    _searchDebounce?.cancel();
    final q = v.trim();
    if (q.isEmpty) {
      setState(() => _global = const GlobalSearchResults());
      return;
    }
    // Debounce the network half; the local nearby filter narrows synchronously.
    _searchDebounce =
        Timer(const Duration(milliseconds: 300), () => _runGlobal(q));
  }

  Future<void> _runGlobal(String query) async {
    final seq = ++_searchSeq;
    try {
      final results = await ref.read(globalSearchProvider).run(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() => _global = results);
    } catch (_) {
      // Best-effort: a failed global fetch just leaves the nearby matches.
      if (!mounted || seq != _searchSeq) return;
      setState(() => _global = const GlobalSearchResults());
    }
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
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search),
          // Unified global search now, same scope as desktop.
          hintText: l10n.searchHint,
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
                    _onQueryChanged('');
                  },
                ),
        ),
      ),
    );
  }

  Widget _content(ScrollController? controller) {
    final l10n = AppLocalizations.of(context);

    // Unified search takes precedence over the location/loading states: global
    // stop/line results don't need a location fix, so typing works even before
    // the user enables location (owner acceptance / C#3). Nearby matches are
    // simply empty until there's a fix.
    if (_query.trim().isNotEmpty) {
      final rows = mergeNearbyThenGlobal(
        nearby: _filtered, // filtered + live-first ordered nearby groups
        stops: _global.stops,
        lines: _global.lines,
      );
      if (rows.isEmpty) {
        return _scrollable(
          controller,
          EmptyState(icon: Icons.search_off, title: l10n.searchNoResults),
        );
      }
      return _searchResults(controller, rows, l10n);
    }

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
      return _scrollable(
        controller,
        EmptyState(
          icon: Icons.near_me_disabled_outlined,
          title: l10n.nearbyEmptyTitle,
          subtitle: l10n.nearbyEmptySubtitle,
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

  /// The merged results list: nearby cards, then (after a section label) the
  /// global stop/line rows. One flat, draggable scroll view.
  Widget _searchResults(
    ScrollController? controller,
    List<SearchRow> rows,
    AppLocalizations l10n,
  ) {
    final firstGlobal = rows.indexWhere((r) => r is! NearbySearchRow);
    final children = <Widget>[];
    for (var i = 0; i < rows.length; i++) {
      // A "More results" label divides the nearby matches from the global ones,
      // but only when BOTH sections are present.
      if (i == firstGlobal && firstGlobal > 0) {
        children.add(_sectionHeader(l10n.searchMoreResults));
      }
      children.add(_rowWidget(rows[i]));
    }
    return ListView(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _rowWidget(SearchRow row) {
    switch (row) {
      case NearbySearchRow(:final group):
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: NearbyCard(
            group: group,
            onTap: widget.onTapGroup == null
                ? null
                : () => widget.onTapGroup!(group),
          ),
        );
      case StopSearchRow(:final stop):
        return _stopTile(stop);
      case LineSearchRow(:final line):
        return _lineTile(line);
    }
  }

  Widget _sectionHeader(String text) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
      child: Text(
        text,
        style: theme.textTheme.labelMedium
            ?.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }

  Widget _stopTile(Stop stop) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(Icons.location_on_outlined,
          color: theme.colorScheme.onSurfaceVariant),
      title: Text(stop.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: stop.lines.isEmpty
          ? null
          : Text(stop.lines.join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: widget.onSelectStop == null ? null : () => widget.onSelectStop!(stop),
    );
  }

  Widget _lineTile(LineInfo line) {
    final type = classifyLine(line.line);
    final color = vehicleColor(type);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        constraints: const BoxConstraints(minWidth: 52),
        decoration:
            BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            vehicleGlyph(type, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(line.line,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
          ],
        ),
      ),
      title: Text('${line.origin} → ${line.destination}',
          maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: widget.onSelectLine == null ? null : () => widget.onSelectLine!(line),
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
