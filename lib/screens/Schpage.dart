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
  final String? reason;

  _ScheduledTask.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        title = json['title'],
        durationMin = json['durationMin'],
        start = DateFormat('HH:mm').parseUtc(json['start']).toLocal(),
        date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal(),
        priority = json['priority'],
        reason = json['reason']?.toString();

  Color get priorityColor {
    switch (priority) {
      case 'high':
        return const Color(0xFFFF6B6B);
      case 'medium':
        return const Color(0xFFFFA726);
      case 'low':
        return const Color(0xFF74EC7A);
      default:
        return const Color(0xFF74EC7A);
    }
  }

  Color get priorityLightColor {
    switch (priority) {
      case 'high':
        return const Color(0xFFFFEBEE);
      case 'medium':
        return const Color(0xFFFFF3E0);
      case 'low':
        return const Color(0xFFE8F5E8);
      default:
        return const Color(0xFFE8F5E8);
    }
  }
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

      /* 1. remove from schedule */
      final schedRef =
          FirebaseFirestore.instance.collection('schedules').doc(schedDocId);
      final currentList =
          (await schedRef.get()).data()!['orderedTasks'] as List<dynamic>;
      final updatedList = currentList.where((t) => t['id'] != task.id).toList()
        ..sort((a, b) => DateFormat('HH:mm')
            .parseUtc(a['start'])
            .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));
      await schedRef.update({'orderedTasks': updatedList});

      /* 2. AI insight */
      final insight = await _generateInsight(task, now);

      /* 3. store in doneTasks */
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

      /* 4. user behaviour */
      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
      final userSnap = await userRef.get();
      final behaviour =
          (userSnap.data()?['behaviour'] as Map<String, dynamic>?) ?? {};
      final key = '${task.priority}_completed';
      behaviour[key] = (behaviour[key] ?? 0) + 1;
      behaviour['lastCompletedAt'] = now;
      behaviour['lastInsight'] = insight;
      await userRef.set({'behaviour': behaviour}, SetOptions(merge: true));

      // Show success feedback
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade100),
                const SizedBox(width: 8),
                const Text('Task completed!'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
          ),
        );
      }
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
    bool? confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Task?'),
        content: Text('Are you sure you want to delete "${task.title}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

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
  Future<void> _showManualAddSheet(String schedDocId, DateTime forDay) async {
    final result = await Navigator.of(context).push<Map<String,dynamic>>(
      MaterialPageRoute(
        builder: (_) => ManualAddPage(day: forDay),
      ),
    );

    if (result == null) return;

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

  /* ---------------  TASK CARD - IMPROVED  --------------- */
  Widget _taskCard(_ScheduledTask task, String schedDocId) {
    final start = task.start;
    final end = start.add(Duration(minutes: task.durationMin));
    final slot = '${_12h(start)} – ${_12h(end)}';
    final reason = task.reason ?? 'Manually Scheduled';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            // Optional: Show task details
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Priority Indicator
                Container(
                  width: 4,
                  height: 60,
                  decoration: BoxDecoration(
                    color: task.priorityColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 16),
                
                // Task Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // Priority Badge
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: task.priorityLightColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              task.priority.toUpperCase(),
                              style: TextStyle(
                                color: task.priorityColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const Spacer(),
                          Text(
                            slot,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Duration: ${task.durationMin} min • $reason',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                
                // Action Buttons
                Column(
                  children: [
                    IconButton(
                      icon: Icon(Icons.check_circle_outline, 
                          color: Colors.green.shade600),
                      tooltip: 'Mark done',
                      onPressed: () => _markDone(task, schedDocId),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline, 
                          color: Colors.red.shade400),
                      tooltip: 'Delete',
                      onPressed: () => _deleteTask(task, schedDocId),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /* ---------------  EMPTY STATE  --------------- */
  Widget _buildEmptyState(DateTime day) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.schedule_outlined,
            size: 64,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            'No tasks scheduled',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add tasks to see your schedule here',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: bundle?.docId.isEmpty == false 
                ? () => _showManualAddSheet(bundle!.docId, day)
                : null,
            icon: const Icon(Icons.add),
            label: const Text('Add Task'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF74EC7A),
            ),
          ),
        ],
      ),
    );
  }

  _ScheduleBundle? bundle;

  /* ---------------  BUILD  --------------- */
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<_ScheduleBundle>(
      stream: _streamSchedule(),
      builder: (_, snap) {
        if (snap.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          );
        }

        if (!snap.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        bundle = snap.data!;
        final activeDay = _days[_tabController.index];

        return Scaffold(
          backgroundColor: Colors.grey[50],
          appBar: AppBar(
            title: const Text(
              'Your Schedule',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            backgroundColor: Colors.white,
            elevation: 0,
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: TabBar(
                  controller: _tabController,
                  isScrollable: true,
                  labelColor: const Color(0xFF74EC7A),
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: const Color(0xFF74EC7A),
                  indicatorWeight: 3,
                  tabs: [
                    for (final d in _days)
                      Tab(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            children: [
                              Text(
                                _tabLabel(d).split(' ')[0],
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                _tabLabel(d).contains(' ') 
                                    ? _tabLabel(d).split(' ')[1]
                                    : '',
                                style: const TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          floatingActionButton: bundle!.docId.isEmpty
              ? null
              : FloatingActionButton(
                  heroTag: 'manual',
                  tooltip: 'Add manual slot',
                  backgroundColor: const Color(0xFF74EC7A),
                  child: const Icon(Icons.add, color: Colors.white),
                  onPressed: () => _showManualAddSheet(bundle!.docId, activeDay),
                ),
          body: TabBarView(
            controller: _tabController,
            children: [
              for (final day in _days)
                _filterDay(bundle!.tasks, day).isEmpty
                    ? _buildEmptyState(day)
                    : Column(
                        children: [
                          // Header with day info
                          Container(
                            padding: const EdgeInsets.all(16),
                            color: Colors.white,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.calendar_today,
                                  color: const Color(0xFF74EC7A),
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  DateFormat('EEEE, MMMM d').format(day),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 16,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${_filterDay(bundle!.tasks, day).length} tasks',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // Task List
                          Expanded(
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 16),
                              children: [
                                for (final t in _filterDay(bundle!.tasks, day))
                                  _taskCard(t, bundle!.docId),
                              ],
                            ),
                          ),
                        ],
                      ),
            ],
          ),
        );
      },
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