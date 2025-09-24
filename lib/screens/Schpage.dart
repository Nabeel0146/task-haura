import 'package:taskhaura/screens/manualtask.dart';

import '../main.dart'; // gemini + db
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_ai/firebase_ai.dart';

/* --------------------  MODEL  -------------------- */
class _ScheduledTask {
  final String id, title;
  final int durationMin;
  final DateTime start;
  final DateTime date;
  final String priority;
  final String? reason; // ← NEW

  _ScheduledTask.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        title = json['title'],
        durationMin = json['durationMin'],
        start = DateFormat('HH:mm').parseUtc(json['start']).toLocal(),
        date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal(),
        priority = json['priority'],
        reason = json['reason']?.toString(); // ← NEW
}


/* --------------------  PAGE  -------------------- */
class SchedulePage extends StatefulWidget {
  const SchedulePage({super.key});

  @override
  State<SchedulePage> createState() => _SchedulePageState();
}

class _SchedulePageState extends State<SchedulePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final List<DateTime> _days;
  

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _days = List.generate(5, (i) => today.add(Duration(days: i)));
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /* ---------------  STREAM SCHEDULE  --------------- */
  Stream<_ScheduleBundle> _streamSchedule() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return _ScheduleBundle.empty();
      final doc = snap.docs.first;
      final list = (doc.data()['orderedTasks'] as List<dynamic>)
          .map((t) => _ScheduledTask.fromJson(t))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      return _ScheduleBundle(docId: doc.id, tasks: list);
    });
  }

  String _12h(DateTime dt) => DateFormat('hh:mm a').format(dt);

  /* ---------------  MARK TASK DONE  --------------- */
  Future<void> _markDone(_ScheduledTask task, String schedDocId) async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final now = DateTime.now();

      /* 1.  remove from schedule */
      final schedRef =
          FirebaseFirestore.instance.collection('schedules').doc(schedDocId);
      final currentList =
          (await schedRef.get()).data()!['orderedTasks'] as List<dynamic>;
      final updatedList = currentList.where((t) => t['id'] != task.id).toList()
        ..sort((a, b) => DateFormat('HH:mm')
            .parseUtc(a['start'])
            .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));
      await schedRef.update({'orderedTasks': updatedList});

      /* 2.  AI insight */
      final insight = await _generateInsight(task, now);

      /* 3.  store in doneTasks */
      await FirebaseFirestore.instance.collection('doneTasks').add({
        'id': task.id,
        'title': task.title,
        'durationMin': task.durationMin,
        'start': DateFormat('HH:mm').format(task.start),
        'date': DateFormat('yyyy-MM-dd').format(task.date),
        'priority': task.priority,
        'completedAt': now,
        'uid': uid,
        'aiInsight': insight,
      });

      /* 4.  user behaviour */
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final userSnap = await userRef.get();
      final behaviour =
          (userSnap.data()?['behaviour'] as Map<String, dynamic>?) ?? {};
      final key = '${task.priority}_completed';
      behaviour[key] = (behaviour[key] ?? 0) + 1;
      behaviour['lastCompletedAt'] = now;
      behaviour['lastInsight'] = insight;
      await userRef.set({'behaviour': behaviour}, SetOptions(merge: true));
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Mark done failed: $e')));
    }
  }

  /* ---------------  AI INSIGHT  --------------- */
  Future<String> _generateInsight(_ScheduledTask task, DateTime completedAt) async {
    final prompt = '''
You are a productivity coach.
Analyse the completed task and write ONE short sentence (max 15 words) about the user's behaviour.
Task: "${task.title}" | Priority: ${task.priority} | Scheduled: ${DateFormat('HH:mm').format(task.start)} | Duration: ${task.durationMin} min.
''';
    try {
      final resp = await gemini.generateContent([Content.text(prompt)]);
      return resp.text?.trim().replaceAll('\n', ' ') ?? 'No insight';
    } catch (_) {
      return 'Completed on time';
    }
  }

  /* ---------------  DELETE TASK  --------------- */
  Future<void> _deleteTask(_ScheduledTask task, String schedDocId) async {
    try {
      final schedRef =
          FirebaseFirestore.instance.collection('schedules').doc(schedDocId);
      final currentList =
          (await schedRef.get()).data()!['orderedTasks'] as List<dynamic>;
      final updatedList = currentList.where((t) => t['id'] != task.id).toList()
        ..sort((a, b) => DateFormat('HH:mm')
            .parseUtc(a['start'])
            .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));
      await schedRef.update({'orderedTasks': updatedList});

      await FirebaseFirestore.instance.collection('deletedTasks').add({
        'id': task.id,
        'title': task.title,
        'durationMin': task.durationMin,
        'start': DateFormat('HH:mm').format(task.start),
        'date': DateFormat('yyyy-MM-dd').format(task.date),
        'priority': task.priority,
        'deletedAt': FieldValue.serverTimestamp(),
        'uid': FirebaseAuth.instance.currentUser!.uid,
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  /* ---------------  MANUAL ADD  --------------- */
  /* ---------------  MANUAL ADD  --------------- */
Future<void> _showManualAddSheet(String schedDocId, DateTime forDay) async {
  final result = await Navigator.of(context).push<Map<String,dynamic>>(
    MaterialPageRoute(
      builder: (_) => ManualAddPage(day: forDay),
    ),
  );

  // user pressed BACK ➜ nothing to do
  if (result == null) return;

  // append the new slot to the existing schedule document
  final schedRef =
      FirebaseFirestore.instance.collection('schedules').doc(schedDocId);
  final currentList =
      (await schedRef.get()).data()!['orderedTasks'] as List<dynamic>;
  final updatedList = [...currentList, result]
    ..sort((a, b) => DateFormat('HH:mm')
        .parseUtc(a['start'])
        .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));
  await schedRef.update({'orderedTasks': updatedList});
}

  /* ---------------  FETCH BLOCKED SLOTS  --------------- */
  Future<List<_BlockedSlot>> _blockedSlots({
    required String uid,
    required DateTime day,
  }) async {
    final snap = await FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: DateFormat('yyyy-MM-dd').format(day))
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return [];
    return (snap.docs.first.data()['orderedTasks'] as List<dynamic>)
        .map((json) {
      final date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal();
      final start = DateFormat('HH:mm').parseUtc(json['start']).toLocal();
      final realStart =
          DateTime(date.year, date.month, date.day, start.hour, start.minute);
      final dur = json['durationMin'] as int;
      return _BlockedSlot(
        start: realStart,
        end: realStart.add(Duration(minutes: dur + 15)), // incl. break
      );
    }).toList();
  }

  /* ---------------  UI HELPERS  --------------- */
  String _tabLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
    return DateFormat('E d').format(day);
  }

  List<_ScheduledTask> _filterDay(List<_ScheduledTask> all, DateTime day) {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return all
        .where((t) => t.date.isAfter(startOfDay) && t.date.isBefore(endOfDay))
        .toList();
  }

  /* ---------------  TASK CARD  --------------- */
  Widget _taskCard(_ScheduledTask task, String schedDocId) {
    final start = task.start;
    final end = start.add(Duration(minutes: task.durationMin));
    final slot = '${_12h(start)} – ${_12h(end)}';
    /* ---------------  REASON ROW  --------------- */
final reason = task.reason ?? 'Manually Scheduled';

    final color = task.priority == 'high'
        ? Colors.redAccent
        : task.priority == 'medium'
            ? Colors.orangeAccent
            : Colors.green;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(child: Text('${start.hour}')),
        title: Text(task.title,
            style: const TextStyle(fontWeight: FontWeight.bold)),
       subtitle: Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  mainAxisSize: MainAxisSize.min,
  children: [
    Text(slot),
    Text('Reason: $reason', style: const TextStyle(fontSize: 12, color: Colors.grey)),
  ],
),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.check_circle_outline, color: Colors.green),
              tooltip: 'Mark done',
              onPressed: () => _markDone(task, schedDocId),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              tooltip: 'Delete',
              onPressed: () => _deleteTask(task, schedDocId),
            ),
          ],
        ),
      ),
    );
  }

  /* ---------------  BUILD  --------------- */
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_ScheduleBundle>(
      stream: _streamSchedule(),
      builder: (_, snap) {
        if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final bundle = snap.data!;
        final activeDay = _days[_tabController.index];

        return Scaffold(
          appBar: AppBar(
            title: const Text('AI Created Schedule'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabs: [for (final d in _days) Tab(text: _tabLabel(d))],
            ),
          ),
          floatingActionButton: FloatingActionButton(
            heroTag: 'manual',
            tooltip: 'Add manual slot',
            child: const Icon(Icons.add),
            onPressed: bundle.docId.isEmpty
                ? null
                : () => _showManualAddSheet(bundle.docId, activeDay),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              for (final day in _days)
                _filterDay(bundle.tasks, day).isEmpty
                    ? Center(child: Text('No tasks for ${_tabLabel(day)}'))
                    : ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        children: [
                          for (final t in _filterDay(bundle.tasks, day))
                            _taskCard(t, bundle.docId),
                        ],
                      ),
            ],
          ),
        );
      },
    );
  }
}

/* ---------------  MANUAL SLOT BOTTOM SHEET  --------------- */
class _ManualSlotSheet extends StatefulWidget {
  final DateTime forDay;
  final List<_BlockedSlot> blockedSlots;
  const _ManualSlotSheet({required this.forDay, required this.blockedSlots});

  @override
  State<_ManualSlotSheet> createState() => _ManualSlotSheetState();
}

class _ManualSlotSheetState extends State<_ManualSlotSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _durationCtrl = TextEditingController(text: '30');
  String _priority = 'medium';
  String? _selectedTime; // HH:mm

  /* ---------------  GENERATE FREE SLOTS  --------------- */
  List<String> _freeSlots() {
    final List<String> free = [];
    const startHour = 8;
    const endHour = 18;
    const step = 15; // minutes

    for (int h = startHour; h < endHour; h++) {
      for (int m = 0; m < 60; m += step) {
        final slot = DateTime(widget.forDay.year, widget.forDay.month,
            widget.forDay.day, h, m);
        final slotEnd = slot.add(const Duration(minutes: 30)); // default 30 min
        bool overlap = widget.blockedSlots.any((b) =>
            slot.isBefore(b.end) && slotEnd.isAfter(b.start));
        if (!overlap) free.add(DateFormat('HH:mm').format(slot));
      }
    }
    return free;
  }

  /* ---------------  SAVE  --------------- */
  void _submit() {
    if (_formKey.currentState!.validate() && _selectedTime != null) {
      Navigator.of(context).pop({
        'title': _titleCtrl.text.trim(),
        'duration': int.parse(_durationCtrl.text.trim()),
        'priority': _priority,
        'start': _selectedTime!,
      });
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
    final freeSlots = _freeSlots();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 24,
        right: 24,
        top: 24,
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add manual time block',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationCtrl,
                decoration: const InputDecoration(
                    labelText: 'Duration (minutes)', suffixText: 'min'),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    v == null || int.tryParse(v) == null ? 'Number' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _priority,
                items: ['low', 'medium', 'high']
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _priority = v!),
                decoration: const InputDecoration(labelText: 'Priority'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedTime,
                items: freeSlots
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedTime = v),
                decoration: const InputDecoration(
                    labelText: 'Start time (free slots)'),
                validator: (v) => v == null ? 'Pick a time' : null,
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.save),
                label: const Text('CREATE'),
                onPressed: _submit,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------------  HELPER  --------------- */
class _ScheduleBundle {
  final String docId;
  final List<_ScheduledTask> tasks;
  _ScheduleBundle({required this.docId, required this.tasks});
  factory _ScheduleBundle.empty() =>
      _ScheduleBundle(docId: '', tasks: <_ScheduledTask>[]);
}

class _BlockedSlot {
  final DateTime start;
  final DateTime end;
  _BlockedSlot({required this.start, required this.end});
}