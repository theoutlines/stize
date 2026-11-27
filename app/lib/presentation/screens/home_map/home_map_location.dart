part of '../home_map_screen.dart';

extension _MapLocation on _HomeMapScreenState {
  // ---- Location -------------------------------------------------------------

  /// On entry: when access is already granted, center instantly on the
  /// last-known fix and let the live stream take over. When the user hasn't
  /// decided yet and the `location_autoprompt` flag is on, ask right away (the
  /// geolocation prompt does not need a user gesture in Chrome, Safari or
  /// Firefox; iOS Safari re-asks every session by default, so riders otherwise
  /// had to tap locate on every visit). A refusal is never re-asked, and a
  /// failed auto-ask stays silent: the recenter button ([_recenterOnMe]) still
  /// asks from a real tap.
  Future<void> _initLocation() async {
    final service = ref.read(locationServiceProvider);
    if (!await service.isPermissionGranted()) {
      await _autopromptLocation();
      return;
    }
    // The first fix (cached or streamed) recenters the camera on the user.
    _pendingRecenter = true;
    final cached = await service.lastKnownIfGranted();
    if (cached != null && mounted) {
      _onFix(ll.LatLng(cached.latitude, cached.longitude), ease: false);
    }
    _reconcileLocationStream();
  }

  /// Asks for location once per screen life, on entry, when the remote
  /// `location_autoprompt` flag is on and the user hasn't decided yet. Called
  /// from [_initLocation] and again when the flag resolves after config loads
  /// (see the listener in build), so a late config doesn't skip the ask.
  Future<void> _autopromptLocation() async {
    if (_autoprompted || !ref.read(locationAutopromptEnabledProvider)) return;
    // Claimed before the first await, so initState and the flag listener can't
    // both ask.
    _autoprompted = true;
    final service = ref.read(locationServiceProvider);
    // On the web the browser owns the decision: asking when it's already
    // granted just returns a fix, asking when it's denied fails quietly (no
    // prompt). Safari's permission query can't be trusted to say "undecided"
    // (owner, iOS 2026-11-22: Chrome asked on entry, Safari didn't), so the web
    // always asks once and lets the browser decide.
    if (!kIsWeb && !await service.isPermissionUndecided()) return;
    try {
      final fresh = await service.getCurrentPosition(); // shows the prompt
      if (!mounted) return;
      _pendingRecenter = true;
      _onFix(ll.LatLng(fresh.latitude, fresh.longitude), ease: false);
      _reconcileLocationStream();
    } catch (_) {
      // Declined, no fix or a platform error: stay quiet on entry, no snackbar.
    }
  }

  /// Applies a fresh position fix: eases the marker toward it (or snaps on the
  /// first one), records the time (feeds the staleness watchdog), and — only
  /// when a recenter was requested — moves the camera onto it.
  void _onFix(ll.LatLng point, {bool ease = true}) {
    if (!mounted) return;
    _lastFixAt = DateTime.now();
    _locationDenied = false;
    _setState(() {
      if (ease && _meTo != null) {
        _meFrom = _displayedMe ?? _meTo;
        _meTo = point;
        _meAnim.forward(from: 0);
      } else {
        // First fix (or an explicit snap): no ease, jump straight there.
        _meFrom = point;
        _meTo = point;
        _meAnim.value = 1;
      }
    });
    if (_pendingRecenter) {
      _pendingRecenter = false;
      final geo = Geographic(lon: point.longitude, lat: point.latitude);
      final controller = _controller;
      if (controller == null) {
        _pendingCenter = geo;
        _pendingZoom = 16;
      } else {
        // Centre the user in the VISIBLE area (right of the panel / above the
        // sheet), not the whole window — the same geometry every camera path
        // reads (owner R3 #1: locate was centring on the full viewport).
        _camMove(center: geo, zoom: 16);
      }
    }
  }

  /// The marker's currently-drawn position (eased between [_meFrom] and
  /// [_meTo]); null when there's no fix to show.
  ll.LatLng? get _displayedMe {
    final to = _meTo;
    if (to == null) return null;
    return lerpLatLng(_meFrom ?? to, to, _meAnim.value);
  }

  /// Brings the position stream into line with the current lifecycle: run it
  /// only while the map is the visible tab *and* the app is foregrounded and
  /// access isn't denied; otherwise pause it. On becoming active again a stream
  /// that has silently stalled (web / iOS Safari) is recreated.
  void _reconcileLocationStream() {
    final shouldStream = _tabActive && _appResumed && !_locationDenied;
    if (!shouldStream) {
      _stopLocationStream();
      return;
    }
    if (_positionSub == null) {
      _startLocationStream();
    } else if (shouldResubscribe(
      active: true,
      lastFixAt: _lastFixAt,
      subscribedAt: _subscribedAt!,
      now: DateTime.now(),
      staleThreshold: _meStaleThreshold,
    )) {
      _startLocationStream();
    }
  }

  void _startLocationStream() {
    final service = ref.read(locationServiceProvider);
    _positionSub?.cancel();
    _subscribedAt = DateTime.now();
    _positionSub = service.positionStream().listen(
      (p) => _onFix(ll.LatLng(p.latitude, p.longitude)),
      onError: _onLocationStreamError,
      cancelOnError: false,
    );
    _startCompass();
  }

  void _stopLocationStream() {
    _positionSub?.cancel();
    _positionSub = null;
    _compassSub?.cancel();
    _compassSub = null;
  }

  /// Heading cone (DS LocationDot): listen to the compass while the location
  /// streams. Only a turn over 2° repaints, so the dot is still at rest.
  void _startCompass() {
    _compassSub?.cancel();
    _compassSub = compassHeadings().listen((h) {
      final last = _heading.value;
      if (last == null || headingDelta(last, h).abs() >= 2) {
        _heading.value = h;
      }
    });
  }

  void _onLocationStreamError(Object error) {
    // Permission revoked (or services switched off) mid-stream: hide the marker
    // quietly and stop. Never re-prompt on our own — the recenter button is the
    // only place we ask again. Other errors are transient; keep listening.
    final revoked =
        error is LocationUnavailable &&
        (error.reason == LocationUnavailableReason.permissionDenied ||
            error.reason == LocationUnavailableReason.permissionDeniedForever ||
            error.reason == LocationUnavailableReason.serviceDisabled);
    if (!revoked) return;
    _stopLocationStream();
    if (!mounted) return;
    _setState(() {
      _locationDenied = true;
      _meFrom = null;
      _meTo = null;
    });
  }

  /// Surface the *real* reason a fix failed, so a timeout or a momentary
  /// unavailability isn't mislabelled as "location is off / access denied" (F3a).
  void _showLocationMessage(LocationUnavailableReason reason) {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final message = switch (reason) {
      LocationUnavailableReason.serviceDisabled => l10n.locationServicesOff,
      LocationUnavailableReason.permissionDenied ||
      LocationUnavailableReason.permissionDeniedForever => l10n.locationDenied,
      LocationUnavailableReason.timeout => l10n.locationTimeout,
      LocationUnavailableReason.positionUnavailable => l10n.locationUnavailable,
    };
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _recenterOnMe() async {
    // iPhone hands out the compass only from inside a tap, before any await:
    // ask on the same Locate tap that asks for location (DS LocationDot).
    unawaited(requestCompassPermission());
    // Recentring on the user is an explicit camera intent — it ends any follow
    // (the vehicle marker + route highlight stay put).
    _stopFollow();
    // Back to you: Nearby is around your fix again.
    if (_browse.point != null || _browse.lifted) {
      _setState(() {
        _browse.point = null;
        _browse.lifted = false;
      });
    }
    // Recenter immediately on the best position we already have (instant
    // feedback), then always kick off a fresh fix that recenters again — so the
    // button reliably moves the camera to the user on every tap, and a stale
    // cached position gets corrected rather than leaving the button feeling
    // dead (X3).
    final me = _meTo;
    if (me != null) {
      _camEase(Geographic(lon: me.longitude, lat: me.latitude), zoom: 16);
    }
    // A real user gesture — allowed to prompt. One fresh fix (also fires the OS
    // prompt on first use) gives an instant recenter; the live stream then keeps
    // the marker tracking.
    final service = ref.read(locationServiceProvider);
    try {
      final fresh = await service.getCurrentPosition();
      _locationDenied = false;
      _pendingRecenter = true;
      _onFix(ll.LatLng(fresh.latitude, fresh.longitude), ease: me != null);
      _reconcileLocationStream();
    } on LocationUnavailable catch (e) {
      _showLocationMessage(e.reason);
    } catch (_) {
      // An unclassified failure: report it as "unavailable", never as "off".
      _showLocationMessage(LocationUnavailableReason.positionUnavailable);
    }
  }

  // ---- Nearby around a map point -------------------------------------------

  /// Nearby is on screen with nothing else open: the map can choose its point.
  bool get _browseEligible =>
      !_follow.active &&
      _selectedVehicleKey == null &&
      _focus == null &&
      _levels.isEmpty &&
      !_pillActive;

  /// The centre point is drawn (dragging now, or a point chosen).
  bool get _browseShowing =>
      _browseEligible && (_browse.lifted || _browse.point != null);

  /// The visible map's centre in screen pixels (left of the panel / above the
  /// sheet excluded).
  Offset _visibleCentre(Size size) {
    final insets = _mapInsets;
    return Offset(
      insets.left + (size.width - insets.left - insets.right) / 2,
      insets.top + (size.height - insets.top - insets.bottom) / 2,
    );
  }

  /// A user drag started on the Nearby map: lift the dot.
  void _onBrowseDragStart() {
    if (!_browseEligible) return;
    // A new drag inside the settle window: the last idle was a pause, not the
    // end of the gesture, so the dot stays up.
    _browse.idleTimer?.cancel();
    if (_browse.lifted) return;
    _browse.dropTimer?.cancel();
    _browse.dropAt = null;
    _setState(() => _browse.lifted = true);
    _pushBrowseDot();
  }

  /// The camera stopped. Wait a beat before dropping: on touch a gesture can
  /// report an idle mid-way (a pause, the end of a flick before the next one).
  void _onBrowseIdle() {
    if (!_browse.lifted) return;
    _browse.idleTimer?.cancel();
    _browse.idleTimer = Timer(
      const Duration(milliseconds: 280),
      _dropBrowseDot,
    );
  }

  /// Drop the dot on the visible centre and make that Nearby's point. A point
  /// within 40 m of your fix is just "around you".
  void _dropBrowseDot() {
    if (!_browse.lifted || !mounted) return;
    final c = _controller;
    if (c == null) return;
    final size = MediaQuery.sizeOf(context);
    final geo = c.toLngLat(_visibleCentre(size));
    final point = ll.LatLng(geo.lat, geo.lon);
    final me = _meTo;
    final home =
        me != null && _distance.as(ll.LengthUnit.Meter, me, point) < 40;
    _setState(() {
      _browse.lifted = false;
      _browse.point = home ? null : point;
    });
    // The bounce: a few tiny source updates over the drop, then still.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _browse.dropTimer?.cancel();
    if (home || still) {
      _browse.dropAt = null;
      _pushBrowseDot();
      return;
    }
    _browse.dropAt = DateTime.now();
    _pushBrowseDot();
    _browse.dropTimer = Timer.periodic(const Duration(milliseconds: 16), (t) {
      final at = _browse.dropAt;
      if (!mounted ||
          at == null ||
          DateTime.now().difference(at) >= StizeMotion.medium) {
        t.cancel();
        _browse.dropAt = null;
      }
      _pushBrowseDot();
    });
  }

  /// How far up the dot rides right now, in px (lifted, or mid-bounce), and
  /// its opacity.
  (double, double) _browseDotLift() {
    const lift = 14.0;
    if (_browse.lifted) return (lift, 0.6);
    final at = _browse.dropAt;
    if (at == null) return (0, 1);
    final t =
        (DateTime.now().difference(at).inMicroseconds /
                StizeMotion.medium.inMicroseconds)
            .clamp(0.0, 1.0);
    final up = 1 - Curves.bounceOut.transform(t);
    return (lift * up, 1 - 0.4 * up);
  }

  /// The dot as map features: your dot (primary with a white ring) and, while
  /// lifted, its shadow on the spot it will land on. Empty when not browsing.
  String _browseDotGeoJson() {
    final c = _controller;
    final features = <Map<String, Object?>>[];
    if (c != null && mounted && _browseShowing) {
      final Offset base;
      if (_browse.lifted) {
        base = _visibleCentre(MediaQuery.sizeOf(context));
      } else {
        final p = _browse.point;
        base = p == null
            ? _visibleCentre(MediaQuery.sizeOf(context))
            : c.toScreenLocation(Geographic(lon: p.longitude, lat: p.latitude));
      }
      final (lift, opacity) = _browseDotLift();
      Map<String, Object?> f(Offset px, Map<String, Object?> props) {
        final g = c.toLngLat(px);
        return {
          'type': 'Feature',
          'geometry': {
            'type': 'Point',
            'coordinates': [g.lon, g.lat],
          },
          'properties': props,
        };
      }

      final primary = Theme.of(context).colorScheme.primary.toHexString();
      if (_browse.lifted) {
        features.add(
          f(base + const Offset(0, 2), {
            'r': 5.0,
            'color': '#000000',
            'opacity': 0.35,
            'blur': 0.8,
            'stroke': 0.0,
          }),
        );
      }
      features.add(
        f(base - Offset(0, lift), {
          'r': 6.0,
          'color': primary,
          'opacity': opacity,
          'blur': 0.0,
          'stroke': 3.0,
        }),
      );
    }
    return jsonEncode({'type': 'FeatureCollection', 'features': features});
  }

  /// Puts the dot's current state on the map (adds the layer on first use).
  Future<void> _pushBrowseDot() async {
    final style = _style;
    if (style == null) return;
    final srcId = _stopSourceId(_LayerIds.browseDot);
    try {
      if (!_browse.dotAdded) {
        _browse.dotAdded = true;
        await style.addSource(
          GeoJsonSource(id: srcId, data: _browseDotGeoJson()),
        );
        await style.addLayer(
          CircleStyleLayer(
            id: _LayerIds.browseDot,
            sourceId: srcId,
            paint: {
              'circle-radius': ['get', 'r'],
              'circle-color': ['get', 'color'],
              'circle-opacity': ['get', 'opacity'],
              'circle-blur': ['get', 'blur'],
              'circle-stroke-width': ['get', 'stroke'],
              'circle-stroke-color': '#ffffff',
              'circle-stroke-opacity': ['get', 'opacity'],
              'circle-pitch-alignment': 'map',
            },
          ),
        );
      } else {
        await style.updateGeoJsonSource(id: srcId, data: _browseDotGeoJson());
      }
    } catch (_) {
      _browse.dotAdded = false;
    }
  }

  /// The pill's place line: around you, or the stop nearest the map point.
  String? _browsePlaceLabel(AppLocalizations l10n) {
    final p = _browse.point;
    if (p == null) return _meTo == null ? null : l10n.nearbyAroundYou;
    Stop? best;
    var bestD = double.infinity;
    for (final s in _stops.area) {
      final d = _distance.as(ll.LengthUnit.Meter, p, ll.LatLng(s.lat, s.lon));
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best != null && bestD < 600 ? best.name : l10n.nearbyThisPoint;
  }
}
