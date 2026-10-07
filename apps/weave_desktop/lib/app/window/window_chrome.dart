import 'package:flutter/services.dart';

/// Where the native window draws its controls.
abstract interface class WindowChrome {
  /// Distance from the top of the window to the centre of the traffic
  /// lights, or `null` when unknown (e.g. in full screen or in tests).
  Future<double?> trafficLightCenter();
}

/// Asks the macOS runner over the `weave/window` channel.
final class MacosWindowChrome implements WindowChrome {
  const MacosWindowChrome();

  static const MethodChannel _channel = MethodChannel('weave/window');

  @override
  Future<double?> trafficLightCenter() async {
    try {
      final Object? center = await _channel.invokeMethod<Object?>('trafficLightCenter');
      return center is num && center > 0 ? center.toDouble() : null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
