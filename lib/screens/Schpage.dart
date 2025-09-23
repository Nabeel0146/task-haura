import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/home.dart'; // Task model

class SchedulePage extends StatelessWidget {
  final List<Task>? tasks; // nullable so nav-bar can use it
  const SchedulePage({super.key, this.tasks});

  @override
  Widget build(BuildContext context) {
    final list = tasks ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('AI Created Schedule')),
      body: list.isEmpty
          ? const Center(child: Text('No schedule – generate one from Home'))
          : _TaskList(tasks: list),
    );
  }
}

class _TaskList extends StatelessWidget {
  final List<Task> tasks;
  const _TaskList({required this.tasks});

  String _formatTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: tasks.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, i) {
        final task = tasks[i];
        final start = task.deadline;
        final end = start.add(Duration(minutes: task.durationMin));
        final slot = '${_formatTime(start)} – ${_formatTime(end)}';
        return ListTile(
          leading: CircleAvatar(child: Text('${i + 1}')),
          title: Text(task.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Time slot: $slot'),
        );
      },
    );
  }
}