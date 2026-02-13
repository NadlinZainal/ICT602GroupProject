import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class CheckinScreen extends StatefulWidget {
  const CheckinScreen({super.key});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _matricController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadMatric();
  }

  Future<void> _loadMatric() async {
    final prefs = await SharedPreferences.getInstance();
    final m = prefs.getString('matric') ?? '';
    _matricController.text = m;
  }

  // ✅ CHECK IF MATRIC IS VALID UiTM FORMAT
  bool _isValidUiTMMatric(String matric) {
    // UiTM matric formats:
    // 1. 10 digits: 2023123456 (year + 6 digits)
    // 2. Old format: 2010987654 (10 digits)
    // 3. With dash: 2023-123456 (optional)

    // Remove any dashes or spaces
    final cleanMatric = matric.replaceAll(RegExp(r'[\s-]'), '');

    // Check if it's exactly 10 digits and all numbers
    if (cleanMatric.length != 10) return false;
    if (!RegExp(r'^\d+$').hasMatch(cleanMatric)) return false;

    // Optional: Check if first 4 digits are valid year (2000-2030)
    final yearPrefix = int.tryParse(cleanMatric.substring(0, 4));
    if (yearPrefix != null) {
      if (yearPrefix < 2000 || yearPrefix > 2030) return false;
    }

    return true;
  }

  // ✅ CHECK MATRIC IN FIREBASE (optional - if you want to maintain student list)
  Future<bool> _isMatricInFirebase(String matric) async {
    try {
      final querySnapshot = await FirebaseFirestore.instance
          .collection('students')
          .where('matric', isEqualTo: matric)
          .limit(1)
          .get();

      return querySnapshot.docs.isNotEmpty;
    } catch (e) {
      debugPrint('Error checking matric: $e');
      // If Firebase check fails, still allow based on format only
      return true;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    final matric = _matricController.text.trim();

    // ✅ STEP 1: Check UiTM format
    bool isValidFormat = _isValidUiTMMatric(matric);

    if (!mounted) return;

    if (!isValidFormat) {
      setState(() {
        _isLoading = false;
      });

      // ❌ INVALID UiTM FORMAT
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Icon(Icons.error_outline, size: 50, color: Colors.red),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Invalid Matric Number',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Text(
                '"$matric" is not a valid UiTM matric number.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'UiTM matric numbers must be 10 digits.\nExample: 2023123456',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
      return;
    }

    // ✅ STEP 2: Optional - Check in Firebase (if you want to restrict to registered students)
    bool existsInFirebase = await _isMatricInFirebase(matric);

    if (!mounted) return;
    setState(() {
      _isLoading = false;
    });

    // Uncomment this block if you want to restrict to Firebase-registered students only
    /*
    if (!existsInFirebase) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Icon(Icons.error_outline, size: 50, color: Colors.red),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Not Registered',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.red),
              ),
              const SizedBox(height: 16),
              Text(
                'Matric number "$matric" is not registered in our system.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 8),
              const Text(
                'Please contact library staff for assistance.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Try Again'),
            ),
          ],
        ),
      );
      return;
    }
    */

    // ✅ VALID UiTM MATRIC - PROCEED
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('matric', matric);
    await prefs.setBool('just_logged_in', true);

    if (!mounted) return;

    // Show welcome popup
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
              matric,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            const SizedBox(height: 16),
            const Text('Happy studying at PTAR UiTM Jasin! 📚'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop(true);
            },
            child: const Text('Start Session'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Check-in'),
        backgroundColor: Colors.deepPurple,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 40),
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.school,
                    size: 80,
                    color: Colors.deepPurple.shade700,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'UiTM Student Check-in',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade900,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please enter your UiTM matric number',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey.shade600,
                  ),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _matricController,
                  decoration: InputDecoration(
                    labelText: 'Matric Number',
                    hintText: 'e.g., 2023123456',
                    prefixIcon: const Icon(Icons.badge, color: Colors.deepPurple),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.deepPurple.shade700, width: 2),
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    suffixIcon: _isLoading
                        ? const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.deepPurple),
                      ),
                    )
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                  enabled: !_isLoading,
                  validator: (v) {
                    final value = v?.trim() ?? '';
                    if (value.isEmpty) return 'Please enter your matric number';
                    if (value.length < 10) return 'Matric must be 10 digits';
                    if (!RegExp(r'^\d+$').hasMatch(value.replaceAll(RegExp(r'[\s-]'), ''))) {
                      return 'Only numbers allowed';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Format: 10 digits (e.g., 2023123456)',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: _isLoading ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Text(
                    'Login',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}