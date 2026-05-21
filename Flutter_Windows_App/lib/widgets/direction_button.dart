import 'package:flutter/material.dart';

/// A single directional control button.
/// Sends the command byte on [onTapDown] and sends STOP on [onTapUp].
class DirectionButton extends StatefulWidget {
  final IconData icon;
  final String label;
  final String command;
  final VoidCallback onPress;   // fires on tap-down
  final VoidCallback onRelease; // fires on tap-up / cancel

  const DirectionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.command,
    required this.onPress,
    required this.onRelease,
  });

  @override
  State<DirectionButton> createState() => _DirectionButtonState();
}

class _DirectionButtonState extends State<DirectionButton>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _down() {
    if (_pressed) return;
    _pressed = true;
    _ctrl.forward();
    widget.onPress();
  }

  void _up() {
    if (!_pressed) return;
    _pressed = false;
    _ctrl.reverse();
    widget.onRelease();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _down(),
      onTapUp: (_) => _up(),
      onTapCancel: _up,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 84,
          height: 84,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFF1A2540),
                const Color(0xFF0D1526),
              ],
            ),
            border: Border.all(
              color: _pressed
                  ? const Color(0xFF00D4FF)
                  : const Color(0xFF1E2D50),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00D4FF).withOpacity(_pressed ? 0.55 : 0.15),
                blurRadius: _pressed ? 20 : 8,
                spreadRadius: _pressed ? 2 : 0,
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color: _pressed
                    ? const Color(0xFF00D4FF)
                    : const Color(0xFF6A7FA8),
                size: 28,
              ),
              const SizedBox(height: 2),
              Text(
                widget.label,
                style: TextStyle(
                  color: _pressed
                      ? const Color(0xFF00D4FF)
                      : const Color(0xFF4A5A7A),
                  fontSize: 9,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
