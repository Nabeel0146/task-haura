// lib/main.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/services/aischeduler.dart';
// ADD at the top of home.dart
import 'package:taskhaura/screens/Schpage.dart' show SchedulePage;
import 'package:taskhaura/register.dart';

/* =========================================================================
   MAIN
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
          return const AuthGate(); // simple placeholder
        },
      ),
    );
  }
}
final db = FirebaseFirestore.instance;   // <-- add this

/* =========================================================================
   AUTH GATE  (placeholder – replace with your real login screen)
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
   MODEL
   ========================================================================= */
enum Priority { low, medium, high }

class Task {
    final String id;
  final String title;
  final String desc;
  final int durationMin;
  final DateTime deadline;          //  <--  NULLABLE
  final Priority priority;
  final String uid;

  Task({
    this.id = '',
    required this.title,
    required this.desc,
    required this.durationMin,
    required this.deadline,
    required this.priority,
    required this.uid,
  });

  factory Task.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => Task(
        id: doc.id,
        title: doc.data()?['title'] ?? '',
        desc: doc.data()?['desc'] ?? '',
        durationMin: doc.data()?['durationMin'] ?? 0,
        deadline:
            (doc.data()?['deadline'] as Timestamp?)?.toDate() ?? DateTime.now(),
        priority: Priority.values.byName(doc.data()?['priority'] ?? 'medium'),
        uid: doc.data()?['uid'] ?? '',
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'desc': desc,
        'durationMin': durationMin,
        'deadline': Timestamp.fromDate(deadline),
        'priority': priority.name,
        'uid': uid,
      };
}

/* =========================================================================
   HOME PAGE
   ========================================================================= */
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _db = FirebaseFirestore.instance.collection('tasks');
  final _user = FirebaseAuth.instance.currentUser!;

  /* ---------------- CRUD ---------------- */
  /* ---------------- CREATE ---------------- */

  Future<void> _aiSchedule() async {
  final snap = await _db.where('uid', isEqualTo: _user.uid).get();
  final tasks = snap.docs.map(Task.fromDoc).toList();
  if (tasks.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Add some tasks first')));
    return;
  }
  try {
    final schedId = await AiScheduler.optimiseAndSave(tasks);
    print('✅ schedule saved with id: $schedId');
    if (!mounted) return;
    // --- show success dialog instead of navigating ---
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Schedule created'),
        content: const Text('Your AI-generated schedule is ready.'),
        actions: [
          TextButton(
            onPressed: Navigator.of(context).pop,
            child: const Text('OK'),
          ),
        ],
      ),
    );
  } catch (e) {
    print('❗ AI scheduler error: $e');
  }
}

  Future<void> _addTask(Task task) async {
    try {
      await _db.add(task.toJson()); // writes to collection "tasks"
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add task: $e')),
      );
    }
  }

  Future<void> _updateTask(String id, Task task) async =>
      _db.doc(id).update(task.toJson());

 Future<void> _deleteTask(String id) async {
  try {
    // 1. read the document
    final doc = await _db.doc(id).get();
    if (!doc.exists) return;

    // 2. copy to deletedTasks with extra timestamp
    final data = doc.data()!;
    data['deletedAt'] = FieldValue.serverTimestamp();
    await db.collection('deletedTasks').add(data);

    // 3. delete from original collection
    await _db.doc(id).delete();

    print('✅ task $id moved to deletedTasks, HomePage');
  } catch (e) {
    print('❗ move+delete failed: $e');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Delete failed: $e')),
    );
  }
}
  /* ---------------- logout ---------------- */

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

    await FirebaseAuth.instance.signOut(); // 1. sign out
    if (!mounted) return;

    // 2. drop the user on the registration screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const RegisterPage()),
      (_) => false, // remove every previous route
    );
  }

  /* ---------------- bottom sheets ---------------- */
  Future<void> _showAddSheet() async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TaskBottomSheet(uid: _user.uid),
    );
    if (result != null) await _addTask(result);
  }

  Future<void> _showEditSheet(Task task, String id) async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (_) => TaskBottomSheet(uid: _user.uid, existingTask: task),
    );
    if (result != null) await _updateTask(id, result);
  }

  /* ---------------- build ---------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Task Haura'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _confirmLogout,
          ),
        ],
      ),
      // floatingActionButton: FloatingActionButton(
      //   onPressed: _showAddSheet,
      //   tooltip: 'Add task',
      //   child: const Icon(Icons.add),
      // ),
      body: Stack(
        children: [
          /* gradient background */
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.center,
                colors: [Color(0xFF74EC7A), Colors.white],
              ),
            ),
          ),
          /* tasks list */
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Row(
                    children: [
                      Image.asset('assets/taskhauralogo.png',
                          width: 36, height: 36),
                      const SizedBox(width: 12),
                      const Text('Task Haura',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Expanded(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: _db
                        .where('uid', isEqualTo: _user.uid)
                        .orderBy('deadline')
                        .snapshots(),
                    builder: (_, snap) {
                      if (snap.hasError)
                        return Center(child: Text('${snap.error}'));
                      if (!snap.hasData)
                        return const Center(child: CircularProgressIndicator());
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text('No tasks yet – tap + to add one',
                              style: TextStyle(color: Colors.white70)),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: docs.length,
                        itemBuilder: (_, i) {
                          final task = Task.fromDoc(docs[i]);
                          return Dismissible(
                            key: Key(task.id),
                            background: Container(color: Colors.red),
                            onDismissed: (_) => _deleteTask(task.id),
                            child: TaskCard(
                              task: task,
                              onEdit: () => _showEditSheet(task, docs[i].id),
                              onDelete: () => _deleteTask(task.id), // NEW
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    FloatingActionButton(
                      heroTag: 'add',
                      onPressed: _showAddSheet,
                      tooltip: 'Add task',
                      child: const Icon(Icons.add),
                    ),
                    const SizedBox(width: 16),
                    FloatingActionButton(
                      heroTag: 'ai',
                      onPressed: _aiSchedule,
                      tooltip: 'AI schedule',
                      child: const Icon(Icons.auto_fix_high),
                    ),
                  ],
                )
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================================
   BOTTOM SHEET (ADD / EDIT)
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

/* =========================================================================
   TASK CARD
   ========================================================================= */
/* =========================================================================
   TASK CARD  (updated delete button)
   ========================================================================= */
class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete; // NEW
  const TaskCard({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete, // NEW
  });

  Color _priorityColor() => task.priority == Priority.high
      ? Colors.redAccent
      : task.priority == Priority.medium
          ? Colors.orangeAccent
          : Colors.green;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors.white.withOpacity(.72),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(task.title,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  onPressed: onEdit,
                  splashRadius: 20,
                ),
                IconButton(
                  // NEW
                  icon: const Icon(Icons.delete_outline,
                      size: 18, color: Colors.red),
                  onPressed: () => _confirmDelete(context),
                  splashRadius: 20,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(task.desc, maxLines: 2, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('${task.durationMin} min'),
                const SizedBox(width: 16),
                Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(DateFormat('MMM d').format(task.deadline)),
                const Spacer(),
                Chip(
                  label: Text(task.priority.name.toUpperCase(),
                      style:
                          const TextStyle(color: Colors.white, fontSize: 10)),
                  backgroundColor: _priorityColor(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /* quick confirmation before deleting */
  void _confirmDelete(BuildContext ctx) {
    showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Delete task?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: Navigator.of(ctx).pop, child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop(true);
              onDelete(); // call the injected callback
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
