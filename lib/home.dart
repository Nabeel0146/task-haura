import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();      // ← Firebase init
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Task Haura',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.green),
      home: const HomePage(),
    );
  }
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

  /* ---------------- CRUD helpers ---------------- */

  Future<void> _addTask(Task task) async {
    await _db.add(task.toJson());
  }

  Future<void> _updateTask(String id, Task task) async {
    await _db.doc(id).update(task.toJson());
  }

  Future<void> _deleteTask(String id) async {
    await _db.doc(id).delete();
  }
  Future<void> _confirmLogout(BuildContext context) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Logout?'),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('CANCEL'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('LOGOUT'),
        ),
      ],
    ),
  );

  if (shouldLogout ?? false) {
    // TODO: replace with your real sign-out logic (FirebaseAuth, etc.)
    // Example:
    // await FirebaseAuth.instance.signOut();
    // Navigator.pushReplacementNamed(context, '/login');
  }
}

  /* ---------------- bottom-sheet wrappers ---------------- */

  Future<void> _showAddSheet() async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddTaskSheet(),
    );
    if (result != null) await _addTask(result);
  }

  Future<void> _showEditSheet(Task task, String id) async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddTaskSheet(existingTask: task),
    );
    if (result != null) await _updateTask(id, result);
  }

  /* ---------------- build ---------------- */

@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(
      title: const Text('Task Haura'),
      backgroundColor: Colors.transparent,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.logout, color: Colors.white),
          tooltip: 'Logout',
          onPressed: () => _confirmLogout(context),
        ),
      ],
    ),
    extendBodyBehindAppBar: true, // keeps gradient visible
    floatingActionButton: FloatingActionButton(
      onPressed: _showAddSheet,
      tooltip: 'Add task',
      child: const Icon(Icons.add),
    ),
    body: Stack(
        children: [
          /* gradient */
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  transform: GradientRotation(6),
                  end: Alignment.center,
                  colors: [
                    Color.fromARGB(255, 116, 236, 122),
                    Color.fromARGB(255, 255, 255, 255),
                  ],
                ),
              ),
            ),
          ),
          /* content */
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /* header + logo */
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                  child: Row(
                    children: [
                      Image.asset('assets/taskhauralogo.png',
                          width: 36, height: 36),
                      const SizedBox(width: 12),
                      const Text(
                        'Task Haura',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                /* task list */
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: _db.orderBy('deadline').snapshots(),
                    builder: (context, snap) {
                      if (snap.hasError) {
                        return Center(child: Text('${snap.error}'));
                      }
                      if (!snap.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final docs = snap.data!.docs;
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text(
                            'No tasks yet – tap + to add one',
                            style: TextStyle(color: Colors.white70),
                          ),
                        );
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: docs.length,
                        itemBuilder: (context, index) {
                          final doc = docs[index];
                          final task =
                              Task.fromJson(doc.data() as Map<String, dynamic>);
                          return TaskCard(
                            task: task,
                            onEdit: () => _showEditSheet(task, doc.id),
                            onDelete: () => _deleteTask(doc.id),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/* =========================================================================
   MODEL
   ========================================================================= */

class Task {
  final String title;
  final String desc;
  final int durationMin;
  final DateTime deadline;
  final Priority priority;

  Task({
    required this.title,
    required this.desc,
    required this.durationMin,
    required this.deadline,
    required this.priority,
  });

  factory Task.fromJson(Map<String, dynamic> json) => Task(
        title: json['title'],
        desc: json['desc'],
        durationMin: json['durationMin'],
        deadline: (json['deadline'] as Timestamp).toDate(),
        priority: Priority.values.byName(json['priority']),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'desc': desc,
        'durationMin': durationMin,
        'deadline': Timestamp.fromDate(deadline),
        'priority': priority.name,
      };
}

enum Priority { low, medium, high }

/* =========================================================================
   ADD-TASK BOTTOM SHEET
   ========================================================================= */

class AddTaskSheet extends StatefulWidget {
  final Task? existingTask;
  const AddTaskSheet({super.key, this.existingTask});

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
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

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
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
                  labelText: 'Duration (minutes)',
                  suffixText: 'min',
                ),
                keyboardType: TextInputType.number,
                validator: (v) =>
                    v == null || int.tryParse(v) == null ? 'Enter a number' : null,
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
                decoration: const InputDecoration(labelText: 'Priority'),
                items: Priority.values
                    .map((e) => DropdownMenuItem(
                          value: e,
                          child: Text(
                              e.name[0].toUpperCase() + e.name.substring(1)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _priority = v!),
              ),
              const SizedBox(height: 30),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('CANCEL'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () {
                      if (_formKey.currentState!.validate()) {
                        Navigator.pop(
                          context,
                          Task(
                            title: _titleCtrl.text.trim(),
                            desc: _descCtrl.text.trim(),
                            durationMin: int.parse(_durationCtrl.text),
                            deadline: _deadline,
                            priority: _priority,
                          ),
                        );
                      }
                    },
                    child: const Text('SAVE'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
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

class TaskCard extends StatelessWidget {
  final Task task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TaskCard({
    super.key,
    required this.task,
    required this.onEdit,
    required this.onDelete,
  });

  Color _priorityColor() {
    switch (task.priority) {
      case Priority.high:
        return Colors.redAccent;
      case Priority.medium:
        return Colors.orangeAccent;
      case Priority.low:
        return Colors.green;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Theme.of(context).colorScheme.surface.withOpacity(.72);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: cardColor,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 92,
            decoration: BoxDecoration(
              color: _priorityColor(),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          task.title,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        onPressed: onEdit,
                        splashRadius: 20,
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        onPressed: onDelete,
                        splashRadius: 20,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(task.desc,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text('${task.durationMin} min',
                          style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(width: 16),
                      Icon(Icons.calendar_today,
                          size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(DateFormat('MMM d').format(task.deadline),
                          style: Theme.of(context).textTheme.bodySmall),
                      const Spacer(),
                      Chip(
                        label: Text(
                          task.priority.name.toUpperCase(),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 10),
                        ),
                        backgroundColor: _priorityColor(),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      const SizedBox(width: 8),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}