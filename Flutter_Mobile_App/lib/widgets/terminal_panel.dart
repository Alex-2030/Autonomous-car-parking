import 'package:flutter/material.dart';
import '../models/log_entry.dart';

/// Terminal-style scrolling panel that displays all robot feedback messages.
class TerminalPanel extends StatefulWidget {
  final List<LogEntry> logs;
  final VoidCallback onClear;

  const TerminalPanel({
    super.key,
    required this.logs,
    required this.onClear,
  });

  @override
  State<TerminalPanel> createState() => _TerminalPanelState();
}

class _TerminalPanelState extends State<TerminalPanel> {
  final ScrollController _scroll = ScrollController();

  @override
  void didUpdateWidget(covariant TerminalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Auto-scroll to the newest line after the frame is rendered
    if (widget.logs.length != oldWidget.logs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF060B16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1A2540), width: 1.5),
        boxShadow: const [
          BoxShadow(
            color: Color(0xFF00D4FF10),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── header bar ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFF0D1526),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(
                bottom: BorderSide(color: Color(0xFF1A2540), width: 1),
              ),
            ),
            child: Row(
              children: [
                // Traffic-light dots
                _Dot(color: const Color(0xFFFF4563)),
                const SizedBox(width: 6),
                _Dot(color: const Color(0xFFFFCC00)),
                const SizedBox(width: 6),
                _Dot(color: const Color(0xFF00FF9C)),
                const SizedBox(width: 12),
                const Text(
                  'ROBOT TERMINAL',
                  style: TextStyle(
                    color: Color(0xFF6A7FA8),
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                // Clear button
                GestureDetector(
                  onTap: widget.onClear,
                  child: const Text(
                    'CLEAR',
                    style: TextStyle(
                      color: Color(0xFF3A4A6A),
                      fontSize: 9,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── log lines ──────────────────────────────────────────────────
          Expanded(
            child: widget.logs.isEmpty
                ? const Center(
                    child: Text(
                      'Awaiting robot response …',
                      style: TextStyle(
                        color: Color(0xFF2A3550),
                        fontSize: 11,
                        letterSpacing: 1,
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(10),
                    itemCount: widget.logs.length,
                    itemBuilder: (_, i) => _LogLine(entry: widget.logs[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

class _Dot extends StatelessWidget {
  final Color color;
  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}

class _LogLine extends StatelessWidget {
  final LogEntry entry;
  const _LogLine({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          Text(
            entry.timeLabel,
            style: const TextStyle(
              color: Color(0xFF2A3A5A),
              fontSize: 10,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(width: 8),
          // Type prefix
          Text(
            entry.prefix,
            style: TextStyle(
              color: entry.color.withOpacity(0.6),
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
            ),
          ),
          // Message
          Expanded(
            child: Text(
              entry.message,
              style: TextStyle(
                color: entry.color,
                fontSize: 10,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
