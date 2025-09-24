import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Page that lets the user add a single manual time-block.
/// Only time gaps that are **really free** for the selected duration are shown.
class ManualAddPage extends StatefulWidget {
  final DateTime day;
  const ManualAddPage({super.key, required this.day});

  @override
  State<ManualAddPage> createState() => _ManualAddPageState();
}

class _ManualAddPageState extends State<ManualAddPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '30');
  String _priority = 'medium';
  String? _selectedTime; // HH:mm
  

  /// Reads the current schedule document for [day] and returns
  /// already booked time segments (start, end).
  Future<List<_BookedSlot>> _loadBookedSlots() async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final snap = await FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: DateFormat('yyyy-MM-dd').format(widget.day))
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) return [];
    final List<dynamic> tasks = snap.docs.first.data()['orderedTasks'] ?? [];

    return tasks.map((json) {
      final date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal();
      final start = DateFormat('HH:mm').parseUtc(json['start']).toLocal();
      final realStart = DateTime(date.year, date.month, date.day,
          start.hour, start.minute);
      final dur = (json['durationMin'] as int?) ?? 30;
      return _BookedSlot(
        start: realStart,
        end: realStart.add(Duration(minutes: dur + 15)), // include break
      );
    }).toList();
  }

  /// Builds the list of HH:mm strings that are **free** for the current duration.
  /// Builds the list of 12-hour AM/PM strings that are **free**
/// for the current duration (08:00 today → 06:00 tomorrow).
Future<List<String>> _freeSlots() async {
  final booked = await _loadBookedSlots();
  const step = 15; // minutes
  final dur = int.tryParse(_durationCtrl.text) ?? 30;

  final free = <String>[];
  final start = DateTime(widget.day.year, widget.day.month, widget.day.day, 8);
  final end = start.add(const Duration(hours: 22)); // 08 + 22 h = 06:00 next day

  DateTime slot = start;
  while (slot.isBefore(end)) {
    final slotEnd = slot.add(Duration(minutes: dur));

    bool overlaps = booked.any((b) =>
        slot.isBefore(b.end) && slotEnd.isAfter(b.start));
    if (!overlaps) {
      free.add(DateFormat('hh:mm a').format(slot)); // 12-hour AM/PM
    }
    slot = slot.add(const Duration(minutes: step));
  }
  return free;
}

  /// Returns the Map that will be written into Firestore.
  Map<String, dynamic> _buildSlotMap() {
  // _selectedTime is now "07:30 PM" etc.  ➜ parse in 12-hour mode
  final startTime = DateFormat('hh:mm a').parseUtc(_selectedTime!).toLocal();
  final realStart = DateTime(widget.day.year, widget.day.month,
      widget.day.day, startTime.hour, startTime.minute);

  return {
    'id': FirebaseFirestore.instance.collection('tasks').doc().id,
    'title': _titleCtrl.text.trim(),
    'durationMin': int.parse(_durationCtrl.text.trim()),
    'start': DateFormat('HH:mm').format(realStart), // 24-hour for DB
    'date': DateFormat('yyyy-MM-dd').format(widget.day),
    'priority': _priority,
  };
}

  void _submit() {
    if (_formKey.currentState!.validate() && _selectedTime != null) {
      Navigator.of(context).pop(_buildSlotMap());
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add manual block')),
      body: FutureBuilder<List<String>>(
        future: _freeSlots(), // reloaded every time the user changes duration
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final slots = snap.data ?? [];
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _titleCtrl,
                    decoration: const InputDecoration(labelText: 'Title'),
                    validator: (v) =>
                        v == null || v.trim().isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _durationCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Duration (minutes)', suffixText: 'min'),
                    keyboardType: TextInputType.number,
                    validator: (v) =>
                        v == null || int.tryParse(v) == null ? 'Number' : null,
                    onChanged: (_) => setState(() {}), // rebuild free slots
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _priority,
                    items: ['low', 'medium', 'high']
                        .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) => setState(() => _priority = v!),
                    decoration: const InputDecoration(labelText: 'Priority'),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: _selectedTime,
                    items: slots
                        .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                        .toList(),
                    onChanged: (v) => setState(() => _selectedTime = v),
                    decoration:
                        const InputDecoration(labelText: 'Start time (free)'),
                    validator: (v) => v == null ? 'Pick a time' : null,
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    icon: const Icon(Icons.save),
                    label: const Text('CREATE'),
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Simple helper class to represent an already booked segment.
class _BookedSlot {
  final DateTime start;
  final DateTime end;
  _BookedSlot({required this.start, required this.end});
}