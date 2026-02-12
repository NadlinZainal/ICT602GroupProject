import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/session.dart';
import '../services/beacon_service.dart';
import '../services/notification_service.dart';
import 'checkin_screen.dart';
import 'package:google_fonts/google_fonts.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  String _matric = '';

  @override
  void initState() {
    super.initState();
    _loadMatric();
    final notif = NotificationService();
    notif.init();
    // listen to beacon changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final beacon = Provider.of<BeaconService>(context, listen: false);
      beacon.addListener(_onBeaconChange);
      beacon.startScanning();
    });
  }

  Future<void> _loadMatric() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _matric = prefs.getString('matric') ?? '';
    });
  }

  void _onBeaconChange() {
    final beacon = Provider.of<BeaconService>(context, listen: false);
    if (beacon.isInside) {
      debugPrint('[DEBUG] Enter detected, starting session and welcome flow');
      _startSession();
      _showWelcomeFlow();
    } else {
      debugPrint('[DEBUG] Exit detected, ending session and exit flow');
      _endSession();
      _showExitFlow();
    }
  }

  void _startSession() {
    _ticker?.cancel();
    setState(() {
      _elapsed = Duration.zero;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() => _elapsed += const Duration(seconds: 1));
    });
  }

  Future<void> _endSession() async {
    _ticker?.cancel();
    if (_matric.isNotEmpty) {
      final now = DateTime.now();
      final session = Session(matric: _matric, start: now.subtract(_elapsed), end: now);
      // Save session to Firestore
      await FirebaseFirestore.instance.collection('sessions').add({
        'matric': session.matric,
        'start': session.start.toIso8601String(),
        'end': session.end.toIso8601String(),
        'duration_seconds': session.duration.inSeconds,
      });
    }
    setState(() {
      _elapsed = Duration.zero;
    });
  }

  Future<void> _showWelcomeFlow() async {
    final notif = NotificationService();
    await notif.showNotification(title: 'Welcome to Perpustakaan Tun Abdul Razak UiTM', body: 'Please switch your phone to silent.');
    _showRulesIfNeeded();
  }

  Future<void> _showExitFlow() async {
  debugPrint('[DEBUG] Showing exit notification');
  final notif = NotificationService();
  await notif.showNotification(title: 'Thank you', body: 'Thanks for visiting the library.');
  }

  Future<void> _showRulesIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final hide = prefs.getBool('hide_rules') ?? false;
    if (!hide) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Library Rules'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('• No food allowed'),
              Text('• Plese keep quiet'),
              Text('• Put your phone on silent'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await prefs.setBool('hide_rules', true);
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text("Don't show again"),
            ),
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    final beacon = Provider.of<BeaconService>(context, listen: false);
    beacon.removeListener(_onBeaconChange);
    super.dispose();
  }

  String _formatDuration(Duration d) {
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }


  @override
  Widget build(BuildContext context) {
    final beacon = Provider.of<BeaconService>(context);
    final isInside = beacon.isInside;
    final status = isInside ? 'Inside' : 'Outside';
    final now = DateFormat.jm().format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('PTAR UiTM Jasin'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOut,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isInside
                        ? [Colors.green.shade800, Colors.green.shade600]
                        : [Colors.blueGrey.shade800, Colors.blueGrey.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: (isInside ? Colors.green : Colors.blueGrey).withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Icon(
                      isInside ? Icons.vpn_key : Icons.door_back_door,
                      color: Colors.white,
                      size: 48,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      status.toUpperCase(),
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Current Status',
                      style: GoogleFonts.poppins(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 32),
                     Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildStatusItem(Icons.access_time, 'Time', now),
                        if (isInside)
                          _buildStatusItem(Icons.timer, 'Session', _formatDuration(_elapsed)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
                  ),
                  title: Text(
                    _matric.isEmpty ? 'Not checked in' : _matric,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Matric ID'),
                  trailing: IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final r = await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CheckinScreen()));
                      if (r == true) _loadMatric();
                    },
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              Text(
                'Quick Actions',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                crossAxisSpacing: 16,
                mainAxisSpacing: 16,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildActionButton(
                    context,
                    icon: Icons.rule,
                    label: 'Library Rules',
                    color: Colors.orange,
                    onTap: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('hide_rules', false);
                      _showRulesIfNeeded();
                    },
                  ),
                  _buildActionButton(
                    context,
                    icon: Icons.notifications_active,
                    label: 'Silent Reminder',
                    color: Colors.purple,
                    onTap: () async {
                      final notif = NotificationService();
                      await notif.showNotification(title: 'Silent Reminder', body: 'Please switch to silent mode');
                    },
                  ),
                  _buildActionButton(
                     context,
                     icon: Icons.bug_report,
                     label: 'Simulate Toggle',
                     color: Colors.teal,
                     onTap: () {
                        final b = Provider.of<BeaconService>(context, listen: false);
                        b.toggleMock();
                     }
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          label,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildActionButton(BuildContext context, {required IconData icon, required String label, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(height: 12),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}
