import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/line_info.dart';
import '../../domain/models/stop.dart';
import '../../l10n/app_localizations.dart';
import '../providers/providers.dart';
import '../widgets/vehicle_icon.dart';

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
  bool _loading = false;

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
      if (!mounted) return;
      setState(() {
        _stops = stops;
        _lines = lines;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final hasQuery = _controller.text.trim().isNotEmpty;
    final hasResults = _stops.isNotEmpty || _lines.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: false,
          onChanged: _onChanged,
          decoration: InputDecoration(hintText: l10n.searchHint, border: InputBorder.none),
        ),
      ),
      body: _loading
          ? const LinearProgressIndicator()
          : (!hasQuery
              ? const SizedBox.shrink()
              : (!hasResults
                  ? Center(child: Text(l10n.searchNoResults))
                  : ListView(
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
                          ),
                      ],
                    ))),
    );
  }
}
