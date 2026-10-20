import 'dart:io';
import 'package:flutter/services.dart';

class AlarmService {
  static const _channel = MethodChannel('safehelm/alarm');

  static Future<void> startAlarm() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('startAlarm');
    } catch (_) {}
  }

  static Future<void> stopAlarm() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stopAlarm');
    } catch (_) {}
  }
}
