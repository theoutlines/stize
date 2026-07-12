import 'dart:convert';

/// Fleet identification ("what will I actually ride"): maps a live garage
/// number (`P80209`, `P93052`, …) to a concrete vehicle model or an operator
/// class, so the arrivals UI can show model, age, AC and low-floor.
///
/// Pure Dart, no Flutter dependency (mirrors `core/vehicle_track_animator.dart`)
/// so it unit-tests without any harness. Loading the asset and wiring the
/// feature flag live at the presentation layer; this file only parses the
/// static reference data and resolves numbers against it.
///
/// The reference data is `assets/data/fleet_models.json`. See
/// `docs/FLEET_INTEGRATION.md` §2 for the matching algorithm this implements.

/// The four possible outcomes of a lookup. The matcher is **total**: every
/// input yields exactly one of these — it never throws and never guesses a
/// "closest" model.
enum FleetMatchKind {
  /// Exact per-vehicle map hit — full attributes from `models_catalog`.
  modelHit,

  /// Class-range hit — attributes from the class. For private-operator classes
  /// these are averaged values (`confidence: per-vehicle`), surfaced to the UI
  /// via [FleetVehicle.approximate].
  classHit,

  /// Real vehicle number that matched nothing — show only the API type + number.
  unknown,

  /// Placeholder id from the `P1..P999` junk pool — never show a number for it.
  unknownJunk,
}

/// Drivetrain, used for the eco badge. `unknown` covers values we don't model.
enum Powertrain {
  diesel,
  cng,
  trolleybus,
  tram,
  electricBattery,
  electricUltracap,
  hybrid,
  unknown;

  static Powertrain fromJson(Object? raw) {
    switch (raw) {
      case 'diesel':
        return Powertrain.diesel;
      case 'cng':
        return Powertrain.cng;
      case 'trolleybus':
        return Powertrain.trolleybus;
      case 'tram':
        return Powertrain.tram;
      case 'electric_battery':
        return Powertrain.electricBattery;
      case 'electric_ultracap':
        return Powertrain.electricUltracap;
      case 'hybrid':
        return Powertrain.hybrid;
      default:
        return Powertrain.unknown;
    }
  }

  /// Zero-emission at the point of use (battery/ultracap/trolley/tram) — drives
  /// the green eco badge. Hybrids are cleaner than diesel but still burn fuel,
  /// so they are treated separately by the UI, not as fully "green" here.
  bool get isElectric =>
      this == Powertrain.electricBattery ||
      this == Powertrain.electricUltracap ||
      this == Powertrain.trolleybus ||
      this == Powertrain.tram;
}

/// The resolved identity + comparison attributes for one arriving vehicle.
///
/// Fields are nullable because a model-hit (via `models_catalog`) and a
/// class-hit (via a class range) expose slightly different data: only classes
/// carry `nickname_sr`, `length_m` and `usb`, while the per-vehicle catalog
/// carries none of those. The UI treats every attribute as optional.
class FleetVehicle {
  const FleetVehicle({
    required this.kind,
    this.id,
    this.modelName,
    this.manufacturer,
    this.country,
    this.nicknameSr,
    this.nicknameLatin,
    this.nicknameEn,
    this.noteI18n = const <String, String>{},
    this.vehicleClassType,
    this.operatorName,
    this.ac,
    this.lowFloor,
    this.articulated,
    this.lengthM,
    this.capacity,
    this.yearsBuilt,
    this.comfortScore,
    this.powertrain = Powertrain.unknown,
    this.usb,
    this.assumedFields = const <String>{},
    this.approximate = false,
  });

  /// UNKNOWN — a real number that matched nothing. UI shows only type + number.
  static const FleetVehicle unknown = FleetVehicle(kind: FleetMatchKind.unknown);

  /// UNKNOWN_JUNK — a `P1..P999` placeholder. UI hides the number entirely.
  static const FleetVehicle junk = FleetVehicle(kind: FleetMatchKind.unknownJunk);

  final FleetMatchKind kind;

  /// Stable identity of the resolved thing: the `models_catalog` key on a
  /// model-hit, or the class `id` on a class-hit. Used to tell classes apart
  /// (e.g. for the "≥2 different classes" comfort-sort gate). Null when unknown.
  final String? id;

  /// Human model name, e.g. "Mercedes Conecto III hybrid" / "Tatra KT4YU".
  final String? modelName;

  /// Manufacturer, e.g. "CAF" / "Duewag/FFA". Present on concrete-model classes
  /// only (the per-vehicle catalog and operator classes don't carry it).
  final String? manufacturer;

  /// Country-of-origin code(s), e.g. "ES" / "DE/CH" (slash-separated for more
  /// than one). Historical codes appear too ("CS", "YU"). See `country_names`
  /// in the UI for localized display.
  final String? country;

  /// Local colloquial name in Serbian Cyrillic ("Ката", "Шпанац", "трола") —
  /// classes only. Shown for the `ru` locale and as the ultimate fallback.
  final String? nicknameSr;

  /// Serbian-Latin form of [nicknameSr], with diacritics ("Španac", "Turčin")
  /// — shown for the `sr` locale (Latin-script Serbian UI). Null when there's
  /// no nickname.
  final String? nicknameLatin;

  /// Plain-ASCII form of the nickname, diacritics stripped ("Spanac", "Turcin")
  /// — shown for the `en` locale (as playful local colour). Null when there's
  /// no nickname.
  final String? nicknameEn;

  /// Ready-made card note per locale code (`ru`/`en`/`sr`), from
  /// `human_note_{ru,en,sr}` (classes) or catalog `note_{ru,en,sr}` (models).
  /// Empty when there's no note. Read via [humanNoteFor].
  final Map<String, String> noteI18n;

  /// The card note for the given UI language code, falling back to Russian
  /// (the always-present source), then any available translation.
  String? humanNoteFor(String languageCode) {
    return noteI18n[languageCode] ??
        noteI18n['ru'] ??
        noteI18n['en'] ??
        (noteI18n.isEmpty ? null : noteI18n.values.first);
  }

  /// The nickname for the given UI language code, or null when there's none.
  /// Local colour in the reader's script: `ru` → Cyrillic ("Турчин"), `sr` →
  /// Serbian Latin ("Turčin"), `en` → plain ASCII ("Turcin"). Other locales
  /// fall back to the ASCII form.
  String? nicknameFor(String languageCode) {
    switch (languageCode) {
      case 'ru':
        return nicknameSr ?? nicknameLatin ?? nicknameEn;
      case 'sr':
        return nicknameLatin ?? nicknameEn ?? nicknameSr;
      default:
        return nicknameEn ?? nicknameLatin ?? nicknameSr;
    }
  }

  /// Raw class type string (`tram`/`trolleybus`/`bus`/`ebus`) when known. On a
  /// model-hit this is borrowed from the enclosing operator class.
  final String? vehicleClassType;

  /// Operator name for non-GSP classes ("Ćurdić", "Strela Beograd").
  final String? operatorName;

  final bool? ac;
  final bool? lowFloor;
  final bool? articulated;
  final double? lengthM;
  final int? capacity;

  /// `[from, to]` build years, or null. See [midYear] for the age anchor.
  final List<int>? yearsBuilt;

  /// 1–5 comfort score (see spec §4). Already computed in the JSON.
  final int? comfortScore;

  final Powertrain powertrain;
  final bool? usb;

  /// Field names whose value is `assumed` in the class confidence block. The UI
  /// renders these with a "~"/grey so a guess isn't shown as fact.
  final Set<String> assumedFields;

  /// True for private-operator mixed classes (`confidence: per-vehicle`): the
  /// whole attribute set is a class average, not this exact vehicle. The UI
  /// marks the entire model line approximate ("~").
  final bool approximate;

  /// Whether this carries any model/class info at all (vs. an unknown/junk).
  bool get hasInfo =>
      kind == FleetMatchKind.modelHit || kind == FleetMatchKind.classHit;

  /// Whether a given attribute should be shown as approximate ("~").
  bool isAssumed(String field) => approximate || assumedFields.contains(field);

  /// Age anchor: the midpoint of [yearsBuilt] (spec §3 — "age from the middle
  /// of years_built"). Null when build years are unknown.
  int? get midYear {
    final y = yearsBuilt;
    if (y == null || y.length < 2) return null;
    return ((y[0] + y[1]) / 2).round();
  }
}

/// A class range with the pre-built [FleetVehicle] to return on a hit, plus the
/// range width so nested ranges can be resolved narrowest-first.
class _ClassRange {
  const _ClassRange(this.lo, this.hi, this.vehicle) : width = hi - lo;

  final int lo;
  final int hi;
  final int width;
  final FleetVehicle vehicle;
}

/// Parsed fleet reference data with a pre-computed lookup index. Build once per
/// run via [tryParse]; [resolve] is O(#ranges) worst case and memoised per
/// number (garage numbers are immutable within a session).
class FleetCatalog {
  FleetCatalog._(this._byVehicle, this._ranges);

  final Map<int, FleetVehicle> _byVehicle;
  final List<_ClassRange> _ranges;
  final Map<int, FleetVehicle> _cache = <int, FleetVehicle>{};

  /// Parse the raw JSON string. Returns null on **any** structural problem
  /// (bad JSON, missing/wrong-typed top-level containers) so the caller can
  /// silently disable the feature (spec §5 / task B5). Individual malformed
  /// entries are skipped rather than failing the whole catalog.
  static FleetCatalog? tryParse(String jsonSource) {
    try {
      final decoded = jsonDecode(jsonSource);
      if (decoded is! Map<String, dynamic>) return null;

      final classesRaw = decoded['classes'];
      final catalogRaw = decoded['models_catalog'];
      final vehiclesRaw = decoded['vehicles'];
      if (classesRaw is! List) return null;
      if (catalogRaw is! Map<String, dynamic>) return null;
      if (vehiclesRaw is! Map<String, dynamic>) return null;

      // Pre-build a FleetVehicle for each catalogued model (used by model-hits).
      final models = <String, FleetVehicle>{};
      for (final entry in catalogRaw.entries) {
        final m = entry.value;
        if (m is! Map<String, dynamic>) continue;
        models[entry.key] = _modelFromCatalog(entry.key, m);
      }

      // Build class ranges. Concrete-model classes carry full attributes;
      // mixed operator classes are approximate (per-vehicle confidence).
      final ranges = <_ClassRange>[];
      for (final c in classesRaw) {
        if (c is! Map<String, dynamic>) continue;
        final vehicle = _classToVehicle(c);
        for (final r in (c['ranges'] as List? ?? const [])) {
          if (r is! List || r.length < 2) continue;
          final lo = _asInt(r[0]);
          final hi = _asInt(r[1]);
          if (lo == null || hi == null || hi < lo) continue;
          ranges.add(_ClassRange(lo, hi, vehicle));
        }
      }

      // Map each exact vehicle number to its model, enriched with the operator
      // name and type borrowed from the narrowest enclosing class (the catalog
      // itself has neither). Verified data, not a guess — the range→operator
      // mapping is authoritative.
      final byVehicle = <int, FleetVehicle>{};
      for (final entry in vehiclesRaw.entries) {
        final n = int.tryParse(entry.key);
        final modelKey = entry.value;
        if (n == null || modelKey is! String) continue;
        final base = models[modelKey];
        if (base == null) continue;
        byVehicle[n] = _enrichFromEnclosing(base, n, ranges);
      }

      return FleetCatalog._(byVehicle, ranges);
    } catch (_) {
      // Any unexpected shape disables the feature rather than crashing the app.
      return null;
    }
  }

  /// Resolve a raw garage number (e.g. "P80209") to a [FleetVehicle]. Total and
  /// never throws. See spec §2.
  FleetVehicle resolve(String? garageNo) {
    final n = _parseGarage(garageNo);
    if (n == null) return FleetVehicle.unknown; // empty / malformed
    if (n < 1000) return FleetVehicle.junk; // P1..P999 placeholder pool
    return _cache.putIfAbsent(n, () => _resolve(n));
  }

  FleetVehicle _resolve(int n) {
    // 1) exact per-vehicle map.
    final exact = _byVehicle[n];
    if (exact != null) return exact;

    // 2) class ranges — narrowest containing range wins (nested electric-bus
    //    classes sit inside wider operator blocks).
    _ClassRange? best;
    for (final r in _ranges) {
      if (n < r.lo || n > r.hi) continue;
      if (best == null || r.width < best.width) best = r;
    }
    if (best != null) return best.vehicle;

    // 3) nothing matched.
    return FleetVehicle.unknown;
  }

  /// Strip an optional leading `P`/`p`, parse the remaining digits. Returns null
  /// for empty or non-numeric input (which resolves to UNKNOWN, not junk).
  static int? _parseGarage(String? garageNo) {
    if (garageNo == null) return null;
    var s = garageNo.trim();
    if (s.isEmpty) return null;
    if (s.length > 1 && (s[0] == 'P' || s[0] == 'p')) {
      s = s.substring(1);
    }
    if (s.isEmpty) return null;
    for (var i = 0; i < s.length; i++) {
      final code = s.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) return null; // not a digit
    }
    return int.tryParse(s);
  }

  static FleetVehicle _modelFromCatalog(String key, Map<String, dynamic> m) {
    return FleetVehicle(
      kind: FleetMatchKind.modelHit,
      id: key,
      modelName: m['name'] as String?,
      noteI18n: _noteI18n(m, 'note'),
      ac: m['ac'] as bool?,
      lowFloor: m['low_floor'] as bool?,
      articulated: m['articulated'] as bool?,
      capacity: _asInt(m['capacity']),
      yearsBuilt: _years(m['years']),
      comfortScore: _asInt(m['comfort_score']),
      powertrain: Powertrain.fromJson(m['powertrain']),
    );
  }

  static FleetVehicle _classToVehicle(Map<String, dynamic> c) {
    final confidence = c['confidence'];
    final assumed = <String>{};
    var approximate = false;
    if (confidence is Map<String, dynamic>) {
      for (final e in confidence.entries) {
        if (e.value == 'assumed') assumed.add(e.key);
        // Private-operator mixed classes mark all attributes per-vehicle.
        if (e.key == 'attributes' && e.value == 'per-vehicle') {
          approximate = true;
        }
      }
    }
    return FleetVehicle(
      kind: FleetMatchKind.classHit,
      id: c['id'] as String?,
      modelName: c['model'] as String?,
      manufacturer: _nonEmpty(c['manufacturer']),
      country: _nonEmpty(c['country']),
      nicknameSr: _nonEmpty(c['nickname_sr']),
      nicknameLatin: _nonEmpty(c['nickname_latin']),
      nicknameEn: _nonEmpty(c['nickname_en']),
      noteI18n: _noteI18n(c, 'human_note'),
      vehicleClassType: c['type'] as String?,
      operatorName: _nonEmpty(c['operator']),
      ac: c['ac'] as bool?,
      lowFloor: c['low_floor'] as bool?,
      articulated: c['articulated'] as bool?,
      lengthM: _asDouble(c['length_m']),
      capacity: _asInt(c['capacity']),
      yearsBuilt: _years(c['years_built']),
      comfortScore: _asInt(c['comfort_score']),
      powertrain: Powertrain.fromJson(c['powertrain']),
      usb: c['usb'] as bool?,
      assumedFields: assumed,
      approximate: approximate,
    );
  }

  /// Copy [base] (a bare catalog model-hit) with the operator name and type of
  /// the narrowest class range that contains [n].
  static FleetVehicle _enrichFromEnclosing(
    FleetVehicle base,
    int n,
    List<_ClassRange> ranges,
  ) {
    _ClassRange? best;
    for (final r in ranges) {
      if (n < r.lo || n > r.hi) continue;
      if (best == null || r.width < best.width) best = r;
    }
    if (best == null) return base;
    final enclosing = best.vehicle;
    return FleetVehicle(
      kind: base.kind,
      id: base.id,
      modelName: base.modelName,
      manufacturer: base.manufacturer,
      country: base.country,
      nicknameSr: base.nicknameSr,
      nicknameLatin: base.nicknameLatin,
      nicknameEn: base.nicknameEn,
      noteI18n: base.noteI18n,
      vehicleClassType: enclosing.vehicleClassType,
      operatorName: enclosing.operatorName,
      ac: base.ac,
      lowFloor: base.lowFloor,
      articulated: base.articulated,
      lengthM: base.lengthM,
      capacity: base.capacity,
      yearsBuilt: base.yearsBuilt,
      comfortScore: base.comfortScore,
      powertrain: base.powertrain,
      usb: base.usb,
      assumedFields: base.assumedFields,
      approximate: base.approximate,
    );
  }

  static List<int>? _years(Object? raw) {
    if (raw is! List || raw.length < 2) return null;
    final a = _asInt(raw[0]);
    final b = _asInt(raw[1]);
    if (a == null || b == null) return null;
    return [a, b];
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.round();
    return null;
  }

  static double? _asDouble(Object? v) {
    if (v is num) return v.toDouble();
    return null;
  }

  static String? _nonEmpty(Object? v) {
    if (v is String && v.trim().isNotEmpty) return v;
    return null;
  }

  /// Collect localized notes from `{prefix}_{ru,en,sr}` keys into a locale map,
  /// skipping empty/missing values.
  static Map<String, String> _noteI18n(Map<String, dynamic> src, String prefix) {
    final out = <String, String>{};
    for (final lang in const ['ru', 'en', 'sr']) {
      final v = _nonEmpty(src['${prefix}_$lang']);
      if (v != null) out[lang] = v;
    }
    return out;
  }
}
