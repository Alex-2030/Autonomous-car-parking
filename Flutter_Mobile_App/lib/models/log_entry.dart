import 'package:flutter/material.dart';

enum LogType { info, success, error, system }

class LogEntry {
  final String message;
  final LogType type;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.type,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Color get color {
    switch (type) {
      case LogType.success:
        return const Color(0xFF00FF9C); // neon green
      case LogType.error:
        return const Color(0xFFFF4563); // neon red
      case LogType.system:
        return const Color(0xFF00D4FF); // neon cyan
      case LogType.info:
        return const Color(0xFFB0B8D0); // muted white
    }
  }

  String get prefix {
    switch (type) {
      case LogType.success:
        return '[OK]  ';
      case LogType.error:
        return '[ERR] ';
      case LogType.system:
        return '[SYS] ';
      case LogType.info:
        return '[INF] ';
    }
  }

  String get timeLabel {
    final h = timestamp.hour.toString().padLeft(2, '0');
    final m = timestamp.minute.toString().padLeft(2, '0');
    final s = timestamp.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
