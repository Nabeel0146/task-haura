import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';

class AddTaskPage extends StatefulWidget {
  final String uid;
  const AddTaskPage({super.key, required this.uid});

  @override
  State<AddTaskPage> createState() => _AddTaskPageState();
}

class _AddTaskPageState extends State<AddTaskPage> {
  final _formKey = GlobalKey<FormState>();

  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();

  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  Priority _priority = Priority.medium;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  /* ---------------- date picker ---------------- */
  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  /* ---------------- submit ---------------- */
  void _submit() {
    if (_formKey.currentState!.validate()) {
      final task = Task(
        title: _titleCtrl.text.trim(),
        desc: _descCtrl.text.trim(),
        durationMin: int.parse(_durationCtrl.text.trim()),
        deadline: _deadline,
        priority: _priority,
        uid: widget.uid,
      );
      Navigator.of(context).pop<Task?>(task); // <-- typed pop
    }
  }

  /* ---------------- build ---------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add new task'),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text(
              'SAVE',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descCtrl,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 3,
              validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _durationCtrl,
              decoration: const InputDecoration(
                labelText: 'Duration (minutes)',
                suffixText: 'min',
              ),
              keyboardType: TextInputType.number,
              validator: (v) =>
                  v == null || int.tryParse(v) == null ? 'Valid number required' : null,
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(DateFormat('EEE, MMM d, yyyy').format(_deadline)),
              trailing: const Icon(Icons.calendar_today),
              onTap: _pickDeadline,
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<Priority>(
              value: _priority,
              items: Priority.values
                  .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                  .toList(),
              onChanged: (v) => setState(() => _priority = v!),
              decoration: const InputDecoration(labelText: 'Priority'),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.check),
                label: const Text('CREATE TASK'),
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }
}