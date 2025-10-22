import 'package:cloud_firestore/cloud_firestore.dart';
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
  final _newTagCtrl = TextEditingController();

  DateTime _deadline = DateTime.now().add(const Duration(days: 1));
  Priority _priority = Priority.medium;
  TaskStatus _status = TaskStatus.toStart;
  String _selectedTag = '';

  List<String> _userTags = [];
  bool _loadingTags = true;
  bool _saving = false;
  bool _repeatingTask = false; // NEW: Repeating task flag

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

  Future<void> _loadTags() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .get();
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
    await _loadTags();
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _deadline = picked);
    }
  }

  // NEW: Check for existing tasks with same title
  Future<bool> _checkForExistingTasks() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return false;

    final snap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('uid', isEqualTo: widget.uid)
        .where('title', isEqualTo: title)
        .get();

    return snap.docs.isNotEmpty;
  }

  // NEW: Show repeating task confirmation dialog
  Future<bool> _showRepeatingTaskDialog() async {
    final existingCount = await _getExistingTaskCount();
    
    return await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.repeat, color: Colors.blue[600]),
            const SizedBox(width: 8),
            const Text('Repeating Task Found'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'You\'ve created "${_titleCtrl.text.trim()}" $existingCount time(s) before.',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Is this a repeating task/habit?',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Marking as repeating will help you track habits and show a special indicator.',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('NO, JUST ONCE'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[600],
            ),
            child: const Text('YES, HABIT'),
          ),
        ],
      ),
    ) ?? false;
  }

  // NEW: Get count of existing tasks with same title
  Future<int> _getExistingTaskCount() async {
    final snap = await FirebaseFirestore.instance
        .collection('tasks')
        .where('uid', isEqualTo: widget.uid)
        .where('title', isEqualTo: _titleCtrl.text.trim())
        .get();
    return snap.docs.length;
  }

  Future<void> _submit() async {
    if (_loadingTags || _saving) return;
    if (_formKey.currentState!.validate()) {
      setState(() => _saving = true);
      
      try {
        // Check for existing tasks with same title
        final hasExistingTasks = await _checkForExistingTasks();
        
        // If existing tasks found and not already marked as repeating, show dialog
        if (hasExistingTasks && !_repeatingTask) {
          final shouldMarkAsRepeating = await _showRepeatingTaskDialog();
          if (mounted) {
            setState(() {
              _repeatingTask = shouldMarkAsRepeating;
            });
          }
        }

        // Create task object with repeatingTask field
        final task = Task(
          title: _titleCtrl.text.trim(),
          desc: _descCtrl.text.trim(),
          durationMin: int.parse(_durationCtrl.text.trim()),
          deadline: _deadline,
          priority: _priority,
          uid: widget.uid,
          status: _status,
          tag: _selectedTag,
          repeatingTask: _repeatingTask, // NEW: Include repeating task flag
        );

        // Convert task to map for Firestore manually
        final taskMap = {
          'title': task.title,
          'desc': task.desc,
          'durationMin': task.durationMin,
          'deadline': Timestamp.fromDate(task.deadline!),
          'priority': task.priority.name,
          'uid': task.uid,
          'status': task.status.name,
          'tag': task.tag,
          'createdAt': FieldValue.serverTimestamp(),
          'repeatingTask': task.repeatingTask, // NEW: Include in Firestore
        };

        // Add to Firestore
        final docRef = await FirebaseFirestore.instance
            .collection('tasks')
            .add(taskMap);

        // Update the task with the generated ID
        await docRef.update({'id': docRef.id});

        if (mounted) {
          // Show success message with repeating task info if applicable
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    _repeatingTask ? Icons.repeat : Icons.check,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _repeatingTask 
                          ? 'Habit task created successfully!'
                          : 'Task created successfully!',
                    ),
                  ),
                ],
              ),
              backgroundColor: Colors.green,
            ),
          );

          // Navigate back
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error creating task: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() => _saving = false);
        }
      }
    }
  }

  Future<void> _showAddTagDialog() async {
    return showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Add New Tag',
            style: TextStyle(fontWeight: FontWeight.w600)),
        content: TextField(
          controller: _newTagCtrl,
          decoration: InputDecoration(
            hintText: 'Enter tag name',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(_).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(_).pop();
              _addTag(_newTagCtrl.text);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  Widget _buildTagChips() {
    if (_loadingTags) {
      return const Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            // No tag option
            FilterChip(
              label: Text(
                'No tag',
                style: TextStyle(
                  color: _selectedTag == '' ? Colors.white : Colors.grey[700],
                ),
              ),
              selected: _selectedTag == '',
              selectedColor: Theme.of(context).primaryColor,
              checkmarkColor: Colors.white,
              backgroundColor: Colors.grey[100],
              onSelected: (_) => setState(() => _selectedTag = ''),
            ),
            // User tags
            ..._userTags.map(
              (t) => FilterChip(
                label: Text(
                  t,
                  style: TextStyle(
                    color: _selectedTag == t ? Colors.white : Colors.grey[700],
                  ),
                ),
                selected: _selectedTag == t,
                selectedColor: Theme.of(context).primaryColor,
                checkmarkColor: Colors.white,
                backgroundColor: Colors.grey[100],
                onSelected: (_) => setState(() => _selectedTag = t),
              ),
            ),
            // Add tag chip
            InputChip(
              label: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    'New Tag',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
              backgroundColor: Colors.grey[50],
              onPressed: _showAddTagDialog,
            ),
          ],
        ),
        if (_userTags.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'No tags yet. Add some to organize your tasks better!',
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  // NEW: Build repeating task indicator in the form
  Widget _buildRepeatingTaskIndicator() {
    if (!_repeatingTask) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[100]!),
      ),
      child: Row(
        children: [
          Icon(Icons.repeat, color: Colors.green[600], size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Repeating Task/Habit',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Colors.green[800],
                    fontSize: 14,
                  ),
                ),
                Text(
                  'This task will be marked as a habit',
                  style: TextStyle(
                    color: Colors.green[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.green[600], size: 18),
            onPressed: () {
              setState(() {
                _repeatingTask = false;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required Widget child,
    String? helperText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.black87,
          ),
        ),
        const SizedBox(height: 8),
        child,
        if (helperText != null) ...[
          const SizedBox(height: 4),
          Text(
            helperText,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Create New Task',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        elevation: 0,
        foregroundColor: Colors.black,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              icon: _saving 
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save, size: 20),
              label: _saving ? const Text('Saving...') : const Text('Save'),
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Repeating Task Indicator
              _buildRepeatingTaskIndicator(),

              // Title Field
              _buildFormField(
                label: 'Task Title *',
                child: TextFormField(
                  controller: _titleCtrl,
                  decoration: InputDecoration(
                    hintText: 'Enter task title',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  validator: (v) => v!.trim().isEmpty ? 'Title is required' : null,
                ),
              ),

              // Description Field
              _buildFormField(
                label: 'Description *',
                child: TextFormField(
                  controller: _descCtrl,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Describe your task...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  validator: (v) => v!.trim().isEmpty ? 'Description is required' : null,
                ),
              ),

              // Duration Field
              _buildFormField(
                label: 'Duration *',
                helperText: 'Estimated time needed in minutes',
                child: TextFormField(
                  controller: _durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'e.g., 30',
                    suffixText: 'minutes',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  validator: (v) =>
                      v == null || int.tryParse(v) == null ? 'Please enter a valid number' : null,
                ),
              ),

              // Deadline Picker
              _buildFormField(
                label: 'Deadline',
                child: InkWell(
                  onTap: _pickDeadline,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_today,
                          color: Theme.of(context).primaryColor,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          DateFormat('EEE, MMM d, yyyy').format(_deadline),
                          style: const TextStyle(fontSize: 16),
                        ),
                        const Spacer(),
                        Text(
                          'Change',
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Priority Dropdown
              _buildFormField(
                label: 'Priority',
                child: DropdownButtonFormField<Priority>(
                  value: _priority,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: Priority.values.map((p) {
                    Color color;
                    switch (p) {
                      case Priority.high:
                        color = Colors.red;
                      case Priority.medium:
                        color = Colors.orange;
                      case Priority.low:
                        color = Colors.green;
                    }
                    return DropdownMenuItem(
                      value: p,
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            p.name.toUpperCase(),
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: color,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _priority = v!),
                ),
              ),

              // Status Dropdown
              _buildFormField(
                label: 'Status',
                child: DropdownButtonFormField<TaskStatus>(
                  value: _status,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                  items: TaskStatus.values.map((s) {
                    String pretty = s.name
                        .replaceAll('toStart', 'To Start')
                        .replaceAll('onDoing', 'In Progress')
                        .replaceAll('completed', 'Completed');
                    return DropdownMenuItem(
                      value: s,
                      child: Text(pretty),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _status = v!),
                ),
              ),

              // Tags Section
              _buildFormField(
                label: 'Tags',
                helperText: 'Organize your tasks with tags',
                child: _buildTagChips(),
              ),

              const SizedBox(height: 24),

              // Create Task Button
              SizedBox(
                height: 54,
                child: FilledButton.icon(
                  icon: _saving 
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : const Icon(Icons.add_task, size: 24),
                  label: _saving 
                      ? const Text('CREATING TASK...')
                      : const Text(
                          'CREATE TASK',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                  onPressed: _saving ? null : _submit,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}