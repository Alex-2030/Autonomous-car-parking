import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

import '../models/log_entry.dart';

// ---------------------------------------------------------------------------
// RobotCommand — single-byte character codes sent to the HC-05
// ---------------------------------------------------------------------------
class RobotCommand {
  static const String forward  = 'F';
  static const String backward = 'B';
  static const String left     = 'L';
  static const String right    = 'R';
  static const String stop     = 'S';
}

// ---------------------------------------------------------------------------
// BluetoothService
//
// Wraps flutter_bluetooth_serial's BluetoothConnection.
//
// Async stream logic:
//   BluetoothConnection exposes `input` as a Stream<Uint8List>.  Each chunk
//   is raw bytes from the HC-05 UART.  Because the ATmega32A sends short
//   strings ("ACK_DONE\n", "ERR_OBSTACLE\n") in one UART burst, chunks may
//   arrive split across multiple events OR merged.  We therefore accumulate
//   bytes into a local string buffer and only emit a complete message when
//   we see a newline ('\n') or after 80 ms of inactivity (fallback timer).
//   This guarantees real-time, frame-accurate UI updates without blocking the
//   main isolate.
// ---------------------------------------------------------------------------
class BluetoothService extends ChangeNotifier {
  // ── public observable state ────────────────────────────────────────────────
  bool get isConnected    => _connection?.isConnected ?? false;
  String? get deviceName  => _connectedDeviceName;
  String  get currentMode => _currentMode;
  List<LogEntry> get logs => List.unmodifiable(_logs);

  // ── private ────────────────────────────────────────────────────────────────
  BluetoothConnection? _connection;
  String? _connectedDeviceName;
  String  _currentMode = 'UNKNOWN';

  final List<LogEntry> _logs   = [];
  final StringBuffer   _rxBuf  = StringBuffer();
  StreamSubscription<Uint8List>? _inputSub;
  Timer? _flushTimer;

  // ── connect ───────────────────────────────────────────────────────────────
  Future<void> connectTo(BluetoothDevice device) async {
    if (isConnected) await disconnect();

    _addLog('Connecting to ${device.name ?? device.address} …', LogType.system);

    if (!Platform.isAndroid) {
      _addLog('Bluetooth SPP is not supported on Windows.', LogType.error);
      return;
    }

    try {
      _connection = await BluetoothConnection.toAddress(device.address)
          .timeout(const Duration(seconds: 10));

      _connectedDeviceName = device.name ?? device.address;
      _addLog('Connected to $_connectedDeviceName', LogType.system);
      notifyListeners();

      _listenToInputStream();
    } catch (e) {
      _addLog('Connection failed: $e', LogType.error);
      notifyListeners();
      rethrow;
    }
  }

  // ── disconnect ────────────────────────────────────────────────────────────
  Future<void> disconnect() async {
    _flushTimer?.cancel();
    await _inputSub?.cancel();
    _inputSub = null;

    _connection?.dispose();
    _connection = null;
    _connectedDeviceName = null;
    _rxBuf.clear();

    _addLog('Disconnected.', LogType.system);
    notifyListeners();
  }

  // ── send a single-character command ───────────────────────────────────────
  void sendCommand(String cmd) {
    if (!isConnected) {
      _addLog('Not connected — command "$cmd" dropped.', LogType.error);
      notifyListeners();
      return;
    }

    try {
      _connection!.output.add(Uint8List.fromList(utf8.encode(cmd)));
      _connection!.output.allSent;
      debugPrint('[BT TX] $cmd');
    } catch (e) {
      _addLog('TX error: $e', LogType.error);
      notifyListeners();
    }
  }

  // ── stream listener ───────────────────────────────────────────────────────
  //
  //   Every time a Uint8List chunk arrives from the HC-05:
  //     1. Decode bytes to UTF-8 and append to _rxBuf.
  //     2. If the buffer contains '\n', extract complete lines and dispatch.
  //     3. Reset a 80 ms inactivity timer; when it fires, flush any leftover
  //        content that never got a newline (handles firmware without '\n').
  //
  void _listenToInputStream() {
    _inputSub = _connection!.input!.listen(
      (Uint8List chunk) {
        // Restart the inactivity flush timer on every new byte arrival
        _flushTimer?.cancel();
        _flushTimer = Timer(const Duration(milliseconds: 80), _flushBuffer);

        _rxBuf.write(utf8.decode(chunk, allowMalformed: true));
        _processLines();
      },
      onDone: () {
        _flushBuffer();
        _addLog('Connection closed by remote device.', LogType.system);
        _connection = null;
        _connectedDeviceName = null;
        notifyListeners();
      },
      onError: (Object e) {
        _addLog('RX error: $e', LogType.error);
        notifyListeners();
      },
      cancelOnError: false,
    );
  }

  // Split accumulated buffer on newlines and dispatch each complete line
  void _processLines() {
    final raw = _rxBuf.toString();
    final lines = raw.split('\n');

    // Keep the incomplete last fragment in the buffer
    _rxBuf.clear();
    _rxBuf.write(lines.last);

    for (int i = 0; i < lines.length - 1; i++) {
      final line = lines[i].trim();
      if (line.isNotEmpty) _dispatchMessage(line);
    }
  }

  // Flush whatever is left when the inactivity timer fires
  void _flushBuffer() {
    final remaining = _rxBuf.toString().trim();
    _rxBuf.clear();
    if (remaining.isNotEmpty) _dispatchMessage(remaining);
  }

  // Map raw strings from the ATmega32A to typed log entries
  void _dispatchMessage(String msg) {
    debugPrint('[BT RX] $msg');

    LogEntry entry;

    if (msg.contains('Done') || msg.contains('Ready')) {
      entry = LogEntry(message: msg, type: LogType.success);
    } else if (msg.contains('Obstacle') || msg.contains('too small')) {
      entry = LogEntry(message: msg, type: LogType.error);
    } else if (msg.contains('[PARK]') || msg.contains('[MODE]') || msg.contains('[SM]')) {
      if (msg.contains('[MODE]')) {
        if (msg.contains('Manual')) {
          _currentMode = 'MANUAL';
        } else if (msg.contains('Autonomous')) {
          _currentMode = 'AUTO';
        }
      }
      entry = LogEntry(message: msg, type: LogType.system);
    } else {
      // Handles the raw sensor data line: S=... F=... PREV=...
      entry = LogEntry(message: msg, type: LogType.info);
    }

    _addLog(entry.message, entry.type);
    notifyListeners();
  }

  // ── helpers ───────────────────────────────────────────────────────────────
  void _addLog(String msg, LogType type) {
    _logs.add(LogEntry(message: msg, type: type));
    // Keep a rolling window of the last 200 lines
    if (_logs.length > 200) _logs.removeAt(0);
  }

  void clearLogs() {
    _logs.clear();
    _currentMode = 'UNKNOWN';
    notifyListeners();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _inputSub?.cancel();
    _connection?.dispose();
    super.dispose();
  }
}
