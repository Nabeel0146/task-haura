import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:taskhaura/screens/mainscreen.dart';

class OnboardingPage extends StatefulWidget {
  final String uid;
  const OnboardingPage({super.key, required this.uid});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _formKey = GlobalKey<FormState>();

  TimeOfDay? _startTime;
  TimeOfDay? _endTime;
  final _focusTypeCtrl = TextEditingController();

  bool _isLoading = false;

  /* ---------- helpers ---------- */
  String _format(TimeOfDay? t) => t == null ? '--:--' : t.format(context);

  Future<void> _pickTime(bool pickStart) async {
    final initial = pickStart
        ? (_startTime ?? const TimeOfDay(hour: 9, minute: 0))
        : (_endTime ?? const TimeOfDay(hour: 17, minute: 0));
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked != null) {
      setState(() {
        if (pickStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
    }
  }

  String? _timeValidator(_) =>
      _startTime == null || _endTime == null
          ? 'Please select both start and end times'
          : null;

  /* ---------- SKIP  ---------- */
  void _skip() => Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );

  /* ---------- SAVE  ---------- */
  Future<void> _saveOnboarding() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final workingHours = '${_format(_startTime)} – ${_format(_endTime)}';

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .update({
        'workingHours': workingHours,
        'focusType': _focusTypeCtrl.text.trim(),
      });

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /* ---------- UI ---------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Almost there!',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Help us understand your work style.',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 32),

                /* working hours */
                const Text('Working hours',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.deepPurple)),
                        title: Text(_format(_startTime)),
                        trailing: const Icon(Icons.access_time, color: Colors.deepPurple),
                        onTap: () => _pickTime(true),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('to', style: TextStyle(fontSize: 16)),
                    ),
                    Expanded(
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: const BorderSide(color: Colors.deepPurple)),
                        title: Text(_format(_endTime)),
                        trailing: const Icon(Icons.access_time, color: Colors.deepPurple),
                        onTap: () => _pickTime(false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FormField(
                  validator: _timeValidator,
                  builder: (_) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 20),

                /* focus type */
                DropdownButtonFormField<String>(
                  value: null,
                  hint: const Text('Select focus type'),
                  items: const [
                    DropdownMenuItem(
                        value: 'Can work long hours straight',
                        child: Text('Can work long hours straight')),
                    DropdownMenuItem(
                        value: 'Less focused, need frequent breaks',
                        child: Text('Less focused, need frequent breaks')),
                    DropdownMenuItem(
                        value: 'Mixed / varies by day',
                        child: Text('Mixed / varies by day')),
                  ],
                  onChanged: (v) => _focusTypeCtrl.text = v ?? '',
                  validator: (_) =>
                      _focusTypeCtrl.text.isEmpty ? 'Please select focus type' : null,
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 32),

                /* continue button */
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurple,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPressed: _isLoading ? null : _saveOnboarding,
                    child: _isLoading
                        ? const CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 3)
                        : const Text(
                            'Continue',
                            style: TextStyle(fontSize: 16, color: Colors.white),
                          ),
                  ),
                ),
                const SizedBox(height: 12),

                /* skip for now */
                Center(
                  child: TextButton(
                    onPressed: _skip,
                    child: const Text(
                      'Skip for now',
                      style: TextStyle(color: Colors.deepPurple),
                    ),
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