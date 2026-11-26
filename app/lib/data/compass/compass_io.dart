/// No compass source off the web yet: the dot shows without a cone.
Stream<double> compassHeadings() => const Stream.empty();

/// Nothing to ask for off the web.
Future<bool> requestCompassPermission() async => false;
