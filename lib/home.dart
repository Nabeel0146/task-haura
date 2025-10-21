import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';
import 'package:taskhaura/screens/addtask.dart';
import 'package:taskhaura/screens/Schpage.dart' show SchedulePage;
import 'package:taskhaura/AUTH/register.dart';
import 'package:taskhaura/ai/ai_chatscreen.dart';
import 'package:taskhaura/services/aischeduler.dart';
import 'package:taskhaura/widgets/task_card.dart';

/* =========================================================================
   MAIN  (unchanged)
   ========================================================================= */
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const App());
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Haura',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
          useMaterial3: true, colorSchemeSeed: const Color(0xFF74EC7A)),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Scaffold(
                body: Center(child: CircularProgressIndicator()));
          }
          if (snap.hasData) return const HomePage();
          return const AuthGate();
        },
      ),
    );
  }
}

final db = FirebaseFirestore.instance;

/* =========================================================================
   AUTH GATE  (unchanged)
   ========================================================================= */
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<void> _anonLogin() async => FirebaseAuth.instance.signInAnonymously();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.login),
          label: const Text('Sign in anonymously'),
          onPressed: _anonLogin,
        ),
      ),
    );
  }
}
/* =========================================================================
   HOME PAGE  –  TAG + STATUS FILTER + TRANSPARENT FLOATING BUTTONS
   ========================================================================= */
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _db = FirebaseFirestore.instance.collection('tasks');
  final _user = FirebaseAuth.instance.currentUser!;

  /* ------------ FILTER STATE ------------ */
  List<String> _userTags = [];
  String _selectedTag = 'All';

  final List<TaskStatus> _statuses = TaskStatus.values;
  TaskStatus _selectedStatus = TaskStatus.toStart;

  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  Future<void> _loadTags() async {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_user.uid)
        .get();
    final List<dynamic> tags = snap.data()?['tags'] ?? [];
    if (mounted) setState(() => _userTags = tags.cast<String>());
  }


 /* ------------ HANDLE TASK CHECK ------------ */
Future<void> _handleTaskCheck(Task task, String docId) async {
  TaskStatus newStatus;
  
  switch (task.status) {
    case TaskStatus.toStart:
      newStatus = TaskStatus.onDoing;
      break;
    case TaskStatus.onDoing:
      newStatus = TaskStatus.done;
      break;
    case TaskStatus.done:
      newStatus = TaskStatus.done; // Stay done if already done
      break;
    case TaskStatus.skipped:
      newStatus = TaskStatus.skipped; // Stay skipped if already skipped
      break;
  }
  
  await _db.doc(docId).update({'status': newStatus.name});
}

  /* ------------ TAG FILTER CHIPS ------------ */
  Widget _buildTagFilter() {
    if (_userTags.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _filterChip('All', _selectedTag == 'All',
              () => setState(() => _selectedTag = 'All')),
          const SizedBox(width: 8),
          ..._userTags.map(
            (t) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _filterChip(
                  t, _selectedTag == t, () => setState(() => _selectedTag = t)),
            ),
          ),
        ],
      ),
    );
  }

  /* ------------ STATUS FILTER – icon + text ------------ */
  Widget _buildStatusFilter() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 5, 12, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: TaskStatus.values.map((s) {
          final bool selected = _selectedStatus == s;
          final Color iconColor = selected
              ? const Color.fromARGB(255, 51, 103, 47)
              : Colors.grey[600]!;
          return GestureDetector(
            onTap: () => setState(() => _selectedStatus = s),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_statusIcon(s), color: iconColor, size: 26),
                const SizedBox(height: 2),
                Text(_statusName(s),
                    style: TextStyle(fontSize: 11, color: iconColor)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  IconData _statusIcon(TaskStatus s) {
    switch (s) {
      case TaskStatus.toStart:
        return Icons.play_arrow;
      case TaskStatus.onDoing:
        return Icons.autorenew;
      case TaskStatus.done:
        return Icons.check_circle;
      case TaskStatus.skipped:
        return Icons.skip_next;
    }
  }

  String _statusName(TaskStatus s) => s.name
      .replaceAll('toStart', 'to start')
      .replaceAll('onDoing', 'on doing');

  /* ------------ GENERIC FILTER CHIP ------------ */
  Widget _filterChip(String label, bool selected, VoidCallback onTap) {
    return Material(
      elevation: selected ? 2 : 0,
      color: selected
          ? const Color.fromARGB(255, 51, 103, 47).withOpacity(.35)
          : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: selected
                      ? const Color.fromARGB(255, 240, 240, 240)
                      : Colors.black87,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );
  }

  /* ------------ AI ASSISTANT (bottom-sheet) ------------ */
  Future<void> _openAiAssistant() async {
    final snap = await _db.where('uid', isEqualTo: _user.uid).get();
    final tasks = snap.docs.map(Task.fromDoc).toList();
    if (!mounted) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AiChatSheet(userTasks: tasks),
    );
  }

  /* ------------ CRUD ------------ */
  Future<void> _addTask(Task task) async {
    try {
      await _db.add(task.toJson());
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to add task: $e')));
    }
  }

  Future<void> _updateTask(String id, Task task) async =>
      _db.doc(id).update(task.toJson());

  Future<void> _deleteTask(String id) async {
    try {
      final doc = await _db.doc(id).get();
      if (!doc.exists) return;
      final data = doc.data()!..['deletedAt'] = FieldValue.serverTimestamp();
      await db.collection('deletedTasks').add(data);
      await _db.doc(id).delete();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Delete failed: $e')));
    }
  }

  Future<void> _showEditSheet(Task task, String id) async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TaskBottomSheet(uid: _user.uid, existingTask: task),
    );
    if (result != null) await _updateTask(id, result);
  }

  Future<void> _confirmLogout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Logout?'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
              onPressed: Navigator.of(context).pop,
              child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('LOGOUT'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterPage()),
      (_) => false,
    );
  }

  /* ------------ BUILD ------------ */
  /* ------------ BUILD ------------ */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      /* 1.  let the body start *after* the app-bar */
      extendBodyBehindAppBar: false, //  <—  changed
      /* 2.  give the bar a solid colour so it covers the gradient */
      appBar: AppBar(
        backgroundColor: const Color(0xFF74EC7A), //  <—  solid colour
        elevation: 0,
        title: Row(
          children: [
            Image.asset('assets/taskhauralogo.png', width: 36, height: 36),
            const SizedBox(width: 12),
            const Text(
              'Task Haura',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu, color: Colors.white),
            onPressed: () => Scaffold.of(context).openEndDrawer(),
          ),
        ],
      ),
      endDrawer: Drawer(/* … unchanged … */),
      body: Stack(
        children: [
          /* gradient background */
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color.fromARGB(255, 131, 245, 103), Colors.white],
              ),
            ),
          ),

          /* content + transparent FABs */
          Column(
            children: [
              const SizedBox(height: 8), //  tiny top padding (optional)
              _buildTagFilter(), //  now drawn *below* the AppBar
              const SizedBox(height: 10),
              _buildStatusFilter(),
              Expanded(child: _buildTaskList()),
            ],
          ),

          /* transparent floating buttons */
          /* transparent floating buttons */
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // FloatingActionButton(
                //   heroTag: 'add',
                //   onPressed: () async {
                //     final newTask = await Navigator.of(context).push<Task>(
                //       MaterialPageRoute(
                //         builder: (_) => AddTaskPage(uid: _user.uid),
                //       ),
                //     );
                //     if (newTask != null) await _addTask(newTask);
                //   },
                //   tooltip: 'Add task',
                //   child: const Icon(Icons.add),
                // ),
                const SizedBox(height: 12),
                FloatingActionButton(
                  heroTag: 'ai',
                  onPressed: _openAiAssistant,
                  tooltip: 'AI Assistant',
                  child: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

/* ------------ BUILD TASK LIST WITH CHECKBOXES AND AUTO-SKIP ------------ */
Widget _buildTaskList() {
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _db
        .where('uid', isEqualTo: _user.uid)
        .orderBy('deadline')
        .snapshots(),
    builder: (_, snap) {
      if (snap.hasError) return Center(child: Text('${snap.error}'));
      if (!snap.hasData)
        return const Center(child: CircularProgressIndicator());

      final docs = snap.data!.docs;
      final now = DateTime.now();

      // Check and update tasks with passed due dates
      for (final doc in docs) {
        final task = Task.fromDoc(doc);
        final taskDeadline = task.deadline;
        
        // Only update if deadline has passed AND task is not already done/skipped
        if (taskDeadline!.isBefore(DateTime(now.year, now.month, now.day)) &&
            task.status != TaskStatus.done &&
            task.status != TaskStatus.skipped) {
          // Update status to skipped in Firestore
          _db.doc(doc.id).update({'status': TaskStatus.skipped.name});
        }
      }

      // Apply both tag and status filters
      final filtered = docs.where((d) {
        final task = Task.fromDoc(d);

        // Tag filter: 'All' or specific tag
        final tagMatches = _selectedTag == 'All' || task.tag == _selectedTag;

        // Status filter: only show tasks with the selected status
        final statusMatches = task.status == _selectedStatus;

        return tagMatches && statusMatches;
      }).toList();

      if (filtered.isEmpty) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _statusIcon(_selectedStatus),
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                'No ${_statusName(_selectedStatus)} tasks',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _selectedTag == 'All'
                    ? 'Try changing filters or add new tasks'
                    : 'No ${_statusName(_selectedStatus)} tasks with tag "$_selectedTag"',
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final task = Task.fromDoc(filtered[i]);
          final docId = filtered[i].id;
          
          // For skipped tasks, show reschedule option
          if (_selectedStatus == TaskStatus.skipped) {
            return _buildSkippedTaskWithReschedule(task, docId);
          } else {
            return Dismissible(
              key: Key(task.id),
              background: Container(color: Colors.red),
              onDismissed: (_) => _deleteTask(task.id),
              child: TaskCard(
                task: task,
                onEdit: () => _showEditSheet(task, docId),
                onDelete: () => _deleteTask(task.id),
                onCheck: () => _handleTaskCheck(task, docId),
              ),
            );
          }
        },
      );
    },
  );
}

/* ------------ BUILD SKIPPED TASK WITH RESCHEDULE OPTION ------------ */
Widget _buildSkippedTaskWithReschedule(Task task, String docId) {
  final suggestedDate = _getSuggestedRescheduleDate(task.deadline!);
  
  return Column(
    children: [
      Dismissible(
        key: Key(task.id),
        background: Container(color: Colors.red),
        onDismissed: (_) => _deleteTask(task.id),
        child: TaskCard(
          task: task,
          onEdit: () => _showEditSheet(task, docId),
          onDelete: () => _deleteTask(task.id),
          onCheck: () => _handleTaskCheck(task, docId),
        ),
      ),
      // Reschedule suggestion container
      Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue[100]!),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, color: Colors.blue[600], size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suggested reschedule:',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.blue[800],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    DateFormat('EEE, MMM d, yyyy').format(suggestedDate),
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.blue[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => _confirmReschedule(task, docId, suggestedDate),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              child: const Text(
                'Reschedule',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}

/* ------------ GET SUGGESTED RESCHEDULE DATE ------------ */
DateTime _getSuggestedRescheduleDate(DateTime originalDeadline) {
  final now = DateTime.now();
  final daysSinceDeadline = now.difference(originalDeadline).inDays;
  
  // If deadline was very recent (within 3 days), suggest tomorrow
  if (daysSinceDeadline >= -3 && daysSinceDeadline <= 0) {
    return now.add(const Duration(days: 1));
  }
  
  // If deadline was further in the past, suggest 2 days from now
  return now.add(const Duration(days: 2));
}

/* ------------ CONFIRM AND RESCHEDULE TASK ------------ */
Future<void> _confirmReschedule(Task task, String docId, DateTime suggestedDate) async {
  DateTime selectedDate = suggestedDate;
  
  await showDialog<bool>(
    context: context,
    builder: (_) => StatefulBuilder(
      builder: (context, setState) {
        return AlertDialog(
          title: const Text('Reschedule Task'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Task: ${task.title}',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 16),
              
              // Current deadline
              Row(
                children: [
                  const Text(
                    'Original deadline: ',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  Text(
                    DateFormat('MMM d, yyyy').format(task.deadline!),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              
              // Date picker section
              const Text(
                'Choose new due date:',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 8),
              
              // Date selection field
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey[300]!),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('EEE, MMM d, yyyy').format(selectedDate),
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    IconButton(
                      icon: const Icon(Icons.calendar_today, size: 20),
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setState(() => selectedDate = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              
              // Quick date options
              Row(
                children: [
                  _buildQuickDateOption(
                    'Tomorrow', 
                    DateTime.now().add(const Duration(days: 1)), 
                    selectedDate, 
                    (newDate) => setState(() => selectedDate = newDate)
                  ),
                  const SizedBox(width: 8),
                  _buildQuickDateOption(
                    'In 3 days', 
                    DateTime.now().add(const Duration(days: 3)), 
                    selectedDate, 
                    (newDate) => setState(() => selectedDate = newDate)
                  ),
                  const SizedBox(width: 8),
                  _buildQuickDateOption(
                    'Next week', 
                    DateTime.now().add(const Duration(days: 7)), 
                    selectedDate, 
                    (newDate) => setState(() => selectedDate = newDate)
                  ),
                ],
              ),
              const SizedBox(height: 12),
              
              const Text(
                'This will update the task status to "To Start" and open AI scheduling to find the best time slot.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue[600]),
              child: const Text('RESCHEDULE'),
            ),
          ],
        );
      },
    ),
  ).then((confirmed) async {
    if (confirmed == true) {
      await _processReschedule(task, docId, selectedDate);
    }
  });
}

/* ------------ PROCESS RESCHEDULE ------------ */
Future<void> _processReschedule(Task task, String docId, DateTime newDate) async {
  try {
    // Update task with new deadline and reset status
    await _db.doc(docId).update({
      'deadline': Timestamp.fromDate(newDate),
      'status': TaskStatus.toStart.name,
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Task rescheduled to ${DateFormat('MMM d, yyyy').format(newDate)}!'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Open AI scheduling for this task
      await _openAiScheduling(task);
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to reschedule: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/* ------------ OPEN AI SCHEDULING FOR TASK ------------ */
Future<void> _openAiScheduling(Task task) async {
  try {
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('AI is finding the best time slot for your task...'),
          ],
        ),
      ),
    );

    // Get AI scheduling suggestion
    final aiResponse = await AiScheduler.chatSchedule(task);
    
    if (mounted) {
      Navigator.of(context).pop(); // Close loading dialog
      
      // Show AI scheduling suggestion for confirmation
      await _showAiScheduleConfirmation(task, aiResponse);
    }
  } catch (e) {
    if (mounted) {
      Navigator.of(context).pop(); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('AI scheduling failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/* ------------ SHOW AI SCHEDULE CONFIRMATION ------------ */
Future<void> _showAiScheduleConfirmation(Task task, String aiResponse) async {
  // Parse the AI response to extract time suggestion
  final timeMatch = RegExp(r'(\d{1,2}:\d{2})-(\d{1,2}:\d{2})').firstMatch(aiResponse);
  final reasonMatch = RegExp(r'\?([^"]+)').firstMatch(aiResponse);
  
  String timeSuggestion = 'Unable to parse time';
  String reason = 'AI suggested time slot';
  
  if (timeMatch != null) {
    final startTime24 = timeMatch.group(1)!;
    final endTime24 = timeMatch.group(2)!;
    
    // Convert 24-hour format to 12-hour format
    final startTime12 = _convertTo12HourFormat(startTime24);
    final endTime12 = _convertTo12HourFormat(endTime24);
    
    timeSuggestion = '$startTime12-$endTime12';
  }
  if (reasonMatch != null) {
    reason = reasonMatch.group(1)?.trim() ?? 'AI suggested time slot';
  }

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('AI Schedule Suggestion'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Task: ${task.title}', style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Text('Suggested Time: $timeSuggestion', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('Reason: $reason', style: const TextStyle(fontSize: 14, color: Colors.grey)),
          const SizedBox(height: 16),
          const Text(
            'Would you like to add this to your schedule?',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('NO THANKS'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
          child: const Text('ADD TO SCHEDULE'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    await _addToAiSchedule(task, aiResponse);
  }
}

/* ------------ CONVERT 24-HOUR FORMAT TO 12-HOUR FORMAT ------------ */
String _convertTo12HourFormat(String time24) {
  try {
    final parts = time24.split(':');
    if (parts.length != 2) return time24;
    
    int hour = int.parse(parts[0]);
    final minute = parts[1];
    
    String period = 'AM';
    
    if (hour >= 12) {
      period = 'PM';
      if (hour > 12) hour -= 12;
    }
    if (hour == 0) hour = 12;
    
    return '$hour:$minute $period';
  } catch (e) {
    return time24; // Return original if parsing fails
  }
}

/* ------------ ADD TASK TO AI SCHEDULE ------------ */
Future<void> _addToAiSchedule(Task task, String aiResponse) async {
  try {
    // Parse the time from AI response
    final timeMatch = RegExp(r'(\d{1,2}:\d{2})-(\d{1,2}:\d{2})').firstMatch(aiResponse);
    
    if (timeMatch != null) {
      final startTimeStr = timeMatch.group(1)!;
      final endTimeStr = timeMatch.group(2)!;
      
      final today = DateTime.now();
      final startTime = DateFormat('HH:mm').parse(startTimeStr);
      final endTime = DateFormat('HH:mm').parse(endTimeStr);
      
      final startDateTime = DateTime(today.year, today.month, today.day, startTime.hour, startTime.minute);
      final endDateTime = DateTime(today.year, today.month, today.day, endTime.hour, endTime.minute);
      
      // Use the existing AiScheduler.insertSingleSlot method
      await AiScheduler.insertSingleSlot(
        task,
        startDateTime,
        endDateTime,
        userId: _user.uid,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Task successfully added to your schedule!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      throw Exception('Could not parse time from AI response');
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to add to schedule: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

/* ------------ BUILD QUICK DATE OPTION CHIP ------------ */
Widget _buildQuickDateOption(String label, DateTime date, DateTime selectedDate, Function(DateTime) onDateSelected) {
  final isSelected = selectedDate.year == date.year && 
                    selectedDate.month == date.month && 
                    selectedDate.day == date.day;
  
  return GestureDetector(
    onTap: () => onDateSelected(date),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue[100] : Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isSelected ? Colors.blue[300]! : Colors.grey[300]!,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          color: isSelected ? Colors.blue[800] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    ),
  );
}

}

/* =========================================================================
   BOTTOM SHEET  –  NULL-SAFE
   ========================================================================= */
class TaskBottomSheet extends StatefulWidget {
  final Task? existingTask;
  final String uid;
  const TaskBottomSheet({super.key, this.existingTask, required this.uid});

  @override
  State<TaskBottomSheet> createState() => _TaskBottomSheetState();
}

class _TaskBottomSheetState extends State<TaskBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _durationCtrl;
  late DateTime _deadline;
  late Priority _priority;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existingTask?.title ?? '');
    _descCtrl = TextEditingController(text: widget.existingTask?.desc ?? '');
    _durationCtrl = TextEditingController(
        text: widget.existingTask?.durationMin.toString() ?? '');
    _deadline = widget.existingTask?.deadline ??
        DateTime.now().add(const Duration(days: 1));
    _priority = widget.existingTask?.priority ?? Priority.medium;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

/* ------------ OPEN FULL-SCREEN AI ASSISTANT ------------ */

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final task = Task(
        id: widget.existingTask?.id ?? '',
        title: _titleCtrl.text.trim(),
        desc: _descCtrl.text.trim(),
        durationMin: int.parse(_durationCtrl.text.trim()),
        deadline: _deadline,
        priority: _priority,
        uid: widget.uid,
      );
      Navigator.of(context).pop(task);
    }
  }

  @override
  Widget build(BuildContext context) {
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
              Text(widget.existingTask == null ? 'Add task' : 'Edit task',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 20),
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 2,
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationCtrl,
                decoration: const InputDecoration(
                    labelText: 'Duration (minutes)', suffixText: 'min'),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || int.tryParse(v) == null
                    ? 'Enter a valid number'
                    : null,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(DateFormat('EEE, MMM d, yyyy').format(_deadline)),
                trailing: const Icon(Icons.calendar_today),
                onTap: _pickDeadline,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Priority>(
                value: _priority,
                items: Priority.values
                    .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                    .toList(),
                onChanged: (v) => setState(() => _priority = v!),
                decoration: const InputDecoration(labelText: 'Priority'),
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.save),
                label: Text(widget.existingTask == null ? 'CREATE' : 'UPDATE'),
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
