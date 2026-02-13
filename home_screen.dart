import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
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

  // For break reminders
  Timer? _breakReminderTimer;
  int _lastBreakReminderMinutes = 0;

  // For time spent reminders
  Timer? _timeSpentTimer;
  int _lastTimeSpentReminderMinutes = 0;

  @override
  void initState() {
    super.initState();
    _loadMatric().then((_) {
      // Check for first time welcome after login
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkFirstTimeWelcome();
      });
    });

    final notif = NotificationService();
    notif.init();
    notif.requestPermissions();

    // listen to beacon changes
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final beacon = Provider.of<BeaconService>(context, listen: false);
      beacon.addListener(_onBeaconChange);
      beacon.startScanning();
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    return 'Good Evening';
  }

  String _getFormattedDate() {
    final now = DateTime.now();
    return DateFormat('EEE, dd MMM').format(now);
  }

  Future<void> _checkFirstTimeWelcome() async {
    final prefs = await SharedPreferences.getInstance();
    final justLoggedIn = prefs.getBool('just_logged_in') ?? false;

    if (justLoggedIn && _matric.isNotEmpty) {
      // Reset flag
      await prefs.setBool('just_logged_in', false);

      // Show welcome popup
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Icon(Icons.waving_hand, size: 50, color: Colors.deepPurple),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Welcome,',
                style: TextStyle(fontSize: 18, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 8),
              Text(
                _matric,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepPurple,
                ),
              ),
              const SizedBox(height: 16),
              const Text('Have a productive study session! 📚'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _loadMatric() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _matric = prefs.getString('matric') ?? '';
    });
  }

  // ✅ LOGOUT FUNCTION
  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    final oldMatric = _matric;

    // Clear matric from SharedPreferences
    await prefs.remove('matric');

    setState(() {
      _matric = '';
    });

    // Show Thank You popup
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Icon(Icons.exit_to_app, size: 50, color: Colors.deepPurple), // ✅ FIXED
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Thank You!',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              'Goodbye, $oldMatric',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 8),
            const Text('See you again at PTAR UiTM Jasin! 📚'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    // Optional: Send logout notification
    final notif = NotificationService();
    await notif.showNotification(
      id: 3,
      title: '👋 Logged Out',
      body: 'You have been logged out. See you next time!',
    );
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

    _breakReminderTimer?.cancel();
    _breakReminderTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkBreakReminders();
    });

    _timeSpentTimer?.cancel();
    _timeSpentTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      _checkTimeSpentReminders();
    });
  }

  void _checkBreakReminders() async {
    if (!mounted) return;

    final minutes = _elapsed.inMinutes;

    if (minutes >= 30 && minutes % 30 == 0 && minutes > _lastBreakReminderMinutes) {
      _lastBreakReminderMinutes = minutes;
      final notif = NotificationService();
      await notif.showBreakReminder(minutes);
    }
  }

  void _checkTimeSpentReminders() async {
    if (!mounted) return;

    final minutes = _elapsed.inMinutes;
    final reminderTimes = [15, 30, 45, 60, 75, 90, 105, 120];

    if (reminderTimes.contains(minutes + 1) && minutes > _lastTimeSpentReminderMinutes) {
      _lastTimeSpentReminderMinutes = minutes;
      final notif = NotificationService();
      await notif.showTimeSpentReminder(minutes + 1);
      debugPrint('✅ ${minutes + 1} minute reminder sent at ${minutes}m ${_elapsed.inSeconds % 60}s');
    }
  }

  Future<void> _endSession() async {
    _ticker?.cancel();
    if (_matric.isNotEmpty) {
      final now = DateTime.now();
      final session = Session(
          matric: _matric, start: now.subtract(_elapsed), end: now);

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
    await notif.showNotification(
        id: 1,
        title: 'Welcome to Perpustakaan Tun Abdul Razak UiTM',
        body: 'Please switch your phone to silent.'
    );
    _showRulesIfNeeded();
  }

  Future<void> _showExitFlow() async {
    debugPrint('[DEBUG] Showing exit notification');
    final notif = NotificationService();

    String durationText = _formatDuration(_elapsed);
    await notif.showNotification(
        id: 2,
        title: 'Thank you',
        body: 'Thanks for visiting the library. You spent $durationText in the library.'
    );
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
              Text('• Please keep quiet'),
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
            TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK')
            ),
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
    final currentTime = DateFormat.jm().format(DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: const Text('PTAR UiTM Jasin'),
        // ✅ ADD LOGIN/LOGOUT BUTTON IN APPBAR
        actions: [
          if (_matric.isEmpty)
          // LOGIN BUTTON
            IconButton(
              icon: const Icon(Icons.login),
              tooltip: 'Login',
              onPressed: () async {
                final result = await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const CheckinScreen())
                );
                if (result == true) _loadMatric();
              },
            )
          else
          // LOGOUT BUTTON
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: _logout,
            ),
        ],
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
                        ? [Colors.green.shade800, Colors.teal.shade600]
                        : [Colors.deepPurple.shade800, Colors.purple.shade700],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: (isInside ? Colors.green : Colors.deepPurple)
                          .withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned(
                      right: -20,
                      bottom: -20,
                      child: Opacity(
                        opacity: 0.1,
                        child: Icon(
                          Icons.menu_book,
                          size: 120,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    Column(
                      children: [
                        TweenAnimationBuilder(
                          tween: Tween<double>(begin: 0.8, end: 1.0),
                          duration: const Duration(seconds: 1),
                          curve: Curves.easeInOut,
                          builder: (context, scale, child) {
                            return Transform.scale(
                              scale: scale,
                              child: Icon(
                                isInside ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                                color: Colors.white,
                                size: 48,
                              ),
                            );
                          },
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
                          isInside ? 'You are in the library' : 'You are outside',
                          style: GoogleFonts.poppins(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                        const Divider(color: Colors.white24, height: 32),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildStatusItem(Icons.access_time, 'Time', currentTime),
                            if (isInside)
                              _buildStatusItem(Icons.timer, 'Session', _formatDuration(_elapsed)),
                            _buildStatusItem(Icons.calendar_today, 'Date', _getFormattedDate()),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              if (isInside && _elapsed.inMinutes >= 30)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '☕ Time for a break!',
                      style: GoogleFonts.poppins(
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 16),

              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                    child: Text(
                      _matric.isNotEmpty ? _matric.substring(0, 2).toUpperCase() : '??',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.primary,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _matric.isEmpty
                              ? 'Not logged in'
                              : '${_getGreeting()}, ${_matric.substring(0, 4)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      if (_matric.isNotEmpty && isInside)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green.shade200),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fiber_manual_record,
                                  color: Colors.green.shade600, size: 10),
                              const SizedBox(width: 4),
                              Text(
                                'Active',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade800,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                  subtitle: Text(
                    _matric.isEmpty ? 'Tap login button to check in' : 'Matric ID • $_matric',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: _matric.isNotEmpty
                      ? IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () async {
                      final r = await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const CheckinScreen())
                      );
                      if (r == true) _loadMatric();
                    },
                  )
                      : null,
                ),
              ),

              if (_matric.isNotEmpty)
                FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('sessions')
                      .where('matric', isEqualTo: _matric)
                      .where('start', isGreaterThanOrEqualTo: Timestamp.fromDate(
                      DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day)))
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.hasData) {
                      int totalSeconds = 0;
                      for (var doc in snapshot.data!.docs) {
                        totalSeconds += ((doc['duration_seconds'] ?? 0) as int);
                      }

                      final totalHours = totalSeconds ~/ 3600;
                      final totalMinutes = (totalSeconds % 3600) ~/ 60;

                      if (totalSeconds > 0) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Card(
                            color: Colors.blue.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(Icons.today, color: Colors.blue.shade700),
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Today\'s Study Time',
                                        style: TextStyle(
                                          color: Colors.blue.shade900,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      Text(
                                        totalHours > 0
                                            ? '$totalHours hour${totalHours > 1 ? 's' : ''} $totalMinutes minutes'
                                            : '$totalMinutes minutes',
                                        style: TextStyle(
                                          color: Colors.blue.shade900,
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                    }
                    return const SizedBox.shrink();
                  },
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
                    label: 'Silent Mode Reminder',
                    color: Colors.purple,
                    onTap: () async {
                      final notif = NotificationService();
                      await notif.showSilentModeReminder();
                    },
                  ),
                  _buildActionButton(
                    context,
                    icon: Icons.coffee,
                    label: 'Break Reminder',
                    color: Colors.brown,
                    onTap: () async {
                      if (_elapsed.inMinutes >= 30) {
                        final notif = NotificationService();
                        await notif.showBreakReminder(_elapsed.inMinutes);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('You need to study at least 30 minutes before a break reminder'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
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
                    },
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

  Widget _buildActionButton(BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap
  }) {
    return StatefulBuilder(
      builder: (context, setState) {
        // ignore: unused_local_variable
        bool isPressed = false;

        return GestureDetector(
          onTapDown: (_) {
            setState(() {
              isPressed = true;
            });
            HapticFeedback.lightImpact();
          },
          onTapUp: (_) {
            setState(() {
              isPressed = false;
            });
          },
          onTapCancel: () {
            setState(() {
              isPressed = false;
            });
          },
          onTap: onTap,
          child: AnimatedScale(
            scale: isPressed ? 0.95 : 1.0,
            duration: const Duration(milliseconds: 100),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    color.withValues(alpha: isPressed ? 0.6 : 0.1),
                    color.withValues(alpha: isPressed ? 0.4 : 0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  if (!isPressed)
                    BoxShadow(
                      color: color.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                ],
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                  width: 1,
                ),
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
          ),
        );
      },
    );
  }
}