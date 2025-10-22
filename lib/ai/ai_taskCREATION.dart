import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/models/task.dart';
import 'package:voice_to_text/voice_to_text.dart';
import '../main.dart';

class AITaskCreationPage extends StatefulWidget {
  final String? userTags;
  final String? workingHours;
  final String userId;
  
  const AITaskCreationPage({
    super.key,
    this.userTags,
    this.workingHours,
    required this.userId,
  });

  @override
  State<AITaskCreationPage> createState() => _AITaskCreationPageState();
}

class _AITaskCreationPageState extends State<AITaskCreationPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _conversation = [];
  List<Task> _generatedTasks = [];
  bool _thinking = false;
  
  // For task finalization
  List<String> _userTags = [];
  bool _loadingTags = true;
  Map<int, DateTime> _taskDeadlines = {};
  Map<int, String> _taskTags = {};

  // Input fields
  Priority _selectedPriority = Priority.medium;
  DateTime? _selectedDueDate;
  bool _showInputOptions = false;

  // Voice to text
  final VoiceToText _speech = VoiceToText();
  String _recognizedText = '';

  @override
  void initState() {
    super.initState();
    _addWelcomeMessage();
    _loadUserTags();
    _initSpeech();
  }

  void _initSpeech() {
    _speech.initSpeech();
    _speech.addListener(() {
      setState(() {
        _recognizedText = _speech.speechResult;
        if (_recognizedText.isNotEmpty) {
          _controller.text = _recognizedText;
        }
      });
    });
  }

  void _addWelcomeMessage() {
    _conversation.add({
      'role': 'assistant',
      'text': "Let's create a task together! Describe what you need to do, set priority and due date, and I'll help you break it down into manageable tasks. You can type or use the microphone to speak your task.",
    });
  }

  Future<void> _loadUserTags() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.userId)
          .get();
      
      final List<dynamic> tags = snap.data()?['tags'] ?? [];
      setState(() {
        _userTags = tags.cast<String>();
        _loadingTags = false;
      });
    } catch (_) {
      setState(() => _loadingTags = false);
    }
  }

  void _startListening() {
    if (!_speech.speechEnabled) {
      _showError('Speech recognition is not available on this device');
      return;
    }

    _speech.startListening();
  }

  void _stopListening() {
    _speech.stop();
    // Auto-send if we have text
    if (_recognizedText.trim().isNotEmpty) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (_controller.text.trim().isNotEmpty && mounted) {
          _sendMessage();
        }
      });
    }
  }

  void _toggleListening() {
    if (_speech.isListening) {
      _stopListening();
    } else {
      _startListening();
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _addMessage('user', text);
    _controller.clear();
    setState(() {
      _thinking = true;
      _showInputOptions = false;
      _recognizedText = '';
    });

    try {
      final prompt = _buildTaskCreationPrompt(text);
      final response = await gemini.generateContent([Content.text(prompt)]);
      final aiResponse = response.text?.trim() ?? 'Sorry, I could not process that.';

      _parseTasksFromAIResponse(aiResponse);
      
      String motivationalText = _extractMotivationalText(aiResponse);
      
      _addMessage('assistant', motivationalText);
      
      if (_generatedTasks.isNotEmpty) {
        _addTaskBlocksToChat();
      }
      
      setState(() => _thinking = false);
    } catch (e) {
      _addMessage('assistant', 'Sorry, there was an error. Please try again.');
      setState(() => _thinking = false);
    }
  }

  String _extractMotivationalText(String aiResponse) {
    final singleTaskIndex = aiResponse.indexOf('SINGLE_TASK');
    final multipleTasksIndex = aiResponse.indexOf('MULTIPLE_TASKS');
    
    int taskStartIndex = -1;
    if (singleTaskIndex != -1) {
      taskStartIndex = singleTaskIndex;
    } else if (multipleTasksIndex != -1) {
      taskStartIndex = multipleTasksIndex;
    }
    
    if (taskStartIndex != -1) {
      return aiResponse.substring(0, taskStartIndex).trim();
    }
    
    return aiResponse;
  }

  String _buildTaskCreationPrompt(String userInput) {
    final now = DateTime.now();
    final daysUntilDue = _selectedDueDate != null 
        ? _selectedDueDate!.difference(now).inDays 
        : 7;
    
    String dueDateContext = '';
    if (_selectedDueDate != null) {
      final formattedDate = DateFormat('MMMM d, yyyy').format(_selectedDueDate!);
      if (daysUntilDue <= 1) {
        dueDateContext = 'URGENT: Due tomorrow or today! Need to complete quickly.';
      } else if (daysUntilDue <= 3) {
        dueDateContext = 'Due in $daysUntilDue days - relatively soon, need efficient planning.';
      } else if (daysUntilDue <= 7) {
        dueDateContext = 'Due in $daysUntilDue days - good timeframe for balanced task breakdown.';
      } else {
        dueDateContext = 'Due in $daysUntilDue days - plenty of time for gradual progress.';
      }
    }

    return '''
You are a task creation assistant. The user wants to create a task: "$userInput"

Priority: ${_selectedPriority.name.toUpperCase()}
Due: ${_selectedDueDate != null ? DateFormat('MMM d').format(_selectedDueDate!) : 'Not set'}
$dueDateContext

TASK STRATEGY:
- Close deadline (1-3 days): 1-2 tasks, shorter durations
- Moderate (4-7 days): 2-3 balanced tasks  
- Far deadline (8+ days): 3-4 smaller tasks
- Simple tasks: Keep as single task
- High priority: Focus on critical path
- Low priority: More relaxed timing

Provide a brief, encouraging explanation of your approach, then format:

For single task:
SINGLE_TASK
Title: [Task Title]
Duration: [Number] minutes
Priority: [low/medium/high]
Description: [Brief description]

For multiple tasks:
MULTIPLE_TASKS
Task 1:
Title: [Task Title]
Duration: [Number] minutes
Priority: [low/medium/high]
Description: [Brief description]

Task 2:
Title: [Task Title]
Duration: [Number] minutes
Priority: [low/medium/high]
Description: [Brief description]

Keep response concise but motivational. Focus on practical advice.

User context:
- Tags: ${widget.userTags ?? 'Not specified'}
- Hours: ${widget.workingHours ?? '9-5'}
''';
  }

  void _parseTasksFromAIResponse(String response) {
    _generatedTasks.clear();
    
    try {
      if (response.contains('SINGLE_TASK')) {
        final task = _parseSingleTask(response);
        if (task != null) {
          _generatedTasks.add(task);
        }
      } else if (response.contains('MULTIPLE_TASKS')) {
        final tasks = _parseMultipleTasks(response);
        _generatedTasks.addAll(tasks);
      }
    } catch (e) {
      print('Error parsing tasks: $e');
    }
  }

  Task? _parseSingleTask(String response) {
    try {
      final lines = response.split('\n');
      String? title, duration, priority, description;
      
      for (int i = 0; i < lines.length; i++) {
        final line = lines[i].trim();
        if (line.startsWith('Title:')) {
          title = line.substring(6).trim();
        } else if (line.startsWith('Duration:')) {
          duration = line.substring(9).replaceAll('minutes', '').trim();
        } else if (line.startsWith('Priority:')) {
          priority = line.substring(9).trim();
        } else if (line.startsWith('Description:')) {
          description = line.substring(12).trim();
        }
      }
      
      if (title != null && duration != null) {
        return Task(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          title: title,
          desc: description ?? '',
          durationMin: int.tryParse(duration) ?? 30,
          deadline: _selectedDueDate ?? DateTime.now().add(const Duration(days: 1)),
          priority: _parsePriority(priority ?? 'medium'),
          uid: widget.userId,
          status: TaskStatus.toStart,
          tag: '',
          createdAt: DateTime.now(),
        );
      }
    } catch (e) {
      print('Error parsing single task: $e');
    }
    return null;
  }

  List<Task> _parseMultipleTasks(String response) {
    final tasks = <Task>[];
    try {
      final sections = response.split('Task ');
      for (final section in sections) {
        if (section.trim().isEmpty || !section.contains('Title:')) continue;
        
        final lines = section.split('\n');
        String? title, duration, priority, description;
        
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('Title:')) {
            title = trimmed.substring(6).trim();
          } else if (trimmed.startsWith('Duration:')) {
            duration = trimmed.substring(9).replaceAll('minutes', '').trim();
          } else if (trimmed.startsWith('Priority:')) {
            priority = trimmed.substring(9).trim();
          } else if (trimmed.startsWith('Description:')) {
            description = trimmed.substring(12).trim();
          }
        }
        
        if (title != null && duration != null) {
          tasks.add(Task(
            id: '${DateTime.now().millisecondsSinceEpoch}_${tasks.length}',
            title: title,
            desc: description ?? '',
            durationMin: int.tryParse(duration) ?? 30,
            deadline: _selectedDueDate ?? DateTime.now().add(const Duration(days: 1)),
            priority: _parsePriority(priority ?? 'medium'),
            uid: widget.userId,
            status: TaskStatus.toStart,
            tag: '',
            createdAt: DateTime.now(),
          ));
        }
      }
    } catch (e) {
      print('Error parsing multiple tasks: $e');
    }
    return tasks;
  }

  Priority _parsePriority(String priority) {
    final lower = priority.toLowerCase();
    if (lower.contains('high')) return Priority.high;
    if (lower.contains('low')) return Priority.low;
    return Priority.medium;
  }

  void _addMessage(String role, String text) {
    setState(() {
      _conversation.add({'role': role, 'text': text});
    });
  }

  void _addTaskBlocksToChat() {
    setState(() {
      _conversation.add({
        'role': 'assistant',
        'type': 'task_blocks',
        'tasks': List<Task>.from(_generatedTasks),
      });
    });
  }

  Future<void> _confirmTasks() async {
    if (_loadingTags) return;

    final shouldProceed = await _showFinalConfirmationDialog();
    if (shouldProceed ?? false) {
      await _saveTasksToFirestore();
      Navigator.pop(context, _generatedTasks);
    }
  }

  Future<bool?> _showFinalConfirmationDialog() {
    DateTime selectedDeadline = _selectedDueDate ?? DateTime.now().add(const Duration(days: 1));
    String selectedTag = '';

    return showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(_generatedTasks.length == 1 ? 'Confirm Task' : 'Confirm Tasks'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ..._generatedTasks.asMap().entries.map((entry) {
                      final task = entry.value;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: Icon(
                            _getPriorityIcon(task.priority),
                            color: _getPriorityColor(task.priority),
                          ),
                          title: Text(task.title),
                          subtitle: Text('${task.durationMin} min • ${task.priority.name}'),
                        ),
                      );
                    }),
                    const SizedBox(height: 16),
                    
                    const Text('Tag for all tasks:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _buildTagChips(selectedTag, (tag) {
                      setDialogState(() => selectedTag = tag);
                    }),
                    const SizedBox(height: 16),
                    
                    const Text('Due date for all tasks:', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(DateFormat('EEE, MMM d, yyyy').format(selectedDeadline)),
                      trailing: const Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: selectedDeadline,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365)),
                        );
                        if (picked != null) {
                          setDialogState(() => selectedDeadline = picked);
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () {
                    for (int i = 0; i < _generatedTasks.length; i++) {
                      _taskTags[i] = selectedTag;
                      _taskDeadlines[i] = selectedDeadline;
                    }
                    Navigator.pop(context, true);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF74EC7A),
                  ),
                  child: const Text('ADD TASK(S)'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildTagChips(String selectedTag, Function(String) onTagSelected) {
    if (_loadingTags) {
      return const CircularProgressIndicator(strokeWidth: 2);
    }

    return Wrap(
      spacing: 8,
      children: [
        ChoiceChip(
          label: const Text('No tag'),
          selected: selectedTag == '',
          selectedColor: Colors.blue.shade100,
          onSelected: (_) => onTagSelected(''),
        ),
        ..._userTags.map(
          (t) => ChoiceChip(
            label: Text(t),
            selected: selectedTag == t,
            selectedColor: Colors.blue.shade100,
            onSelected: (_) => onTagSelected(t),
          ),
        ),
      ],
    );
  }

  Future<void> _saveTasksToFirestore() async {
    final batch = FirebaseFirestore.instance.batch();
    
    for (int i = 0; i < _generatedTasks.length; i++) {
      final task = _generatedTasks[i];
      
      final finalTask = Task(
        id: task.id,
        title: task.title,
        desc: task.desc,
        durationMin: task.durationMin,
        deadline: _taskDeadlines[i],
        priority: task.priority,
        uid: task.uid,
        status: task.status,
        tag: _taskTags[i] ?? '',
        createdAt: task.createdAt,
      );

      final taskRef = FirebaseFirestore.instance
          .collection('tasks')
          .doc(finalTask.id);
      
      batch.set(taskRef, finalTask.toJson());
    }
    
    await batch.commit();
  }

  Widget _buildTaskBlocks(List<Task> tasks) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 8),
            child: Text(
              tasks.length == 1 
                  ? 'Here\'s your task ready to go! 🚀'
                  : 'Your ${tasks.length} manageable tasks:',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          ...tasks.asMap().entries.map((entry) {
            final index = entry.key;
            final task = entry.value;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(
                  _getPriorityIcon(task.priority),
                  color: _getPriorityColor(task.priority),
                ),
                title: Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (task.desc.isNotEmpty)
                      Text(
                        task.desc,
                        style: const TextStyle(fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${task.durationMin} min • ${task.priority.name} priority',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.edit, size: 18),
                  onPressed: () => _editTaskInChat(index, task),
                ),
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _editAllTasks,
                    child: const Text('Modify All'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _confirmTasks,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF74EC7A),
                    ),
                    child: const Text('Add Task(s)'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getPriorityIcon(Priority priority) {
    switch (priority) {
      case Priority.high:
        return Icons.flag;
      case Priority.medium:
        return Icons.flag_outlined;
      case Priority.low:
        return Icons.outlined_flag;
    }
  }

  Color _getPriorityColor(Priority priority) {
    switch (priority) {
      case Priority.high:
        return Colors.red;
      case Priority.medium:
        return Colors.orange;
      case Priority.low:
        return Colors.green;
    }
  }

  void _editTaskInChat(int taskIndex, Task task) {
    final titleController = TextEditingController(text: task.title);
    final durationController = TextEditingController(text: task.durationMin.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Task'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              TextField(
                controller: durationController,
                decoration: const InputDecoration(labelText: 'Duration (min)'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final newTitle = titleController.text.trim();
              final newDuration = int.tryParse(durationController.text) ?? task.durationMin;
              
              if (newTitle.isNotEmpty) {
                setState(() {
                  _generatedTasks[taskIndex] = _createUpdatedTask(
                    task, 
                    newTitle, 
                    newDuration
                  );
                  _updateTaskBlocksInChat();
                });
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _updateTaskBlocksInChat() {
    for (int i = 0; i < _conversation.length; i++) {
      if (_conversation[i]['type'] == 'task_blocks') {
        setState(() {
          _conversation[i]['tasks'] = List<Task>.from(_generatedTasks);
        });
        break;
      }
    }
  }

  void _editAllTasks() {
    setState(() {
      _conversation.removeWhere((msg) => msg['type'] == 'task_blocks');
    });
  }

  Task _createUpdatedTask(Task originalTask, String newTitle, int newDuration) {
    return Task(
      id: originalTask.id,
      title: newTitle,
      desc: originalTask.desc,
      durationMin: newDuration,
      deadline: originalTask.deadline,
      priority: originalTask.priority,
      uid: originalTask.uid,
      status: originalTask.status,
      tag: originalTask.tag,
      createdAt: originalTask.createdAt,
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final role = message['role'];
    final text = message['text'];
    final type = message['type'];
    final tasks = message['tasks'];
    final isUser = role == 'user';
    
    if (type == 'task_blocks' && tasks != null) {
      return _buildTaskBlocks(tasks);
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser)
            const CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xFF74EC7A),
              child: Icon(Icons.auto_awesome, size: 18, color: Colors.white),
            ),
          if (!isUser) const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isUser ? const Color(0xFF74EC7A) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 8),
          if (isUser)
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.grey,
              child: Icon(Icons.person, size: 18, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _inputSection() {
    return SafeArea(
      child: Column(
        children: [
          if (_showInputOptions) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              color: Colors.grey[50],
              child: Column(
                children: [
                  Row(
                    children: [
                      const Text('Priority:', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 16),
                      ChoiceChip(
                        label: const Text('High'),
                        selected: _selectedPriority == Priority.high,
                        selectedColor: Colors.red.shade100,
                        onSelected: (_) => setState(() => _selectedPriority = Priority.high),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Medium'),
                        selected: _selectedPriority == Priority.medium,
                        selectedColor: Colors.orange.shade100,
                        onSelected: (_) => setState(() => _selectedPriority = Priority.medium),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Low'),
                        selected: _selectedPriority == Priority.low,
                        selectedColor: Colors.green.shade100,
                        onSelected: (_) => setState(() => _selectedPriority = Priority.low),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text('Due Date:', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 16),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _selectedDueDate ?? DateTime.now().add(const Duration(days: 1)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setState(() => _selectedDueDate = picked);
                            }
                          },
                          child: Text(
                            _selectedDueDate != null 
                                ? DateFormat('MMM d, yyyy').format(_selectedDueDate!)
                                : 'Select due date',
                            style: TextStyle(
                              color: _selectedDueDate != null ? Colors.black : Colors.grey,
                            ),
                          ),
                        ),
                      ),
                      if (_selectedDueDate != null) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _selectedDueDate = null),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    _showInputOptions ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: const Color(0xFF74EC7A),
                  ),
                  onPressed: () => setState(() => _showInputOptions = !_showInputOptions),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Stack(
                    children: [
                      TextField(
                        controller: _controller,
                        decoration: InputDecoration(
                          hintText: _speech.isListening ? "Listening...." : 'Describe your task...',
                          filled: true,
                          fillColor: _speech.isListening ? Colors.blue.shade50 : Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(24),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                      if (_speech.isListening)
                        Positioned(
                          right: 8,
                          top: 0,
                          bottom: 0,
                          child: Icon(
                            Icons.record_voice_over,
                            color: Colors.red,
                            size: 20,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _speech.speechEnabled
                    ? AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        child: _speech.isListening 
                            ? FloatingActionButton(
                                mini: true,
                                backgroundColor: Colors.red,
                                onPressed: _toggleListening,
                                child: const Icon(Icons.mic, color: Colors.white),
                              )
                            : FloatingActionButton(
                                mini: true,
                                backgroundColor: const Color(0xFF74EC7A),
                                onPressed: _toggleListening,
                                child: const Icon(Icons.mic_none, color: Colors.white),
                              ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.mic_off, color: Colors.grey),
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Speech recognition is not available'),
                              backgroundColor: Colors.orange,
                            ),
                          );
                        },
                      ),
                const SizedBox(width: 8),
                FloatingActionButton(
                  mini: true,
                  backgroundColor: const Color(0xFF74EC7A),
                  onPressed: _sendMessage,
                  child: const Icon(Icons.send, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Task with AI'),
        backgroundColor: const Color(0xFF74EC7A),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _conversation.length,
              itemBuilder: (context, index) {
                final message = _conversation[index];
                return _buildMessageBubble(message);
              },
            ),
          ),
          if (_thinking) const LinearProgressIndicator(),
          _inputSection(),
        ],
      ),
    );
  }
}