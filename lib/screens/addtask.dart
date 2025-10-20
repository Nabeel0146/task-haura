import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart'; // <-- adjust to your path

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
  final _newTagCtrl = TextEditingController();

  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  Priority _priority = Priority.medium;
  TaskStatus _status = TaskStatus.toStart;
  String _selectedTag = ''; // empty = "No tag"

  List<String> _userTags = [];
  bool _loadingTags = true; // NEW: guard against premature submit

  /* ---------------------------------------------------------- */
  /* Lifecycle                                                  */
  /* ---------------------------------------------------------- */
  @override
  void initState() {
    super.initState();
    _loadTags();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _durationCtrl.dispose();
    _newTagCtrl.dispose();
    super.dispose();
  }

  /* ---------------------------------------------------------- */
  /* Tags handling                                              */
  /* ---------------------------------------------------------- */
  Future<void> _loadTags() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('users').doc(widget.uid).get();
      final List<dynamic> tags = snap.data()?['tags'] ?? [];
      if (mounted) {
        setState(() {
          _userTags = tags.cast<String>();
          _loadingTags = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingTags = false);
    }
  }

  Future<void> _addTag(String tag) async {
    if (tag.trim().isEmpty) return;
    await FirebaseFirestore.instance.collection('users').doc(widget.uid).set(
      {'tags': FieldValue.arrayUnion([tag.trim()])},
      SetOptions(merge: true),
    );
    _newTagCtrl.clear();
    await _loadTags(); // refresh chips
  }

  /* ---------------------------------------------------------- */
  /* Date picker                                                */
  /* ---------------------------------------------------------- */
  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _deadline = picked);
  }

  /* ---------------------------------------------------------- */
  /* Submit                                                     */
  /* ---------------------------------------------------------- */
  void _submit() {
    if (_loadingTags) return; // still loading – ignore tap
    if (_formKey.currentState!.validate()) {
      final task = Task(
        title: _titleCtrl.text.trim(),
        desc: _descCtrl.text.trim(),
        durationMin: int.parse(_durationCtrl.text.trim()),
        deadline: _deadline,
        priority: _priority,
        uid: widget.uid,
        status: _status,
        tag: _selectedTag,
      );
      Navigator.of(context).pop(task);
    }
  }

  

  /* ---------------------------------------------------------- */
  /* Add-tag dialog                                             */
  /* ---------------------------------------------------------- */
  Future<void> _showAddTagDialog() async {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add new tag'),
        content: TextField(
          controller: _newTagCtrl,
          decoration: const InputDecoration(hintText: 'Tag name'),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: Navigator.of(_).pop,
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(_).pop();
              _addTag(_newTagCtrl.text);
            },
            child: const Text('ADD'),
          ),
        ],
      ),
    );
  }

  /* ---------------------------------------------------------- */
  /* UI – Tag chips                                             */
  /* ---------------------------------------------------------- */
  Widget _buildTagChips() {
    if (_loadingTags) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_userTags.isEmpty) {
      return Center(
        child: TextButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add your first tag'),
          onPressed: _showAddTagDialog,
        ),
      );
    }

    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('No tag'),
          selected: _selectedTag == '',
          selectedColor: Colors.blue.shade100,
          onSelected: (_) => setState(() => _selectedTag = ''),
        ),
        ..._userTags.map(
          (t) => ChoiceChip(
            label: Text(t),
            selected: _selectedTag == t,
            selectedColor: Colors.blue.shade100,
            onSelected: (_) => setState(() => _selectedTag = t),
          ),
        ),
        ActionChip(
          label: const Icon(Icons.add, size: 18),
          onPressed: _showAddTagDialog,
        ),
      ],
    );
  }

  /* ---------------------------------------------------------- */
  /* Main build                                                 */
  /* ---------------------------------------------------------- */
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add new task'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _submit),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: const InputDecoration(labelText: 'Title'),
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                validator: (v) => v!.trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Duration', suffixText: 'minutes'),
                validator: (v) =>
                    v == null || int.tryParse(v) == null ? 'Invalid number' : null,
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
              const SizedBox(height: 16),
              DropdownButtonFormField<TaskStatus>(
                value: _status,
                items: TaskStatus.values.map((s) {
                  String pretty = s.name
                      .replaceAll('toStart', 'to start')
                      .replaceAll('onDoing', 'on doing');
                  return DropdownMenuItem(value: s, child: Text(pretty));
                }).toList(),
                onChanged: (v) => setState(() => _status = v!),
                decoration: const InputDecoration(labelText: 'Status'),
              ),
              const SizedBox(height: 16),
              const Text('Tag', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 8),
              _buildTagChips(),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('CREATE TASK'),
                  onPressed: _submit,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}