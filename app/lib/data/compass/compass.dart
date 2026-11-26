// The phone's compass heading for the location dot's cone (DS LocationDot).
// Web reads the DeviceOrientation events; other platforms have no source yet.
export 'compass_io.dart' if (dart.library.js_interop) 'compass_web.dart';
