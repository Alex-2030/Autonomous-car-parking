import 'package:flutter/material.dart';
import 'package:flutter_bluetooth_serial_plus/flutter_bluetooth_serial_plus.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../services/bluetooth_service.dart';

/// Shows paired Bluetooth devices and lets the user pick the HC-05.
/// Calls [bluetoothService.connectTo] on selection.
class DeviceListScreen extends StatefulWidget {
  final BluetoothService bluetoothService;

  const DeviceListScreen({super.key, required this.bluetoothService});

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen> {
  List<BluetoothDevice> _devices = [];
  bool _loading = true;
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    _loadPairedDevices();
  }

  Future<void> _loadPairedDevices() async {
    setState(() => _loading = true);
    
    try {
      if (Platform.isAndroid) {
        // Request Android 12+ Bluetooth permissions
        Map<Permission, PermissionStatus> statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.location,
        ].request();
      }

      if (!Platform.isAndroid) {
        final availablePorts = SerialPort.availablePorts;
        
        setState(() {
          _devices = availablePorts.map((port) {
            String desc = 'Serial Device';
            try {
              final sp = SerialPort(port);
              if (sp.description != null && sp.description!.isNotEmpty) {
                desc = sp.description!;
              }
              sp.dispose();
            } catch (_) {}
            
            return BluetoothDevice(
              address: port,
              name: '$port ($desc)',
              isConnected: false,
            );
          }).toList();
          
          if (_devices.isEmpty) {
            _devices.add(BluetoothDevice(
              address: 'COM10',
              name: 'Windows COM Port (COM10 Fallback)',
              isConnected: false,
            ));
          }
          _loading = false;
        });
        return;
      }

      // Check if Bluetooth is even turned on
      bool? isEnabled = await FlutterBluetoothSerial.instance.isEnabled;
      if (isEnabled == false) {
        await FlutterBluetoothSerial.instance.requestEnable();
      }

      final devices = await FlutterBluetoothSerial.instance.getBondedDevices();
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load devices: $e'),
            backgroundColor: const Color(0xFFFF4563),
          ),
        );
      }
    }
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() => _connectingAddress = device.address);
    try {
      await widget.bluetoothService.connectTo(device);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to connect: $e'),
            backgroundColor: const Color(0xFFFF4563),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _connectingAddress = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1526),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Color(0xFF6A7FA8), size: 20),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: const Text(
          'SELECT DEVICE',
          style: TextStyle(
            color: Color(0xFF00D4FF),
            fontSize: 13,
            letterSpacing: 3,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF6A7FA8), size: 22),
            onPressed: _loadPairedDevices,
            tooltip: 'Refresh',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFF1A2540)),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF00D4FF)),
            )
          : _devices.isEmpty
              ? _emptyState()
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _DeviceTile(
                    device: _devices[i],
                    isConnecting:
                        _connectingAddress == _devices[i].address,
                    onTap: () => _connect(_devices[i]),
                  ),
                ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bluetooth_disabled_rounded,
              size: 56, color: const Color(0xFF1A2540)),
          const SizedBox(height: 16),
          const Text(
            'No paired devices found.\nPair the HC-05 in Android Settings first.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF3A4A6A),
              fontSize: 13,
              height: 1.7,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _loadPairedDevices,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF00D4FF),
              side: const BorderSide(color: Color(0xFF00D4FF), width: 1),
            ),
          ),
        ],
      ),
    );
  }
}

// ── device tile ───────────────────────────────────────────────────────────────

class _DeviceTile extends StatelessWidget {
  final BluetoothDevice device;
  final bool isConnecting;
  final VoidCallback onTap;

  const _DeviceTile({
    required this.device,
    required this.isConnecting,
    required this.onTap,
  });

  bool get _isRobot =>
      (device.name ?? '').toLowerCase().contains('hc-05') ||
      (device.name ?? '').toLowerCase().contains('robot') ||
      (device.name ?? '').toLowerCase().contains('hc05');

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: isConnecting ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1526),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _isRobot
                ? const Color(0xFF00D4FF).withOpacity(0.5)
                : const Color(0xFF1A2540),
            width: 1.5,
          ),
          boxShadow: _isRobot
              ? [
                  BoxShadow(
                    color: const Color(0xFF00D4FF).withOpacity(0.08),
                    blurRadius: 12,
                  )
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRobot
                    ? const Color(0xFF00D4FF).withOpacity(0.12)
                    : const Color(0xFF1A2540),
              ),
              child: Icon(
                _isRobot
                    ? Icons.precision_manufacturing_rounded
                    : Icons.bluetooth_rounded,
                color: _isRobot
                    ? const Color(0xFF00D4FF)
                    : const Color(0xFF4A5A7A),
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    device.name ?? 'Unknown Device',
                    style: TextStyle(
                      color: _isRobot
                          ? const Color(0xFFE0EAFF)
                          : const Color(0xFF8A9ABB),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    device.address,
                    style: const TextStyle(
                      color: Color(0xFF3A4A6A),
                      fontSize: 10,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
            if (isConnecting)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF00D4FF),
                ),
              )
            else
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 14,
                color: _isRobot
                    ? const Color(0xFF00D4FF)
                    : const Color(0xFF2A3550),
              ),
          ],
        ),
      ),
    );
  }
}
