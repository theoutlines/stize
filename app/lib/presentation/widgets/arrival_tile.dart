import 'package:flutter/material.dart';

import '../../domain/models/arrival.dart';
import '../../l10n/app_localizations.dart';
import 'vehicle_icon.dart';

class ArrivalTile extends StatelessWidget {
  const ArrivalTile({super.key, required this.arrival});

  final Arrival arrival;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        child: Icon(vehicleIconFor(arrival.vehicleType), color: theme.colorScheme.onSecondaryContainer),
      ),
      title: Text(arrival.line, style: theme.textTheme.titleMedium),
      subtitle: arrival.stopsRemaining != null
          ? Text(l10n.arrivalStopsAway(arrival.stopsRemaining!))
          : null,
      trailing: Text(
        arrival.etaMinutes <= 0 ? l10n.arrivalEtaNow : l10n.arrivalEtaMinutes(arrival.etaMinutes),
        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}
