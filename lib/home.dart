import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';
import 'package:taskhaura/screens/addtask.dart';
import 'package:taskhaura/screens/Schpage.dart' show SchedulePage;
import 'package:taskhaura/AUTH/register.dart';
import 'package:taskhaura/screens/ai_chatscreen.dart';
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
  final _db   = FirebaseFirestore.instance.collection('tasks');
  final _user = FirebaseAuth.instance.currentUser!;

  /* ------------ FILTER STATE ------------ */
  List<String> _userTags   = [];
  String       _selectedTag = 'All';

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
              child: _filterChip(t, _selectedTag == t,
                  () => setState(() => _selectedTag = t)),
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
      case TaskStatus.toStart: return Icons.play_arrow;
      case TaskStatus.onDoing: return Icons.autorenew;
      case TaskStatus.done:    return Icons.check_circle;
      case TaskStatus.skipped: return Icons.skip_next;
    }
  }

  String _statusName(TaskStatus s) =>
      s.name.replaceAll('toStart', 'to start').replaceAll('onDoing', 'on doing');

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
    extendBodyBehindAppBar: false,          //  <—  changed
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
    endDrawer: Drawer( /* … unchanged … */ ),
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
            const SizedBox(height: 8),        //  tiny top padding (optional)
            _buildTagFilter(),                //  now drawn *below* the AppBar
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


/* extracted task-list builder – keeps build() clean */
Widget _buildTaskList() {
  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
    stream: _db
        .where('uid', isEqualTo: _user.uid)
        .orderBy('deadline')
        .snapshots(),
    builder: (_, snap) {
      if (snap.hasError) return Center(child: Text('${snap.error}'));
      if (!snap.hasData) return const Center(child: CircularProgressIndicator());

      final docs = snap.data!.docs;
      final filtered = docs.where((d) {
        final t = Task.fromDoc(d);
        final tagOk = _selectedTag == 'All' || t.tag == _selectedTag;
        final statusOk = _selectedStatus == t.status;
        return tagOk && statusOk;
      }).toList();

      if (filtered.isEmpty) {
        return const Center(
          child: Text('No tasks match the selected filters',
              style: TextStyle(color: Colors.white70)),
        );
      }

      return ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
        itemCount: filtered.length,
        itemBuilder: (_, i) {
          final task = Task.fromDoc(filtered[i]);
          return Dismissible(
            key: Key(task.id),
            background: Container(color: Colors.red),
            onDismissed: (_) => _deleteTask(task.id),
            child: TaskCard(
              task: task,
              onEdit: () => _showEditSheet(task, filtered[i].id),
              onDelete: () => _deleteTask(task.id),
            ),
          );
        },
      );
    },
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
