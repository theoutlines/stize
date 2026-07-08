import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart' as ll;

import '../../data/location/location_service.dart';
import '../../domain/models/geocode_result.dart';
import '../../domain/models/line_info.dart';
import '../../domain/models/stop.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/vehicle_icon.dart';
import 'map_screen_args.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<Stop> _stops = [];
  List<LineInfo> _lines = [];
  List<GeocodeResult> _places = [];
  bool _loading = false;

  List<Stop> _nearbyStops = [];
  ll.LatLng? _myPosition;
  bool _nearbyLoading = false;

  @override
  void initState() {
    super.initState();
    _loadNearby();
  }

  Future<void> _loadNearby() async {
    setState(() => _nearbyLoading = true);
    try {
      final position = await ref.read(locationServiceProvider).getCurrentPosition();
      final point = ll.LatLng(position.latitude, position.longitude);
      final stops = await ref.read(stopsRepositoryProvider).nearby(lat: point.latitude, lon: point.longitude);
      if (!mounted) return;
      setState(() {
        _myPosition = point;
        _nearbyStops = stops;
        _nearbyLoading = false;
      });
    } on LocationUnavailable {
      // Soft fallback: no location, just leave the manual search available.
      if (!mounted) return;
      setState(() => _nearbyLoading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => _nearbyLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _stops = [];
        _lines = [];
        _places = [];
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _runSearch(query));
  }

  Future<void> _runSearch(String query) async {
    setState(() => _loading = true);
    try {
      final stops = await ref.read(stopsRepositoryProvider).search(query);
      final lines = await ref.read(linesRepositoryProvider).search(query);
      List<GeocodeResult> places = [];
      try {
        places = await ref.read(geocodeRepositoryProvider).search(query);
      } catch (_) {
        // Geocoding is a best-effort second layer; ignore failures here.
      }
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _lines = lines;
        _places = places;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _openPlaceOnMap(GeocodeResult place) async {
    final center = ll.LatLng(place.lat, place.lon);
    final stops = await ref.read(stopsRepositoryProvider).nearby(lat: place.lat, lon: place.lon);
    if (!mounted) return;
    context.push(
      '/map',
      extra: MapScreenArgs(stops: stops, center: center, centerLabel: place.displayName),
    );
  }

  Future<void> _openLineOnMap(LineInfo line) async {
    final shape = await ref.read(linesRepositoryProvider).getShapeByLineNumber(line.line);
    if (!mounted) return;
    final routeStops = shape.stops
        .map((s) => Stop(stopId: s.stopId, name: s.name, lat: s.lat, lon: s.lon, lines: [line.line]))
        .toList();
    context.push(
      '/map',
      extra: MapScreenArgs(
        stops: routeStops,
        polyline: shape.polyline,
        title: '${line.line}: ${shape.origin} → ${shape.destination}',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasQuery = _controller.text.trim().isNotEmpty;
    final hasResults = _stops.isNotEmpty || _lines.isNotEmpty || _places.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          onChanged: _onChanged,
          decoration: InputDecoration(hintText: l10n.searchHint, border: InputBorder.none),
        ),
        actions: [
          if (hasQuery && _stops.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.map_outlined),
              onPressed: () => context.push('/map', extra: MapScreenArgs(stops: _stops)),
            ),
        ],
      ),
      body: _loading
          ? const LinearProgressIndicator()
          : (!hasQuery ? _nearbyBody(l10n) : (!hasResults ? Center(child: Text(l10n.searchNoResults)) : _resultsBody())),
    );
  }

  Widget _nearbyBody(AppLocalizations l10n) {
    if (_nearbyLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_nearbyStops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l10n.nearbyStopsEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.my_location),
          title: Text(l10n.nearbyStopsTitle),
          trailing: IconButton(
            icon: const Icon(Icons.map_outlined),
            onPressed: () => context.push(
              '/map',
              extra: MapScreenArgs(stops: _nearbyStops, center: _myPosition),
            ),
          ),
        ),
        for (final stop in _nearbyStops)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(stop.name),
            subtitle: Text(stop.lines.join(', ')),
            onTap: () => context.push('/stop/${stop.stopId}?name=${Uri.encodeComponent(stop.name)}'),
          ),
      ],
    );
  }

  Widget _resultsBody() {
    return ListView(
      children: [
        for (final stop in _stops)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: Text(stop.name),
            subtitle: Text(stop.lines.join(', ')),
            onTap: () => context.push('/stop/${stop.stopId}?name=${Uri.encodeComponent(stop.name)}'),
          ),
        for (final line in _lines)
          ListTile(
            leading: Icon(vehicleIconFor(line.vehicleType)),
            title: Text(line.line),
            subtitle: Text('${line.origin} → ${line.destination}'),
            trailing: const Icon(Icons.map_outlined),
            onTap: () => _openLineOnMap(line),
          ),
        for (final place in _places)
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: Text(place.displayName),
            onTap: () => _openPlaceOnMap(place),
          ),
      ],
    );
  }
}
