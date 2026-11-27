part of 'nearby_view.dart';

// What the Nearby list draws: the local search field, the content for each
// state (no location, search results, the stop groups) and its rows.
extension _NearbyRows on NearbyViewState {
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
        places: _global.places,
        query: _query,
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
      // The jam notice and the guide strip open the list itself, mobile and
      // desktop alike, and scroll with it (DS Banner, owner 2026-11-26).
      lead: _query.isEmpty ? _lead() : null,
      leadColor: _hasJams
          ? jamSurface(StizeColors.of(context))
          : GuideStrip.surface(StizeColors.of(context)),
    );
  }

  Set<String> get _contextLines => {
    for (final g in _groups ?? const <NearbyGroup>[]) g.line,
  };

  bool get _hasJams => nearbyJams(ref, _contextLines).isNotEmpty;

  /// What opens the Nearby list: the jam notice, then the guide strip.
  Widget? _lead() {
    final parts = [
      if (_hasJams) JamNearbyStrip(contextLines: _contextLines),
      ?widget.banner,
    ];
    if (parts.isEmpty) return null;
    if (parts.length == 1) return parts.single;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: FlatCards.of(context) ? 0 : StizeSpace.space1,
      children: parts,
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
    return StretchCardList(
      controller: controller,
      shrinkWrap: widget.hugContent,
      bottomPadding: MediaQuery.paddingOf(context).bottom,
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
      case PlaceSearchRow(:final place):
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          leading: PlaceBadge(kind: place.kind),
          title: Text(place.displayName),
          onTap: widget.onSelectPlace == null
              ? null
              : () => widget.onSelectPlace!(place),
        );
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

  Widget _stopTile(Stop stop) => StopResultTile(
    stop: stop,
    onTap: widget.onSelectStop == null
        ? null
        : () => widget.onSelectStop!(stop),
  );

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
    return StretchCardList(
      controller: controller,
      shrinkWrap: widget.hugContent,
      children: [
        // The guide strip leads empty and loading states too.
        if (widget.banner != null && _query.isEmpty)
          FlatCards.of(context)
              ? widget.banner!
              : Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: widget.banner,
                ),
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: widget.hugContent ? 0 : 220),
          child: child,
        ),
      ],
    );
  }
}
