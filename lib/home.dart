import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'My Tasks',
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
  final List<Task> _tasks = [];
  static const _kStorageKey = 'tasks_v2';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  /* ---------------- persistence ---------------- */

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kStorageKey) ?? [];
    _tasks.addAll(raw.map((e) => Task.fromJson(jsonDecode(e))));
    setState(() {});
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = _tasks.map((t) => jsonEncode(t.toJson())).toList();
    await prefs.setStringList(_kStorageKey, encoded);
  }

  /* ---------------- add task ---------------- */

  Future<void> _addTask() async {
    final result = await showModalBottomSheet<Task>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const AddTaskSheet(),
    );

    if (result != null) {
      setState(() => _tasks.add(result));
      await _saveTasks();
    }
  }

  /* ---------------- delete task ---------------- */

  void _deleteTask(int index) {
    setState(() => _tasks.removeAt(index));
    _saveTasks();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task removed'), duration: Duration(seconds: 1)),
    );
  }

  /* ---------------- build ---------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
      body: Stack(
        children: [
          /* ---------------- gradient ---------------- */
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              height: MediaQuery.of(context).size.height * 1,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [
                    Color(0xFF4CAF50),
                    Color.fromARGB(255, 255, 255, 255),
                  ],
                ),
              ),
            ),
          ),

          /* ---------------- content ---------------- */
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                /* title */
                const Padding(
                  padding: EdgeInsets.fromLTRB(24, 16, 24, 24),
                  child: Text(
                    'My Tasks',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                /* list */
                Expanded(
                  child: _tasks.isEmpty
                      ? const Center(
                          child: Text(
                            'No tasks yet – tap + to add one',
                            style: TextStyle(color: Colors.white70),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _tasks.length,
                          itemBuilder: (context, index) {
                            final t = _tasks[index];
                            return Dismissible(
                              key: ValueKey(t.hashCode),
                              background: Container(color: Colors.red),
                              onDismissed: (_) => _deleteTask(index),
                              child: TaskCard(task: t),
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
        deadline: DateTime.parse(json['deadline']),
        priority: Priority.values.byName(json['priority']),
      );

  Map<String, dynamic> toJson() => {
        'title': title,
        'desc': desc,
        'durationMin': durationMin,
        'deadline': deadline.toIso8601String(),
        'priority': priority.name,
      };
}

enum Priority { low, medium, high }

/* =========================================================================
   ADD-TASK BOTTOM SHEET
   ========================================================================= */

class AddTaskSheet extends StatefulWidget {
  const AddTaskSheet({super.key});

  @override
  State<AddTaskSheet> createState() => _AddTaskSheetState();
}

class _AddTaskSheetState extends State<AddTaskSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  Priority _priority = Priority.medium;

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
              Text('Add a task', style: Theme.of(context).textTheme.headlineSmall),
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
                validator: (v) {
                  if (v == null || int.tryParse(v) == null) return 'Enter a number';
                  return null;
                },
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
                          child: Text(e.name[0].toUpperCase() + e.name.substring(1)),
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
  const TaskCard({super.key, required this.task});

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
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 5,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _priorityColor(),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    task.title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(task.desc, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text('${task.durationMin} min'),
                const SizedBox(width: 16),
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(DateFormat('MMM d').format(task.deadline)),
                const Spacer(),
                Chip(
                  label: Text(
                    task.priority.name.toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
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
}