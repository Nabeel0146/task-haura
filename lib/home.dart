

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<String> _tasks = [];

  static const _kStorageKey = 'tasks';

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  /* --------------- persistence helpers --------------- */

  Future<void> _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kStorageKey) ?? [];
    setState(() => _tasks.addAll(raw));
  }

  Future<void> _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_kStorageKey, _tasks);
  }

  /* --------------- UI helpers --------------- */

  Future<void> _addTask() async {
    final textCtrl = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('New task'),
        content: TextField(
          controller: textCtrl,
          decoration: const InputDecoration(hintText: 'What do you need to do?'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ADD'),
          ),
        ],
      ),
    );

    if (result == true && textCtrl.text.trim().isNotEmpty) {
      setState(() {
        _tasks.add(textCtrl.text.trim());
        _saveTasks();
      });
    }
  }

  void _removeTask(int index) {
    setState(() {
      _tasks.removeAt(index);
      _saveTasks();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Task removed'), duration: Duration(seconds: 1)),
    );
  }

  /* --------------- build --------------- */

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        centerTitle: true,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addTask,
        tooltip: 'Add task',
        child: const Icon(Icons.add),
      ),
      body: _tasks.isEmpty
          ? const Center(child: Text('No tasks yet – tap + to add one'))
          : ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _tasks.length,
              itemBuilder: (context, index) {
                final task = _tasks[index];
                return Dismissible(
                  key: ValueKey('$task-$index'),
                  background: Container(color: Colors.red),
                  onDismissed: (_) => _removeTask(index),
                  child: Card(
                    child: ListTile(
                      title: Text(task),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _removeTask(index),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}