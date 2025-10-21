import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:taskhaura/main.dart';

class ProductivityPage extends StatefulWidget {
  const ProductivityPage({super.key});

  @override
  State<ProductivityPage> createState() => _ProductivityPageState();
}

class _ProductivityPageState extends State<ProductivityPage> {
  final User? _user = FirebaseAuth.instance.currentUser;
  List<TaskStats> _tasks = [];
  List<DoneTask> _doneTasks = [];
  List<SkippedTask> _skippedTasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (_user == null) {
      setState(() => _loading = false);
      return;
    }

    await Future.wait([
      _loadTasks(),
      _loadDoneTasks(),
      _loadSkippedTasks(),
    ]);
    
    setState(() => _loading = false);
  }

  Future<void> _loadTasks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('tasks')
        .where('uid', isEqualTo: _user!.uid)
        .get();

    final tasks = snapshot.docs.map((doc) {
      final data = doc.data();
      return TaskStats(
        id: doc.id,
        title: data['title'] ?? '',
        status: _parseStatus(data['status']),
        tag: data['tag'] ?? '',
        durationMin: (data['durationMin'] as num?)?.toInt() ?? 0,
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      );
    }).toList();

    setState(() => _tasks = tasks);
  }

  Future<void> _loadDoneTasks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('doneTasks')
        .where('uid', isEqualTo: _user!.uid)
        .get();

    final doneTasks = snapshot.docs.map((doc) {
      final data = doc.data();
      return DoneTask(
        id: doc.id,
        title: data['title'] ?? '',
        durationMin: (data['durationMin'] as num?)?.toInt() ?? 0,
        completedAt: (data['completedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        priority: data['priority'] ?? 'medium',
        scheduledStart: data['start'] ?? '',
      );
    }).toList();

    setState(() => _doneTasks = doneTasks);
  }

  Future<void> _loadSkippedTasks() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('deletedTasks')
        .where('uid', isEqualTo: _user!.uid)
        .get();

    final skippedTasks = snapshot.docs.map((doc) {
      final data = doc.data();
      return SkippedTask(
        id: doc.id,
        title: data['title'] ?? '',
        durationMin: (data['durationMin'] as num?)?.toInt() ?? 0,
        deletedAt: (data['deletedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        priority: data['priority'] ?? 'medium',
      );
    }).toList();

    setState(() => _skippedTasks = skippedTasks);
  }

  TaskStatus _parseStatus(String status) {
    switch (status) {
      case 'done': return TaskStatus.done;
      case 'onDoing': return TaskStatus.onDoing;
      default: return TaskStatus.toStart;
    }
  }

  ProductivityStats get _stats {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    // Today's tasks from doneTasks collection
    final todayDoneTasks = _doneTasks.where((task) {
      final taskDate = DateTime(task.completedAt.year, task.completedAt.month, task.completedAt.day);
      return taskDate == today;
    }).toList();

    final completedToday = todayDoneTasks.length;
    final totalToday = completedToday + _skippedTasks.where((task) {
      final taskDate = DateTime(task.deletedAt.year, task.deletedAt.month, task.deletedAt.day);
      return taskDate == today;
    }).length;

    final completionRate = totalToday > 0 ? completedToday / totalToday : 0.0;

    // Weekly stats
    final weekStart = today.subtract(Duration(days: today.weekday - 1));
    final weekDoneTasks = _doneTasks.where((task) {
      final taskDate = DateTime(task.completedAt.year, task.completedAt.month, task.completedAt.day);
      return taskDate.isAfter(weekStart.subtract(const Duration(days: 1)));
    }).toList();

    final weekSkippedTasks = _skippedTasks.where((task) {
      final taskDate = DateTime(task.deletedAt.year, task.deletedAt.month, task.deletedAt.day);
      return taskDate.isAfter(weekStart.subtract(const Duration(days: 1)));
    }).toList();

    final weeklyCompleted = weekDoneTasks.length;
    final weeklyTotal = weeklyCompleted + weekSkippedTasks.length;
    final weeklyCompletionRate = weeklyTotal > 0 ? weeklyCompleted / weeklyTotal : 0.0;

    // Calculate peak hours from done tasks
    final peakHours = _calculatePeakHours();

    // Calculate average focus hours (total completed task minutes / 60)
    final totalFocusMinutes = _doneTasks.fold(0, (sum, task) => sum + task.durationMin);
    final averageFocusHours = _doneTasks.isNotEmpty ? totalFocusMinutes / 60 / _doneTasks.length : 0.0;

    // Tag distribution from all tasks
    final tagStats = <String, int>{};
    for (final task in _tasks) {
      if (task.tag.isNotEmpty) {
        tagStats[task.tag] = (tagStats[task.tag] ?? 0) + 1;
      }
    }

    // Priority distribution from done tasks
    final priorityStats = <String, int>{};
    for (final task in _doneTasks) {
      priorityStats[task.priority] = (priorityStats[task.priority] ?? 0) + 1;
    }

    // Tag completion stats
    final tagCompletionStats = <String, TagCompletion>{};
    for (final task in _tasks) {
      if (task.tag.isNotEmpty) {
        if (!tagCompletionStats.containsKey(task.tag)) {
          tagCompletionStats[task.tag] = TagCompletion(total: 0, completed: 0);
        }
        tagCompletionStats[task.tag]!.total++;
        
        // Check if this task is completed (exists in doneTasks)
        final isCompleted = _doneTasks.any((doneTask) => doneTask.title == task.title);
        if (isCompleted) {
          tagCompletionStats[task.tag]!.completed++;
        }
      }
    }

    return ProductivityStats(
      totalTasks: _tasks.length,
      completedTasks: _doneTasks.length,
      skippedTasks: _skippedTasks.length,
      todayCompletionRate: completionRate,
      todayCompleted: completedToday,
      todayTotal: totalToday,
      weeklyCompletionRate: weeklyCompletionRate,
      weeklyCompleted: weeklyCompleted,
      weeklyTotal: weeklyTotal,
      tagDistribution: tagStats,
      priorityDistribution: priorityStats,
      peakHours: peakHours,
      averageFocusHours: averageFocusHours,
      totalFocusMinutes: totalFocusMinutes,
      tagCompletionStats: tagCompletionStats,
    );
  }

  Map<String, int> _calculatePeakHours() {
    final hourCounts = <int, int>{};
    
    for (final task in _doneTasks) {
      final hour = task.completedAt.hour;
      hourCounts[hour] = (hourCounts[hour] ?? 0) + 1;
    }

    // Convert to time ranges
    final peakHours = <String, int>{};
    for (int hour = 0; hour < 24; hour++) {
      final count = hourCounts[hour] ?? 0;
      String timeRange;
      if (hour < 6) timeRange = 'Night (12-6 AM)';
      else if (hour < 12) timeRange = 'Morning (6-12 AM)';
      else if (hour < 18) timeRange = 'Afternoon (12-6 PM)';
      else timeRange = 'Evening (6-12 PM)';
      
      peakHours[timeRange] = (peakHours[timeRange] ?? 0) + count;
    }

    return peakHours;
  }

  Future<String> _getAISuggestion() async {
    final stats = _stats;
    final completedCount = stats.completedTasks;
    final skippedCount = stats.skippedTasks;
    final todayRate = stats.todayCompletionRate;
    final weeklyRate = stats.weeklyCompletionRate;

    final prompt = '''
You are a productivity coach analyzing user task data.
Provide ONE short, actionable suggestion (max 20 words) based on this data:

Completed tasks: $completedCount
Skipped/deleted tasks: $skippedCount
Today's completion rate: ${(todayRate * 100).toStringAsFixed(0)}%
Weekly completion rate: ${(weeklyRate * 100).toStringAsFixed(0)}%
Peak productivity hours: ${_findPeakHour(stats.peakHours)}

Focus on the most important improvement area. Be encouraging but honest.
''';

    try {
      final resp = await gemini.generateContent([Content.text(prompt)]);
      return resp.text?.trim().replaceAll('\n', ' ') ?? 'Focus on completing your most important task first.';
    } catch (_) {
      // Fallback suggestions based on data
      if (todayRate < 0.3) {
        return "Start with your most important task. Break it into smaller steps.";
      } else if (todayRate < 0.7) {
        return "Great progress! Try the Pomodoro technique to maintain focus.";
      } else {
        return "Excellent work! Remember to take breaks to avoid burnout.";
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: Colors.grey[50],
        body: const Center(
          child: Text('Please sign in to view productivity insights'),
        ),
      );
    }

    final stats = _stats;

    return Scaffold(
      body: FutureBuilder<String>(
        future: _getAISuggestion(),
        builder: (context, snapshot) {
          final aiSuggestion = snapshot.data ?? 'Analyzing your productivity patterns...';
          
          return Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.fromARGB(255, 131, 245, 103), Colors.white],
              ),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 20),
                  _buildTodayProgress(stats),
                  const SizedBox(height: 20),
                   _buildTagCompletionProgress(stats), // New section
                   const SizedBox(height: 20),
                  
                  _buildAISuggestion(aiSuggestion),
                  const SizedBox(height: 20),
                  _buildProductivityInsights(stats),
                  const SizedBox(height: 20),
                  _buildTagDistribution(stats),
                  const SizedBox(height: 20),
                  _buildPriorityDistribution(stats),
                  const SizedBox(height: 20),
                 
                ],
              ),
            ),
          );
        },
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    color: Color(0xFF74EC7A),
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
                  color: Color(0xFF74EC7A),
                ),
              ),
              progressColor: const Color(0xFF74EC7A),
              backgroundColor: Colors.grey[200]!,
              circularStrokeCap: CircularStrokeCap.round,
            ),
            const SizedBox(height: 16),
            Text(
              _getTodayProgressMessage(stats.todayCompletionRate),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getTodayProgressMessage(double rate) {
    if (rate == 0) return "Start your day with one small task!";
    if (rate < 0.3) return "Every task completed is progress. Keep going!";
    if (rate < 0.7) return "Good momentum! You're building great habits.";
    if (rate < 1.0) return "Almost there! Finish strong.";
    return "Perfect day! You've completed all your tasks.";
  }

  Widget _buildAISuggestion(String suggestion) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.auto_awesome, color: Colors.purple.shade600, size: 20),
                const SizedBox(width: 8),
                Text(
                  'AI Productivity Tip',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              suggestion,
              style: TextStyle(
                fontSize: 15,
                color: Colors.grey[700],
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductivityInsights(ProductivityStats stats) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              'Most Productive Time',
              _findPeakHour(stats.peakHours),
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.timer,
              'Avg Focus per Task',
              '${stats.averageFocusHours.toStringAsFixed(1)} hours',
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.trending_up,
              'Weekly Completion',
              '${(stats.weeklyCompletionRate * 100).toStringAsFixed(0)}%',
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.check_circle,
              'Total Completed',
              '${stats.completedTasks} tasks',
            ),
            const SizedBox(height: 12),
            _buildInsightRow(
              Icons.skip_next,
              'Tasks Skipped',
              '${stats.skippedTasks} tasks',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightRow(IconData icon, String title, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF74EC7A)),
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
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF74EC7A),
          ),
        ),
      ],
    );
  }

  String _findPeakHour(Map<String, int> peakHours) {
    if (peakHours.isEmpty) return 'Not enough data';
    final maxEntry = peakHours.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${maxEntry.key}';
  }

  Widget _buildTagDistribution(ProductivityStats stats) {
    if (stats.tagDistribution.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text(
              'No tags data available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
              _buildDistributionBar(entry.key, entry.value, stats.totalTasks)
            ).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildPriorityDistribution(ProductivityStats stats) {
    if (stats.priorityDistribution.isEmpty) {
      return const SizedBox();
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Completed Tasks by Priority',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 16),
            ...stats.priorityDistribution.entries.map((entry) => 
              _buildDistributionBar(
                '${entry.key[0].toUpperCase()}${entry.key.substring(1)} Priority',
                entry.value,
                stats.completedTasks
              )
            ).toList(),
          ],
        ),
      ),
    );
  }

  // NEW SECTION: Tag Completion Progress with Vertical Bars
  Widget _buildTagCompletionProgress(ProductivityStats stats) {
    if (stats.tagCompletionStats.isEmpty) {
      return Card(
        
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Padding(
          padding: EdgeInsets.all(20),
          child: Center(
            child: Text(
              'No tag completion data available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tag Completion Progress',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Completed tasks vs total tasks for each tag',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            // Use Wrap for responsive layout
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: stats.tagCompletionStats.entries.map((entry) {
                final tag = entry.key;
                final completion = entry.value;
                final percentage = completion.total > 0 ? completion.completed / completion.total : 0.0;
                
                return _buildVerticalProgressBar(
                  tag: tag,
                  completed: completion.completed,
                  total: completion.total,
                  percentage: percentage,
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerticalProgressBar({
    required String tag,
    required int completed,
    required int total,
    required double percentage,
  }) {
    return Container(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Vertical progress bar container
          Container(
            width: 30,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(15),
            ),
            child: Stack(
              children: [
                // Progress fill
                Align(
                  alignment: Alignment.bottomCenter,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    width: 30,
                    height: 120 * percentage,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Color(0xFF74EC7A), Color(0xFF4CAF50)],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                // Percentage text in the middle of the bar
                Center(
                  child: Text(
                    '${(percentage * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Tag name
          Text(
            tag.isEmpty ? 'No Tag' : tag,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          // Task count
          Text(
            '$completed/$total',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDistributionBar(String label, int count, int total) {
    final percentage = total > 0 ? count / total : 0.0;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label.isEmpty ? 'No Tag' : label,
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
            backgroundColor: Colors.grey[200],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF74EC7A)),
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

// Updated Models
enum TaskStatus { toStart, onDoing, done }

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

class DoneTask {
  final String id;
  final String title;
  final int durationMin;
  final DateTime completedAt;
  final String priority;
  final String scheduledStart;

  DoneTask({
    required this.id,
    required this.title,
    required this.durationMin,
    required this.completedAt,
    required this.priority,
    required this.scheduledStart,
  });
}

class SkippedTask {
  final String id;
  final String title;
  final int durationMin;
  final DateTime deletedAt;
  final String priority;

  SkippedTask({
    required this.id,
    required this.title,
    required this.durationMin,
    required this.deletedAt,
    required this.priority,
  });
}

class TagCompletion {
  int total;
  int completed;

  TagCompletion({required this.total, required this.completed});
}

class ProductivityStats {
  final int totalTasks;
  final int completedTasks;
  final int skippedTasks;
  final double todayCompletionRate;
  final int todayCompleted;
  final int todayTotal;
  final double weeklyCompletionRate;
  final int weeklyCompleted;
  final int weeklyTotal;
  final Map<String, int> tagDistribution;
  final Map<String, int> priorityDistribution;
  final Map<String, int> peakHours;
  final double averageFocusHours;
  final int totalFocusMinutes;
  final Map<String, TagCompletion> tagCompletionStats;

  ProductivityStats({
    required this.totalTasks,
    required this.completedTasks,
    required this.skippedTasks,
    required this.todayCompletionRate,
    required this.todayCompleted,
    required this.todayTotal,
    required this.weeklyCompletionRate,
    required this.weeklyCompleted,
    required this.weeklyTotal,
    required this.tagDistribution,
    required this.priorityDistribution,
    required this.peakHours,
    required this.averageFocusHours,
    required this.totalFocusMinutes,
    required this.tagCompletionStats,
  });
}