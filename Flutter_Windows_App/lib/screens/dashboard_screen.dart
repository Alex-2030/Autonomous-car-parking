import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';

import '../models/log_entry.dart';
import '../services/bluetooth_service.dart';
import '../widgets/direction_button.dart';
import '../widgets/terminal_panel.dart';
import 'device_list_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final BluetoothService _bt = BluetoothService();

  // Pulse animation for the status ring when connected
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  // Active movement label shown in the centre HUD
  String _activeCmd = '●';
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();

    _bt.addListener(_onBtStateChange);

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.4, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  void _onBtStateChange() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _bt.removeListener(_onBtStateChange);
    _bt.dispose();
    _pulseCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── command helpers ────────────────────────────────────────────────────────

  void _press(String cmd, String label) {
    setState(() => _activeCmd = label);
    _bt.sendCommand(cmd);
  }

  void _release() {
    setState(() => _activeCmd = '●');
    _bt.sendCommand(RobotCommand.stop);
  }

  // ── connection flow ────────────────────────────────────────────────────────

  Future<void> _openDeviceList() async {
    await Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) =>
            DeviceListScreen(bluetoothService: _bt),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  Future<void> _disconnect() async {
    setState(() => _activeCmd = '●');
    await _bt.disconnect();
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final connected = _bt.isConnected;
    final size = MediaQuery.of(context).size;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (!connected) return KeyEventResult.ignored;

        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyW) {
            _press(RobotCommand.forward, '▲');
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyS) {
            _press(RobotCommand.backward, '▼');
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyA) {
            _press(RobotCommand.left, '◀');
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.keyD) {
            _press(RobotCommand.right, '▶');
            return KeyEventResult.handled;
          }
        } else if (event is KeyUpEvent) {
          if (event.logicalKey == LogicalKeyboardKey.keyW ||
              event.logicalKey == LogicalKeyboardKey.keyS ||
              event.logicalKey == LogicalKeyboardKey.keyA ||
              event.logicalKey == LogicalKeyboardKey.keyD) {
            _release();
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0A0E1A),
        body: SafeArea(
          child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            children: [
              // ── top bar ──────────────────────────────────────────────────
              _buildTopBar(connected),

              const SizedBox(height: 16),

              // ── centre HUD ───────────────────────────────────────────────
              _buildHud(connected),

              const SizedBox(height: 20),

              // ── D-pad controls ───────────────────────────────────────────
              _buildDPad(connected),

              const SizedBox(height: 20),

              // ── terminal panel (flexible) ────────────────────────────────
              Expanded(
                child: TerminalPanel(
                  logs: _bt.logs,
                  onClear: _bt.clearLogs,
                ),
              ),

              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
    ),
    );
  }

  // ── top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(bool connected) {
    return Row(
      children: [
        // App title
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'ROBOT MANUAL CONTROLLER',
              style: TextStyle(
                color: Color(0xFFE0EAFF),
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            Text(
              connected
                  ? 'CONNECTED · ${_bt.deviceName ?? ""}'
                  : 'DISCONNECTED',
              style: TextStyle(
                color: connected
                    ? const Color(0xFF00FF9C)
                    : const Color(0xFF3A4A6A),
                fontSize: 9,
                letterSpacing: 2,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),

        const Spacer(),

        // Connection status dot (animated when connected)
        if (connected)
          AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, __) => Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00FF9C)
                    .withOpacity(_pulseAnim.value),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF00FF9C)
                        .withOpacity(_pulseAnim.value * 0.6),
                    blurRadius: 8,
                  ),
                ],
              ),
            ),
          ),

        // Connect / disconnect button
        _GlassButton(
          label: connected ? 'DISCONNECT' : 'CONNECT',
          icon: connected
              ? Icons.bluetooth_disabled_rounded
              : Icons.bluetooth_searching_rounded,
          color: connected
              ? const Color(0xFFFF4563)
              : const Color(0xFF00D4FF),
          onTap: connected ? _disconnect : _openDeviceList,
        ),
      ],
    );
  }

  // ── centre HUD ─────────────────────────────────────────────────────────────

  Widget _buildHud(bool connected) {
    return Container(
      height: 110,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1526),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: connected
              ? const Color(0xFF00D4FF).withOpacity(0.25)
              : const Color(0xFF1A2540),
          width: 1.5,
        ),
        boxShadow: connected
            ? [
                BoxShadow(
                  color: const Color(0xFF00D4FF).withOpacity(0.06),
                  blurRadius: 24,
                  spreadRadius: 4,
                ),
              ]
            : [],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Central command indicator
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF060B16),
                  border: Border.all(
                    color: connected
                        ? const Color(0xFF00D4FF).withOpacity(0.4)
                        : const Color(0xFF1A2540),
                    width: 2,
                  ),
                ),
                child: Center(
                  child: Text(
                    connected ? _activeCmd : '○',
                    style: TextStyle(
                      color: connected
                          ? const Color(0xFF00D4FF)
                          : const Color(0xFF2A3550),
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'COMMAND',
                style: const TextStyle(
                  color: Color(0xFF2A3550),
                  fontSize: 8,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),

          // Mode badge
          _HudBadge(
            label: 'MODE',
            value: connected ? _bt.currentMode : 'IDLE',
            unit: 'BT',
            color: connected
                ? const Color(0xFF00FF9C)
                : const Color(0xFF3A4A6A),
          ),
        ],
      ),
    );
  }

  // ── D-pad ──────────────────────────────────────────────────────────────────

  Widget _buildDPad(bool connected) {
    return Opacity(
      opacity: connected ? 1.0 : 0.35,
      child: IgnorePointer(
        ignoring: !connected,
        child: Column(
          children: [
            // Forward
            DirectionButton(
              icon: Icons.keyboard_arrow_up_rounded,
              label: 'FWD',
              command: RobotCommand.forward,
              onPress:  () => _press(RobotCommand.forward,  '▲'),
              onRelease: _release,
            ),

            const SizedBox(height: 12),

            // Left | Stop ring | Right
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DirectionButton(
                  icon: Icons.keyboard_arrow_left_rounded,
                  label: 'LEFT',
                  command: RobotCommand.left,
                  onPress:  () => _press(RobotCommand.left, '◄'),
                  onRelease: _release,
                ),

                const SizedBox(width: 12),

                // Centre stop button
                GestureDetector(
                  onTap: connected
                      ? () => _bt.sendCommand(RobotCommand.stop)
                      : null,
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A0A12),
                      border: Border.all(
                        color: const Color(0xFFFF4563).withOpacity(0.6),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF4563).withOpacity(0.2),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Text(
                        'STOP',
                        style: TextStyle(
                          color: Color(0xFFFF4563),
                          fontSize: 9,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                DirectionButton(
                  icon: Icons.keyboard_arrow_right_rounded,
                  label: 'RIGHT',
                  command: RobotCommand.right,
                  onPress:  () => _press(RobotCommand.right, '►'),
                  onRelease: _release,
                ),
              ],
            ),

            const SizedBox(height: 12),

            // Backward
            DirectionButton(
              icon: Icons.keyboard_arrow_down_rounded,
              label: 'BWD',
              command: RobotCommand.backward,
              onPress:  () => _press(RobotCommand.backward, '▼'),
              onRelease: _release,
            ),
          ],
        ),
      ),
    );
  }
}

// ── reusable sub-widgets ───────────────────────────────────────────────────────

class _HudBadge extends StatelessWidget {
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _HudBadge({
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF3A4A6A),
            fontSize: 8,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 22,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
          ),
        ),
        Text(
          unit,
          style: TextStyle(
            color: color.withOpacity(0.5),
            fontSize: 8,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class _GlassButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _GlassButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: color.withOpacity(0.4), width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 9,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
