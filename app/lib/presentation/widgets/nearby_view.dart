import 'dart:async';
import 'package:stize/core/design/stize_text.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../core/api_config.dart';
import '../../core/design/stize_tokens.dart';
import '../../core/foreground.dart';
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
import 'jam_nearby_strip.dart';
import 'live_unavailable_banner.dart';
import 'nearby_list.dart';
import 'vehicle_icon.dart';
import '../../core/design/stize_icons.dart';

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
    this.banner,
    this.externalSearch,
    this.externalSearchActive = false,
    this.onSearchFocus,
    this.onSearchCancel,
    this.hugContent = false,
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

  /// Mobile V3 search: called when the search row gains focus (the sheet
  /// rises to its large detent) and when the user taps Cancel (it returns).
  final VoidCallback? onSearchFocus;
  final VoidCallback? onSearchCancel;

  /// Desktop panel: lay out to the content's height (short states make a short
  /// card); lists still fill the available height and scroll.
  final bool hugContent;

  /// One contextual line under the search (guide strip: night, first launch,
  /// at a hub). Null = none.
  final Widget? banner;

  /// One-scroll home: the search lives in the pill on the map. Its text drives
  /// this list's query, and while it is active the nearby cards step aside.
  final TextEditingController? externalSearch;
  final bool externalSearchActive;

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
  late final ForegroundResumeListener _resume = ForegroundResumeListener(() {
    if (mounted && widget.active) _fetch();
  });
  ll.LatLng? _lastFetchLoc;
  int _seq = 0;

  // Global (stop/line) results for the current query — the unified-search half
  // that complements the local nearby filter. Fetched debounced via the SHARED
  // `globalSearchProvider` (same fan-out as desktop — one fork, C#4).
  GlobalSearchResults _global = const GlobalSearchResults();
  Timer? _searchDebounce;
  int _searchSeq = 0;

  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  bool _searchFocused = false;

  @override
  void initState() {
    super.initState();
    widget.externalSearch?.addListener(_onExternalQuery);
    _searchFocused = widget.externalSearchActive;
    _searchFocus.addListener(() {
      if (_searchFocus.hasFocus == _searchFocused) return;
      setState(() => _searchFocused = _searchFocus.hasFocus);
      if (_searchFocus.hasFocus) widget.onSearchFocus?.call();
    });
    if (widget.userLocation != null) _fetch();
    _startTimer();
    _resume; // start listening for foreground returns
  }

  void _onExternalQuery() {
    final q = widget.externalSearch!.text;
    if (q != _query) _onQueryChanged(q);
  }

  @override
  void didUpdateWidget(covariant NearbyView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalSearch != widget.externalSearch) {
      oldWidget.externalSearch?.removeListener(_onExternalQuery);
      widget.externalSearch?.addListener(_onExternalQuery);
    }
    if (widget.externalSearch != null &&
        widget.externalSearchActive != _searchFocused) {
      _searchFocused = widget.externalSearchActive;
    }
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
    widget.externalSearch?.removeListener(_onExternalQuery);
    _timer?.cancel();
    _resume.dispose();
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
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
    _searchDebounce = Timer(
      const Duration(milliseconds: 300),
      () => _runGlobal(q),
    );
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
      if (widget.active && appInForeground) _fetch();
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
    // Timetable rows that can't physically happen are dropped first.
    return orderNearbyGroups(pruneImpossibleScheduled(matched));
  }

  @override
  Widget build(BuildContext context) {
    final contextLines = {
      for (final g in _groups ?? const <NearbyGroup>[]) g.line,
    };
    return Column(
      mainAxisSize: widget.hugContent ? MainAxisSize.min : MainAxisSize.max,
      children: [
        if (widget.showLocalSearch) _localSearch(Theme.of(context)),
        if (widget.banner != null && _query.isEmpty) widget.banner!,
        if (contextLines.isNotEmpty) JamNearbyStrip(contextLines: contextLines),
        Flexible(
          fit: widget.hugContent ? FlexFit.loose : FlexFit.tight,
          child: _content(widget.scrollController),
        ),
      ],
    );
  }

  void _cancelSearch() {
    _searchController.clear();
    _onQueryChanged('');
    _searchFocus.unfocus();
    widget.onSearchCancel?.call();
  }

  /// V3 search row (owner-approved): a light pill as the first row of the
  /// sheet, under the thumb. Focus raises the sheet to its large detent with
  /// results inside it; Cancel clears, drops the keyboard and lowers it back.
  Widget _localSearch(ThemeData theme) {
    final l10n = AppLocalizations.of(context);
    final stize = StizeColors.of(context);
    final active = _searchFocused || _query.isNotEmpty;
    const noBorder = OutlineInputBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(StizeRadius.radiusControl),
      ),
      borderSide: BorderSide.none,
    );
    // The system's field (44px, radius-control, fill-05 at rest, fill-10
    // while editing, no ring), with a clear-and-close × inside it instead of
    // a separate Cancel button (owner, 2026-11-23).
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        StizeSpace.space4,
        StizeSpace.space1,
        StizeSpace.space4,
        StizeSpace.space2,
      ),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        onChanged: _onQueryChanged,
        textInputAction: TextInputAction.search,
        style: StizeType.body.copyWith(color: stize.ink),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: Icon(StizeIcons.search, size: 20, color: stize.ink50),
          prefixIconConstraints: const BoxConstraints(
            minWidth: StizeSize.controlH,
            minHeight: StizeSize.controlH,
          ),
          suffixIcon: active
              ? IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  style: IconButton.styleFrom(shape: const CircleBorder()),
                  icon: Icon(StizeIcons.close, size: 16, color: stize.ink60),
                  onPressed: _cancelSearch,
                )
              : null,
          hintText: l10n.searchHint,
          hintStyle: StizeType.body.copyWith(color: stize.ink50),
          filled: true,
          fillColor: active ? stize.fill10 : stize.fill05,
          border: noBorder,
          enabledBorder: noBorder,
          focusedBorder: noBorder,
          contentPadding: const EdgeInsets.symmetric(
            vertical: StizeSpace.space3,
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
          EmptyState(icon: StizeIcons.searchOff, title: l10n.searchNoResults),
        );
      }
      return _searchResults(controller, rows, l10n);
    }

    // No location yet: invite the user to enable it (with `location_autoprompt`
    // on, the map screen has already asked once on entry).
    if (widget.userLocation == null) {
      return _scrollable(
        controller,
        EmptyState(
          icon: StizeIcons.locate,
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
        EmptyState(icon: StizeIcons.nearMe, title: l10n.nearbyLoading),
      );
    }

    if (_offline && (_groups == null || _groups!.isEmpty)) {
      return _scrollable(
        controller,
        EmptyState(
          icon: StizeIcons.offline,
          title: l10n.noNetworkTitle,
          subtitle: l10n.noNetworkSubtitle,
          onRetry: _fetch,
          retryLabel: l10n.retry,
        ),
      );
    }

    // Focused search with nothing typed yet: the nearby cards step aside so
    // the sheet is the search (owner, 2026-11-23). The map pill (external
    // search) keeps them until a query is typed: an empty sheet under the
    // keyboard read as broken.
    if (_searchFocused && _query.isEmpty && widget.externalSearch == null) {
      return _scrollable(controller, const SizedBox.shrink());
    }

    final groups = _filtered;
    if (groups.isEmpty) {
      return _scrollable(
        controller,
        EmptyState(
          icon: StizeIcons.nearMeOff,
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
    // Cards run edge to edge like every list; the stop/line rows keep a
    // 16px inset of their own.
    return ListView(
      controller: controller,
      shrinkWrap: widget.hugContent,
      padding: EdgeInsets.only(bottom: widget.hugContent ? 0 : 24),
      physics: const AlwaysScrollableScrollPhysics(),
      children: children,
    );
  }

  Widget _rowWidget(SearchRow row) {
    switch (row) {
      case NearbySearchRow(:final group):
        return NearbyCard(
          group: group,
          onTap: widget.onTapGroup == null
              ? null
              : () => widget.onTapGroup!(group),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        text,
        style: StizeText.of(
          context,
        ).control.copyWith(color: theme.colorScheme.outline),
      ),
    );
  }

  Widget _stopTile(Stop stop) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Icon(StizeIcons.pin, color: theme.colorScheme.onSurfaceVariant),
      title: Text(stop.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: stop.lines.isEmpty
          ? null
          : Text(
              stop.lines.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
      onTap: widget.onSelectStop == null
          ? null
          : () => widget.onSelectStop!(stop),
    );
  }

  Widget _lineTile(LineInfo line) {
    final type = line.vehicleType;
    final color = vehicleColor(type);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(minWidth: 52),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            vehicleGlyph(
              type,
              size: 16,
              color: StizeColors.of(context).onTransit,
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (context) {
                // Stiže: line number = the one semibold, white on every type.
                // OFF keeps the prior bold 15 (killswitch).
                final stize = StizeColors.of(context);
                return Text(
                  line.line,
                  style: StizeType.lineNumber.copyWith(color: stize.onTransit),
                );
              },
            ),
          ],
        ),
      ),
      title: Text(
        '${line.origin} → ${line.destination}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: widget.onSelectLine == null
          ? null
          : () => widget.onSelectLine!(line),
    );
  }

  // Wrap a non-list state so a sheet still drags (it needs a scrollable child)
  // and pull-to-refresh still works where relevant.
  Widget _scrollable(ScrollController? controller, Widget child) {
    return ListView(
      controller: controller,
      shrinkWrap: widget.hugContent,
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.hugContent ? 0 : 220),
          child: child,
        ),
      ],
    );
  }
}
