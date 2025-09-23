import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/* ---------- model with date ---------- */
class _ScheduledTask {
  final String id, title;
  final int durationMin;
  final DateTime start; // time portion
  final DateTime date;  // calendar day
  final String priority;

  _ScheduledTask.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        title = json['title'],
        durationMin = json['durationMin'],
        start = DateFormat('HH:mm').parseUtc(json['start']).toLocal(),
        date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal(),
        priority = json['priority'];
}

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

  /* ---------- stream latest schedule ---------- */
  Stream<List<_ScheduledTask>> _streamSchedule() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? <_ScheduledTask>[]
            : (snap.docs.first.data()['orderedTasks'] as List<dynamic>)
                .map((t) => _ScheduledTask.fromJson(t))
                .toList()
              ..sort((a, b) => a.start.compareTo(b.start)));
  }
    String _12h(DateTime dt) => DateFormat('hh:mm a').format(dt);

  /* ---------- delete task + move to deletedTasks ---------- */
  Future<void> _deleteTask(_ScheduledTask task, String schedDocId) async {
    try {
      final schedRef =
          FirebaseFirestore.instance.collection('schedules').doc(schedDocId);
      final currentList =
          (await schedRef.get()).data()!['orderedTasks'] as List<dynamic>;

      final updatedList = currentList
          .where((t) => t['id'] != task.id)
          .toList()
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

  /* ---------- tab labels ---------- */
  String _tabLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
    return DateFormat('E d').format(day);
  }

  /* ---------- filter by calendar day ---------- */
  List<_ScheduledTask> _filterDay(List<_ScheduledTask> all, DateTime day) {
    final startOfDay = DateTime(day.year, day.month, day.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    return all
        .where((t) => t.date.isAfter(startOfDay) && t.date.isBefore(endOfDay))
        .toList();
  }

  /* ---------- single card with delete ---------- */
  Widget _taskCard(_ScheduledTask task, String schedDocId) {
    final start = task.start;
    final end = start.add(Duration(minutes: task.durationMin));
    final slot = '${_12h(start)} – ${_12h(end)}';


    final color = task.priority == 'high'
        ? Colors.redAccent
        : task.priority == 'medium'
            ? Colors.orangeAccent
            : Colors.green;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ListTile(
        leading: CircleAvatar(child: Text('${start.hour}')),
        title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(slot),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline, color: Colors.red),
          onPressed: () => _deleteTask(task, schedDocId),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Created Schedule'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: [for (final d in _days) Tab(text: _tabLabel(d))],
        ),
      ),
      body: StreamBuilder<List<_ScheduledTask>>(
        stream: _streamSchedule(),
        builder: (_, snap) {
          if (snap.hasError) return Center(child: Text('Error: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final allTasks = snap.data!;
          if (allTasks.isEmpty) {
            return const Center(child: Text('No schedule – generate one from Home'));
          }

          final schedDocId = snap.data!.isEmpty
    ? ''
    : (snap as AsyncSnapshot<List<_ScheduledTask>>)
        .data!
        .first
        .id; // <-- already available via first schedule doc

          return TabBarView(
            controller: _tabController,
            children: [
              for (final day in _days)
                _filterDay(allTasks, day).isEmpty
                    ? Center(child: Text('No tasks for ${_tabLabel(day)}'))
                    : ListView(
                        padding: const EdgeInsets.only(top: 8, bottom: 16),
                        children: [
                          for (final t in _filterDay(allTasks, day))
                            _taskCard(t, schedDocId),
                        ],
                      ),
            ],
          );
        },
      ),
    );
  }
}