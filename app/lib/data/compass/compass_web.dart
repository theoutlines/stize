import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Compass headings in degrees clockwise from north, where the top of the
/// phone points.
///
/// iOS Safari puts it in `webkitCompassHeading` on `deviceorientation`, once
/// the page holds permission ([requestCompassPermission]). Android Chrome sends
/// `deviceorientationabsolute`, whose `alpha` grows counter-clockwise from
/// north. Either way the screen's own rotation is added, so a phone held
/// sideways still points the cone the right way. Desktop browsers send
/// nothing, and the stream stays silent.
Stream<double> compassHeadings() {
  late StreamController<double> controller;
  JSFunction? listener;
  String? type;

  void onEvent(JSObject e) {
    double? heading;
    final webkit = e.getProperty<JSAny?>('webkitCompassHeading'.toJS);
    if (webkit != null && webkit.isA<JSNumber>()) {
      heading = (webkit as JSNumber).toDartDouble;
    } else {
      final absolute = e.getProperty<JSAny?>('absolute'.toJS);
      final alpha = e.getProperty<JSAny?>('alpha'.toJS);
      final isAbsolute =
          type == 'deviceorientationabsolute' ||
          (absolute != null &&
              absolute.isA<JSBoolean>() &&
              (absolute as JSBoolean).toDart);
      if (isAbsolute && alpha != null && alpha.isA<JSNumber>()) {
        heading = 360 - (alpha as JSNumber).toDartDouble;
      }
    }
    if (heading == null || heading.isNaN) return;
    heading = (heading + _screenAngle()) % 360;
    if (heading < 0) heading += 360;
    controller.add(heading);
  }

  controller = StreamController<double>.broadcast(
    onListen: () {
      type = globalContext.has('ondeviceorientationabsolute')
          ? 'deviceorientationabsolute'
          : 'deviceorientation';
      listener = onEvent.toJS;
      globalContext.callMethod('addEventListener'.toJS, type!.toJS, listener);
    },
    onCancel: () {
      if (listener != null && type != null) {
        globalContext.callMethod(
          'removeEventListener'.toJS,
          type!.toJS,
          listener,
        );
      }
      listener = null;
    },
  );
  return controller.stream;
}

double _screenAngle() {
  final screen = globalContext.getProperty<JSObject?>('screen'.toJS);
  final orientation = screen?.getProperty<JSObject?>('orientation'.toJS);
  final angle = orientation?.getProperty<JSAny?>('angle'.toJS);
  if (angle != null && angle.isA<JSNumber>()) {
    return (angle as JSNumber).toDartDouble;
  }
  return 0;
}

/// iOS 13+ hands out the compass only after `requestPermission()`, called
/// straight from a user gesture (the Locate tap). Call it before any await in
/// the tap handler. Elsewhere there is nothing to ask and this returns true.
Future<bool> requestCompassPermission() async {
  final ctor = globalContext.getProperty<JSObject?>(
    'DeviceOrientationEvent'.toJS,
  );
  if (ctor == null || !ctor.has('requestPermission')) return true;
  try {
    final result = await ctor
        .callMethod<JSPromise<JSString>>('requestPermission'.toJS)
        .toDart;
    return result.toDart == 'granted';
  } catch (_) {
    return false;
  }
}
