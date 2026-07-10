import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Draft entry to the transport-analytics feature: pick a line number, then see
/// its charts. Kept minimal — the picker will grow (favourites, recents) later.
class AnalyticsHomeScreen extends StatefulWidget {
  const AnalyticsHomeScreen({super.key});

  @override
  State<AnalyticsHomeScreen> createState() => _AnalyticsHomeScreenState();
}

class _AnalyticsHomeScreenState extends State<AnalyticsHomeScreen> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _open() {
    final line = _controller.text.trim();
    if (line.isEmpty) return;
    context.push('/analytics/$line');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Аналитика транспорта')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Выбери линию, чтобы посмотреть её статистику: активность, '
              'реальные интервалы и скорость по времени.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.go,
              onSubmitted: (_) => _open(),
              decoration: const InputDecoration(
                labelText: 'Номер линии',
                hintText: 'напр. 79',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _open,
              icon: const Icon(Icons.query_stats),
              label: const Text('Показать графики'),
            ),
            const SizedBox(height: 24),
            Text(
              'Экспериментально. Данные копятся со временем — у новых линий '
              'графики поначалу будут пустыми.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
