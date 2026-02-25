import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class KioskView extends StatefulWidget {
  final VoidCallback onDismiss;
  const KioskView({super.key, required this.onDismiss});

  @override
  State<KioskView> createState() => _KioskViewState();
}

class _KioskViewState extends State<KioskView> {
  int _currentImageIndex = 0;
  String _currentTime = "";
  late Timer _kioskTimer;
  late Timer _clockTimer;

  final List<String> _kioskImages = [
    'https://images.unsplash.com/photo-1581091226825-a6a2a5aee158?auto=format&fit=crop&q=80&w=1600',
    'https://images.unsplash.com/photo-1565514020179-026b92b84bb6?auto=format&fit=crop&q=80&w=1600',
    'https://images.unsplash.com/photo-1518770660439-4636190af475?auto=format&fit=crop&q=80&w=1600',
  ];

  @override
  void initState() {
    super.initState();
    _startTimers();
  }

  void _startTimers() {
    _kioskTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
      if (mounted) {
        setState(() => _currentImageIndex = (_currentImageIndex + 1) % _kioskImages.length);
      }
    });
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _currentTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now()));
      }
    });
  }

  @override
  void dispose() {
    _kioskTimer.cancel();
    _clockTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onDismiss,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 1000),
            child: Image.network(
              _kioskImages[_currentImageIndex],
              key: ValueKey(_currentImageIndex),
              fit: BoxFit.cover,
              width: double.infinity,
              height: double.infinity,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.black87),
            ),
          ),
          Container(color: Colors.black.withOpacity(0.3)),
          Positioned(
            top: 60,
            left: 40,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_currentTime, style: const TextStyle(color: Colors.white, fontSize: 48, fontWeight: FontWeight.w200, letterSpacing: 2)),
                const SizedBox(height: 10),
                const Text("RFID 솔루션 대기 중...", style: TextStyle(color: Colors.white70, fontSize: 18)),
              ],
            ),
          ),
          Positioned(
            bottom: 60,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 40),
              color: Colors.black.withOpacity(0.5),
              child: const Row(
                children: [
                  FaIcon(FontAwesomeIcons.bullhorn, color: Colors.orangeAccent, size: 24),
                  SizedBox(width: 20),
                  Expanded(
                    child: Text("[공지] 실시간 장치 모니터링 시스템 가동 중", style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}