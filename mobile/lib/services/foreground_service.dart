import 'dart:io';
import 'package:flutter/services.dart';

class SafeHelmForegroundService {
  static const _channel = MethodChannel('safehelm/service');

  static Future<void> start({String status = 'SafeHelm Protection Armed — Helmet Active'}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start', {'status': status});
    } catch (_) {}
  }

  static Future<void> update(String status) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('update', {'status': status});
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
