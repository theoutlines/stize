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
  }

  void _stopLocationStream() {
    _positionSub?.cancel();
    _positionSub = null;
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
    // Recentring on the user is an explicit camera intent — it ends any follow
    // (the vehicle marker + route highlight stay put).
    _stopFollow();
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
}
