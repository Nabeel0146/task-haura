import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:percent_indicator/percent_indicator.dart';

class ProductivityPage extends StatefulWidget {
  const ProductivityPage({super.key});

  @override
  State<ProductivityPage> createState() => _ProductivityPageState();
}

class _ProductivityPageState extends State<ProductivityPage> {
  String? _userId;
  List<TaskStats> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userId = prefs.getString('userId');
    });
    
    if (_userId != null) {
      await _loadTasks();
    }
    setState(() => _loading = false);
  }

  Future<void> _loadTasks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('tasks')
        .where('uid', isEqualTo: _userId)
        .get();

    final tasks = snapshot.docs.map((doc) {
      final data = doc.data();
      return TaskStats(
        id: doc.id,
        title: data['title'] ?? '',
        status: _parseStatus(data['status']),
        tag: data['tag'] ?? '',
        durationMin: data['durationMin'] ?? 0,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      );
    }).toList();

    setState(() => _tasks = tasks);
  }

  TaskStatus _parseStatus(String status) {
    switch (status) {
      case 'completed': return TaskStatus.completed;
      case 'inProgress': return TaskStatus.inProgress;
      default: return TaskStatus.toStart;
    }
  }

  ProductivityStats get _stats {
    final today = DateTime.now();
    final todayTasks = _tasks.where((task) => 
        task.createdAt.year == today.year &&
        task.createdAt.month == today.month &&
        task.createdAt.day == today.day
    ).toList();

    final completedToday = todayTasks.where((t) => t.status == TaskStatus.completed).length;
    final totalToday = todayTasks.length;
    final completionRate = totalToday > 0 ? completedToday / totalToday : 0.0;

    // Calculate tag distribution
    final tagStats = <String, int>{};
    for (final task in _tasks) {
      if (task.tag.isNotEmpty) {
        tagStats[task.tag] = (tagStats[task.tag] ?? 0) + 1;
      }
    }

    // Calculate peak hours (mock data - you can implement real tracking)
    final peakHours = _calculatePeakHours();

    return ProductivityStats(
      totalTasks: _tasks.length,
      completedTasks: _tasks.where((t) => t.status == TaskStatus.completed).length,
      inProgressTasks: _tasks.where((t) => t.status == TaskStatus.inProgress).length,
      todayCompletionRate: completionRate,
      todayCompleted: completedToday,
      todayTotal: totalToday,
      tagDistribution: tagStats,
      peakHours: peakHours,
      averageFocusHours: 3.2, // Mock data
      weeklyCompletionRate: 0.75, // Mock data
    );
  }

  Map<String, int> _calculatePeakHours() {
    // Mock peak hours data - replace with actual time tracking
    return {
      'Morning (6-12)': 12,
      'Afternoon (12-18)': 18,
      'Evening (18-24)': 8,
      'Night (0-6)': 2,
    };
  }

  String _getAISuggestion() {
    final stats = _stats;
    
    if (stats.todayCompletionRate < 0.3) {
      return "Try breaking down larger tasks into smaller, manageable chunks. Start with the most important task first.";
    } else if (stats.todayCompletionRate < 0.7) {
      return "Great progress! Consider using the Pomodoro technique (25min work + 5min break) to maintain focus.";
    } else {
      return "Excellent productivity! Keep up the momentum. Remember to take regular breaks to avoid burnout.";
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = _stats;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildTodayProgress(stats),
            const SizedBox(height: 20),
            _buildAISuggestion(),
            const SizedBox(height: 20),
            _buildProductivityInsights(stats),
            const SizedBox(height: 20),
            _buildTagDistribution(stats),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Productivity Dashboard',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Track your progress and optimize your workflow',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildTodayProgress(ProductivityStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Today's Progress",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  "${stats.todayCompleted}/${stats.todayTotal} tasks",
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.green,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            CircularPercentIndicator(
              radius: 60,
              lineWidth: 12,
              percent: stats.todayCompletionRate,
              center: Text(
                "${(stats.todayCompletionRate * 100).toStringAsFixed(0)}%",
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              progressColor: Colors.green,
              backgroundColor: Colors.green.shade100,
              circularStrokeCap: CircularStrokeCap.round,
            ),
            const SizedBox(height: 16),
            if (stats.todayCompletionRate < 0.5)
              Text(
                "Keep going! You're making progress.",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.orange.shade700,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              )
            else if (stats.todayCompletionRate < 0.8)
              Text(
                "Good work! You're on track.",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.blue.shade700,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              )
            else
              Text(
                "Excellent! You're crushing it!",
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.green.shade700,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAISuggestion() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.green.shade50, Colors.lightGreen.shade50],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.green.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Text(
                'AI Productivity Tip',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.green.shade800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _getAISuggestion(),
            style: TextStyle(
              fontSize: 15,
              color: Colors.green.shade700,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductivityInsights(ProductivityStats stats) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Productivity Insights',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 16),
            _buildInsightRow(
              Icons.access_time,
              'Energy Peak Time',
              _findPeakHour(stats.peakHours),
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.timer,
              'Average Focus Hours',
              '${stats.averageFocusHours.toStringAsFixed(1)} hours/day',
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.trending_up,
              'Weekly Completion Rate',
              '${(stats.weeklyCompletionRate * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.check_circle,
              'Overall Task Completion',
              '${stats.completedTasks}/${stats.totalTasks} tasks',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade600),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              color: Colors.grey[700],
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.blue.shade700,
          ),
        ),
      ],
    );
  }

  String _findPeakHour(Map<String, int> peakHours) {
    if (peakHours.isEmpty) return 'Not enough data';
    final maxEntry = peakHours.entries.reduce(
        (a, b) => a.value > b.value ? a : b);
    return '${maxEntry.key} (${maxEntry.value} tasks)';
  }

  Widget _buildTagDistribution(ProductivityStats stats) {
    if (stats.tagDistribution.isEmpty) {
      return Card(
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: Text(
              'No tags data available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Task Distribution by Tags',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 16),
            ...stats.tagDistribution.entries.map((entry) => 
              _buildTagBar(entry.key, entry.value, stats.totalTasks)
            ).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildTagBar(String tag, int count, int totalTasks) {
    final percentage = totalTasks > 0 ? count / totalTasks : 0.0;
    final colors = [Colors.blue, Colors.green, Colors.orange, Colors.purple, Colors.red];
    final color = colors[tag.hashCode % colors.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tag.isEmpty ? 'No Tag' : tag,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey[700],
                ),
              ),
              Text(
                '$count tasks',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: percentage,
            backgroundColor: color.withOpacity(0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
          ),
          const SizedBox(height: 4),
          Text(
            '${(percentage * 100).toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }
}

// Models
enum TaskStatus { toStart, inProgress, completed }

class TaskStats {
  final String id;
  final String title;
  final TaskStatus status;
  final String tag;
  final int durationMin;
  final DateTime createdAt;
  final DateTime? completedAt;

  TaskStats({
    required this.id,
    required this.title,
    required this.status,
    required this.tag,
    required this.durationMin,
    required this.createdAt,
    this.completedAt,
  });
}

class ProductivityStats {
  final int totalTasks;
  final int completedTasks;
  final int inProgressTasks;
  final double todayCompletionRate;
  final int todayCompleted;
  final int todayTotal;
  final Map<String, int> tagDistribution;
  final Map<String, int> peakHours;
  final double averageFocusHours;
  final double weeklyCompletionRate;

  ProductivityStats({
    required this.totalTasks,
    required this.completedTasks,
    required this.inProgressTasks,
    required this.todayCompletionRate,
    required this.todayCompleted,
    required this.todayTotal,
    required this.tagDistribution,
    required this.peakHours,
    required this.averageFocusHours,
    required this.weeklyCompletionRate,
  });
}