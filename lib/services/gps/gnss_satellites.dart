import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

int estimateSatellitesFromAccuracy(double accuracy) {
  if (!accuracy.isFinite || accuracy <= 0) return 0;
  if (accuracy > 800) return 2;
  if (accuracy > 200) return 3;
  if (accuracy > 75) return 4;
  if (accuracy > 30) return 5;
  if (accuracy > 15) return 7;
  if (accuracy > 8) return 9;
  return 11;
}

int resolveSatellites({required double accuracy, int? realCount}) {
  if (realCount != null && realCount > 3) return realCount;
  return estimateSatellitesFromAccuracy(accuracy);
}

class GnssSatelliteSource {
  static const MethodChannel _channel = MethodChannel('qunleashed/gnss');

  final bool _supported = Platform.isAndroid;
  bool _started = false;
  int? _cached;

  bool get supported => _supported;
  int? get cached => _cached;

  Future<void> start() async {
    if (!_supported || _started) return;
    try {
      await _channel.invokeMethod<void>('start');
      _started = true;
    } on PlatformException {
      _started = false;
    } on MissingPluginException {
      _started = false;
    }
  }

  Future<int?> poll() async {
    if (!_supported || !_started) return null;
    try {
      final count = await _channel.invokeMethod<int>('count');
      _cached = count;
      return count;
    } on PlatformException {
      return _cached;
    } on MissingPluginException {
      return _cached;
    }
  }

  Future<void> stop() async {
    if (!_supported || !_started) return;
    _started = false;
    _cached = null;
    try {
      await _channel.invokeMethod<void>('stop');
    } on PlatformException {
      return;
    } on MissingPluginException {
      return;
    }
  }
}
