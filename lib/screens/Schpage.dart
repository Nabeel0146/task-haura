import 'package:taskhaura/screens/manualtask.dart';
import '../main.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:firebase_ai/firebase_ai.dart';

/* --------------------  MODEL  -------------------- */
class ScheduledTask {
  final String id, title;
  final int durationMin;
  final DateTime start;
  final DateTime date;
  final String priority;
  final String? reason;

  ScheduledTask.fromJson(Map<String, dynamic> json)
      : id = json['id'],
        title = json['title'],
        durationMin = json['durationMin'],
        start = _parseTimeString(json['start']),
        date = _parseDateString(json['date']),
        priority = json['priority'],
        reason = json['reason']?.toString();

  // Helper method to parse time string (already in local time)
  static DateTime _parseTimeString(String timeStr) {
    final parts = timeStr.split(':');
    final hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, hour, minute);
  }

  // Helper method to parse date string (already in local time)
  static DateTime _parseDateString(String dateStr) {
    final parts = dateStr.split('-');
    final year = int.parse(parts[0]);
    final month = int.parse(parts[1]);
    final day = int.parse(parts[2]);
    return DateTime(year, month, day);
  }

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

/* --------------------  TIMELINE PAGE  -------------------- */
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
  _days = List.generate(30, (i) => today.add(Duration(days: i)));
  _tabController = TabController(length: 30, vsync: this);
}

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /* ---------------  STREAM SCHEDULE  --------------- */
  Stream<ScheduleBundle> _streamSchedule() {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    return FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .map((snap) {
      if (snap.docs.isEmpty) return ScheduleBundle.empty();
      final doc = snap.docs.first;
      final list = (doc.data()['orderedTasks'] as List<dynamic>)
          .map((t) => ScheduledTask.fromJson(t))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));

      return ScheduleBundle(docId: doc.id, tasks: list);
    });
  }

  String _12h(DateTime dt) => DateFormat('hh:mm a').format(dt);

  /* ---------------  MARK TASK DONE  --------------- */
  Future<void> _markDone(ScheduledTask task, String schedDocId) async {
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
            .parse(a['start'])
            .compareTo(DateFormat('HH:mm').parse(b['start'])));
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
  Future<String> _generateInsight(
      ScheduledTask task, DateTime completedAt) async {
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
  Future<void> _deleteTask(ScheduledTask task, String schedDocId) async {
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
            .parse(a['start'])
            .compareTo(DateFormat('HH:mm').parse(b['start'])));
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
    final result = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => ManualAddPage(day: forDay),
      ),
    );

    if (result == null) return;

    final schedRef =
        FirebaseFirestore.instance.collection('schedules').doc(schedDocId);
    final currentList =
        (await schedRef.get()).data()!['orderedTasks'] as List<dynamic>;
    final updatedList = [...currentList, result]..sort((a, b) =>
        DateFormat('HH:mm')
            .parse(a['start'])
            .compareTo(DateFormat('HH:mm').parse(b['start'])));
    await schedRef.update({'orderedTasks': updatedList});
  }

  /* ---------------  TIMELINE HELPERS  --------------- */
  String _tabLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return 'Today';
    if (day == today.add(const Duration(days: 1))) return 'Tomorrow';
    return DateFormat('E d').format(day);
  }

  List<ScheduledTask> _filterDay(List<ScheduledTask> all, DateTime day) {
    final normalizedDay = DateTime(day.year, day.month, day.day);

    return all.where((task) {
      final taskDate = DateTime(task.date.year, task.date.month, task.date.day);
      return taskDate == normalizedDay;
    }).toList();
  }

  /* ---------------  TIMELINE GENERATION  --------------- */
  List<Widget> _buildTimeline(List<ScheduledTask> tasks) {
    final timeline = <Widget>[];

    // Create ALL hourly slots from 6:00 AM to 11:00 PM (18 hours)
    final hourSlots = List.generate(18, (index) => index + 6); // 6 AM to 11 PM

    for (final hour in hourSlots) {
      // Get tasks that start in this hour
      final hourTasks = tasks.where((task) => task.start.hour == hour).toList();

      timeline.add(
        _buildHourSlot(hour, hourTasks),
      );
    }

    return timeline;
  }

  Widget _buildHourSlot(int hour, List<ScheduledTask> tasks) {
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    final nextHour = hour + 1;
    final nextPeriod = nextHour < 12 ? 'AM' : 'PM';
    final nextDisplayHour =
        nextHour == 0 ? 12 : (nextHour > 12 ? nextHour - 12 : nextHour);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time label - ALWAYS VISIBLE
          Container(
            width: 70,
            padding: const EdgeInsets.only(top: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$displayHour:00',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                    fontSize: 13,
                  ),
                ),
                Text(
                  period,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'to',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 10,
                  ),
                ),
                Text(
                  '$nextDisplayHour:00',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                    fontSize: 12,
                  ),
                ),
                Text(
                  nextPeriod,
                  style: const TextStyle(
                    color: Colors.grey,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          // Vertical separator line
          Container(
            width: 2,
            height: tasks.isEmpty ? 60 : null, // Minimum height for empty slots
            margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF74EC7A),
              borderRadius: BorderRadius.circular(1),
            ),
          ),

          const SizedBox(width: 8),

          // Task content area
          Expanded(
            child: tasks.isEmpty
                ? _buildEmptySlot(hour)
                : tasks.length == 1
                    ? _buildSingleTask(tasks.first)
                    : _buildMultipleTasks(tasks),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptySlot(int hour) {
    return Container(
      height: 60, // Consistent height for empty slots
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(right: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey.shade50,
      ),
      child: Center(
        child: Text(
          'No tasks scheduled',
          style: TextStyle(
            color: Colors.grey.shade500,
            fontStyle: FontStyle.italic,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSingleTask(ScheduledTask task) {
    final start = task.start;
    final end = start.add(Duration(minutes: task.durationMin));
    final startTime = DateFormat('hh:mm a').format(start);
    final endTime = DateFormat('hh:mm a').format(end);

    return Container(
      margin: const EdgeInsets.only(right: 8, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: task.priorityColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
        color: task.priorityLightColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Priority badge and time
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: task.priorityColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  task.priority.toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '$startTime - $endTime',
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Task title
          Text(
            task.title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (task.reason != null) ...[
            const SizedBox(height: 4),
            Text(
              task.reason!,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.grey,
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Duration: ${task.durationMin} minutes',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.grey,
            ),
          ),
          // Action Buttons
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(Icons.check_circle_outline,
                    color: Colors.green.shade600, size: 20),
                tooltip: 'Mark done',
                onPressed: () => _markDone(task, bundle!.docId),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Colors.red.shade400, size: 20),
                tooltip: 'Delete',
                onPressed: () => _deleteTask(task, bundle!.docId),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMultipleTasks(List<ScheduledTask> tasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, right: 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF74EC7A),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${tasks.length} TASKS',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Multiple tasks scheduled',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        ...tasks.map((task) => _buildTaskCard(task)).toList(),
      ],
    );
  }

  Widget _buildTaskCard(ScheduledTask task) {
    final start = task.start;
    final end = start.add(Duration(minutes: task.durationMin));
    final startTime = DateFormat('hh:mm a').format(start);
    final endTime = DateFormat('hh:mm a').format(end);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6, right: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: task.priorityColor.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Priority indicator
          Container(
            width: 4,
            height: 40,
            decoration: BoxDecoration(
              color: task.priorityColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          // Task details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: task.priorityLightColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        task.priority.toUpperCase(),
                        style: TextStyle(
                          color: task.priorityColor,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '$startTime - $endTime',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  task.title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${task.durationMin} min • ${task.reason ?? "Scheduled"}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          // Action buttons for multiple tasks
          Column(
            children: [
              IconButton(
                icon: Icon(Icons.check_circle_outline,
                    color: Colors.green.shade600, size: 18),
                tooltip: 'Mark done',
                onPressed: () => _markDone(task, bundle!.docId),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline,
                    color: Colors.red.shade400, size: 18),
                tooltip: 'Delete',
                onPressed: () => _deleteTask(task, bundle!.docId),
              ),
            ],
          ),
        ],
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

  ScheduleBundle? bundle;
/* ---------------  BUILD  --------------- */
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ScheduleBundle>(
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
          // Add extendBodyBehindAppBar like in home page
          extendBodyBehindAppBar: false,
          appBar: AppBar(
            backgroundColor:
                const Color(0xFF74EC7A), // Solid green like home page
            elevation: 0,
            title: const Text(
              'Your Schedule',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white, // White text like home page
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(60),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.transparent,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (int i = 0; i < _days.length; i++)
                              GestureDetector(
                                onTap: () {
                                  _tabController.animateTo(i);
                                },
                                child: Container(
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _tabController.index == i
                                        ? const Color(0xFF74EC7A)
                                        : Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _tabLabel(_days[i]).split(' ')[0],
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: _tabController.index == i
                                              ? Colors.white
                                              : Colors.grey,
                                        ),
                                      ),
                                      Text(
                                        _tabLabel(_days[i]).contains(' ')
                                            ? _tabLabel(_days[i]).split(' ')[1]
                                            : '',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w500,
                                          color: _tabController.index == i
                                              ? Colors.white
                                              : Colors.black87,
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
                  onPressed: () =>
                      _showManualAddSheet(bundle!.docId, activeDay),
                ),
          body: Stack(
            children: [
              // Add gradient background like home page
              Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.center,
                    colors: [Color.fromARGB(255, 131, 245, 103), Colors.white],
                  ),
                ),
              ),
              TabBarView(
                controller: _tabController,
                children: [
                  for (final day in _days)
                    _filterDay(bundle!.tasks, day).isEmpty
                        ? _buildEmptyState(day)
                        : Column(
                            children: [
                              const SizedBox(height: 8), // Add some top padding
                              // Day header
                              // Day header with rounded container
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 8,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
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
                              ),
                              const SizedBox(height: 8),
                              // Timeline
                              Expanded(
                                child: ListView(
                                  padding: const EdgeInsets.only(bottom: 20),
                                  children: _buildTimeline(
                                      _filterDay(bundle!.tasks, day)),
                                ),
                              ),
                            ],
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
class ScheduleBundle {
  final String docId;
  final List<ScheduledTask> tasks;
  ScheduleBundle({required this.docId, required this.tasks});
  factory ScheduleBundle.empty() =>
      ScheduleBundle(docId: '', tasks: <ScheduledTask>[]);
}
