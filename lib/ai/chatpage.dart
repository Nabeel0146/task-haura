import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Add this import
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:taskhaura/ai/ai_taskCREATION.dart';
import 'package:taskhaura/ai/schedulepage.dart';
import 'package:taskhaura/models/task.dart';
import '../main.dart';
import '../screens/addtask.dart';

class ChatPage extends StatefulWidget {
  final List<Task> userTasks;
  final Function(Task)? onTaskAdded;
  
  const ChatPage({
    super.key, 
    required this.userTasks, 
    this.onTaskAdded,
    // Remove userId from constructor
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _controller = TextEditingController();
  final List<Map<String, dynamic>> _history = [];
  bool _thinking = false;

  String? _tags;
  String? _workingHours;
  String? _userId; // Store userId internally

  @override
  void initState() {
    super.initState();
    _addWelcome();
    _loadUserContext();
    _getCurrentUserId(); // Get user ID when page initializes
  }

  // Method to get current user ID
  void _getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      setState(() {
        _userId = user.uid;
      });
    }
  }

  Future<void> _loadUserContext() async {
    final pref = await SharedPreferences.getInstance();
    _tags = pref.getString('user_tags');
    _workingHours = pref.getString('user_working_hours');

    if (_tags != null && _workingHours != null) return;

    // Use the current user's ID to fetch their data
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .get();
    
    if (!snap.exists) return;
    final data = snap.data()!;

    _tags = ((data['tags'] ?? []) as List).join(', ');
    _workingHours = data['workingHours'] ?? '9:00 AM – 5:00 PM';

    await pref.setString('user_tags', _tags!);
    await pref.setString('user_working_hours', _workingHours!);
  }

  void _addWelcome() {
    _history.add({
      'role': 'assistant',
      'text': 'Hi 👋  Ask me anything about your day!',
    });
  }

  String _to12(String txt) {
    final reg24 = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?\b');
    return txt.replaceAllMapped(reg24, (m) {
      int h = int.parse(m.group(1)!);
      final min = m.group(2)!;
      final am = h < 12 ? 'AM' : 'PM';
      h = h > 12 ? h - 12 : (h == 0 ? 12 : h);
      return '$h:$min $am';
    });
  }

  bool _isPlanningRequest(String text) {
    final lower = text.toLowerCase();
    return lower.contains(RegExp(
        r'\b(plan|schedule|suggest|advice|organise|organize|today|tomorrow|day|task|time)\b'));
  }

  Future<String> _buildPrompt(String userText) async {
    final buffer = StringBuffer()
      ..writeln('You are a friendly human productivity buddy.')
      ..writeln('Reply in one short, warm sentence like a caring friend.');

    if (_isPlanningRequest(userText) &&
        _tags != null &&
        _workingHours != null) {
      buffer
        ..writeln('')
        ..writeln('Context about the user:')
        ..writeln('- Interests / categories: $_tags')
        ..writeln('- Working hours: $_workingHours (weekdays)')
        ..writeln('')
        ..writeln('Use this context ONLY if relevant to give better suggestions.');
    }

    buffer..writeln('')..writeln('User: $userText');
    return buffer.toString();
  }

  Future<void> _sendChatMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _addBubble('user', text);
    _controller.clear();
    setState(() => _thinking = true);

    final prompt = await _buildPrompt(text);
    final resp = await gemini.generateContent([Content.text(prompt)]);
    final reply = _to12(resp.text?.trim() ?? 'Sorry, I didn\'t catch that.');
    _addBubble('assistant', reply);
    setState(() => _thinking = false);
  }

  void _handleChip(Task t) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AiSchedulePage(
          task: t,
          userTasks: widget.userTasks,
        ),
      ),
    );
  }

  void _handleChipWithPrompt(Task t) {
    final prompt = 'Which is the best time to schedule "${t.title}" (${t.durationMin} minutes)? '
        'Please consider my working hours ($_workingHours) and interests ($_tags) '
        'to provide detailed advice and suggest the optimal time slot.';
    
    _controller.text = prompt;
    _sendChatMessage();
  }

  void _addBubble(String role, String txt) {
    if (txt.isEmpty) return;
    setState(() => _history.add({'role': role, 'text': txt}));
  }

  // New method for AI task creation
  void _createTaskWithAI() async {
    if (_userId == null) {
      _showErrorMessage('Please sign in to create tasks');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AITaskCreationPage(
          userTags: _tags,
          workingHours: _workingHours,
          userId: _userId!, // Use the internal userId
        ),
      ),
    );

    // Handle the returned task(s) from AI task creation
    if (result != null && widget.onTaskAdded != null) {
      if (result is Task) {
        widget.onTaskAdded!(result);
        _showSuccessMessage('Task "${result.title}" added successfully!');
      } else if (result is List<Task>) {
        for (final task in result) {
          widget.onTaskAdded!(task);
        }
        _showSuccessMessage('${result.length} tasks added successfully!');
      }
    }
  }

  void _showSuccessMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showErrorMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  // New method for manual task creation
  void _createManualTask() async {
    if (_userId == null) {
      _showErrorMessage('Please sign in to create tasks');
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTaskPage(uid: _userId!), // Use the internal userId
      ),
    );

    if (result != null && widget.onTaskAdded != null) {
      widget.onTaskAdded!(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(),
        const Divider(),
        if (widget.userTasks.isNotEmpty) ...[
          _chips(),
          const Divider(),
        ],
        Expanded(child: _historyList()),
        _taskCreationButtons(),
        if (_thinking) const LinearProgressIndicator(),
        _inputBar(),
      ],
    );
  }

  Widget _header() {
    return ListTile(
      leading: const Icon(Icons.smart_toy, color: Color(0xFF74EC7A)),
      title: const Text('AI Assistant'),
      trailing: IconButton(
        icon: const Icon(Icons.close), 
        onPressed: () => Navigator.of(context).pop()
      ),
    );
  }

  Widget _chips() {
    return SizedBox(
      height: 60,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: widget.userTasks
            .map((t) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(
                    label: Text(t.title,
                        style: const TextStyle(color: Colors.black87, fontSize: 12)),
                    backgroundColor: Colors.white,
                    onPressed: () => _handleChip(t),
                  ),
                ))
            .toList(),
      ),
    );
  }

  // New task creation buttons widget
  Widget _taskCreationButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.auto_awesome, size: 18),
              label: const Text('Create with AI'),
              onPressed: _createTaskWithAI,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF74EC7A),
                side: const BorderSide(color: Color(0xFF74EC7A)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Manual'),
              onPressed: _createManualTask,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey[700],
                side: BorderSide(color: Colors.grey[700]!),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyList() {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: _history.map((item) => _bubble(item['role'], item['text'])).toList(),
    );
  }

  Widget _bubble(String role, String text) {
    final isMe = role == 'user';
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF74EC7A) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(text,
            style: TextStyle(color: isMe ? Colors.white : Colors.black87)),
      ),
    );
  }

  Widget _inputBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Ask or tap a task…',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                onSubmitted: (_) => _sendChatMessage(),
              ),
            ),
            const SizedBox(width: 8),
            FloatingActionButton(
              mini: true,
              backgroundColor: const Color(0xFF74EC7A),
              onPressed: _sendChatMessage,
              child: const Icon(Icons.send, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}