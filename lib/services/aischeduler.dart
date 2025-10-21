import 'dart:convert';
import 'dart:developer' as dev;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/main.dart';
import 'package:taskhaura/models/task.dart';

class AiScheduler {
  /* ----------------------------------------------------------
   * 1. Get user preferences, tags, and interests from Firestore
   * ---------------------------------------------------------- */
  static Future<Map<String, dynamic>?> _getUserData(String uid) async {
    try {
      dev.log('🔍 Fetching user data for UID: $uid', name: 'AiScheduler');
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      
      if (userDoc.exists) {
        final data = userDoc.data();
        dev.log('✅ User data found:', name: 'AiScheduler');
        dev.log('   - Preferences: ${data?['preferences']}', name: 'AiScheduler');
        dev.log('   - Tags: ${data?['tags']}', name: 'AiScheduler');
        dev.log('   - Interests: ${data?['interests']}', name: 'AiScheduler');
        return {
          'preferences': data?['preferences'] as Map<String, dynamic>?,
          'tags': data?['tags'] as List<dynamic>?,
          'interests': data?['interests'] as List<dynamic>?,
        };
      } else {
        dev.log('❌ User document does not exist for UID: $uid', name: 'AiScheduler');
      }
    } catch (e) {
      dev.log('❌ Error fetching user data: $e', name: 'AiScheduler');
    }
    return null;
  }

  /* ----------------------------------------------------------
   * 2. Get task tags from Firestore
   * ---------------------------------------------------------- */
  static Future<List<String>?> _getTaskTags(String taskId, String uid) async {
    try {
      dev.log('🔍 Fetching task tags for task ID: $taskId', name: 'AiScheduler');
      final taskDoc = await FirebaseFirestore.instance
          .collection('tasks')
          .doc(taskId)
          .get();
      
      if (taskDoc.exists) {
        final data = taskDoc.data();
        final tags = data?['tags'] as List<dynamic>?;
        final tagList = tags?.map((tag) => tag.toString().toLowerCase()).toList();
        dev.log('✅ Task tags found: $tagList', name: 'AiScheduler');
        return tagList;
      } else {
        dev.log('❌ Task document does not exist for ID: $taskId', name: 'AiScheduler');
      }
    } catch (e) {
      dev.log('❌ Error fetching task tags: $e', name: 'AiScheduler');
    }
    return null;
  }

  /* ----------------------------------------------------------
   * 3. Parse working hours and sleep schedule
   * ---------------------------------------------------------- */
  static Map<String, String> _parseTimeRanges(Map<String, dynamic>? prefs) {
    String workingHours = '09:00-17:00'; // Default
    String sleepSchedule = '22:00-06:00'; // Default

    if (prefs != null) {
      dev.log('🔍 Parsing time ranges from preferences: $prefs', name: 'AiScheduler');
      
      // Parse working hours
      if (prefs['workingHours'] != null && prefs['workingHours'] != 'Flexible') {
        final wh = prefs['workingHours'].toString();
        dev.log('   - Raw working hours: $wh', name: 'AiScheduler');
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*–\s*(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(wh);
        if (match != null) {
          workingHours = '${_to24Hour(match.group(1)!, match.group(3)!)}-${_to24Hour(match.group(4)!, match.group(6)!)}';
          dev.log('   - Parsed working hours: $workingHours', name: 'AiScheduler');
        } else {
          dev.log('   - Could not parse working hours format', name: 'AiScheduler');
        }
      } else {
        dev.log('   - Using default working hours: $workingHours', name: 'AiScheduler');
      }

      // Parse sleep schedule
      if (prefs['sleepSchedule'] != null && prefs['sleepSchedule'] != 'Not set') {
        final ss = prefs['sleepSchedule'].toString();
        dev.log('   - Raw sleep schedule: $ss', name: 'AiScheduler');
        final match = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)\s*–\s*(\d{1,2}):(\d{2})\s*(AM|PM)').firstMatch(ss);
        if (match != null) {
          sleepSchedule = '${_to24Hour(match.group(1)!, match.group(3)!)}-${_to24Hour(match.group(4)!, match.group(6)!)}';
          dev.log('   - Parsed sleep schedule: $sleepSchedule', name: 'AiScheduler');
        } else {
          dev.log('   - Could not parse sleep schedule format', name: 'AiScheduler');
        }
      } else {
        dev.log('   - Using default sleep schedule: $sleepSchedule', name: 'AiScheduler');
      }
    } else {
      dev.log('📋 Using default time ranges (no preferences)', name: 'AiScheduler');
      dev.log('   - Working hours: $workingHours', name: 'AiScheduler');
      dev.log('   - Sleep schedule: $sleepSchedule', name: 'AiScheduler');
    }

    return {
      'workingHours': workingHours,
      'sleepSchedule': sleepSchedule,
    };
  }

  static String _to24Hour(String hour, String period) {
    int h = int.parse(hour);
    if (period == 'PM' && h != 12) h += 12;
    if (period == 'AM' && h == 12) h = 0;
    final result = '${h.toString().padLeft(2, '0')}:00';
    dev.log('   - Converted $hour $period to $result', name: 'AiScheduler');
    return result;
  }

  /* ----------------------------------------------------------
   * 4. Check if task is work-related using task tags and user interests
   * ---------------------------------------------------------- */
  static Future<bool> _isWorkRelatedTask(Task task) async {
    dev.log('🔍 Checking if task is work-related:', name: 'AiScheduler');
    dev.log('   - Task ID: ${task.id}', name: 'AiScheduler');
    dev.log('   - Task Title: ${task.title}', name: 'AiScheduler');
    dev.log('   - Task Description: ${task.desc}', name: 'AiScheduler');
    dev.log('   - Task UID: ${task.uid}', name: 'AiScheduler');
    
    try {
      // Get task tags from Firestore
      final taskTags = await _getTaskTags(task.id, task.uid);
      
      // Get user data including interests and tags
      final userData = await _getUserData(task.uid);
      final userInterests = userData?['interests'] as List<dynamic>?;
      final userTags = userData?['tags'] as List<dynamic>?;

      // Work-related identifiers
      final workTaskTags = ['work', 'work projects', 'college', 'student', 'office', 'job', 'professional'];
      final workUserInterests = ['Work Projects', 'Learning & Education'];
      
      dev.log('🔍 Work classification analysis:', name: 'AiScheduler');
      dev.log('   - Task tags: $taskTags', name: 'AiScheduler');
      dev.log('   - User interests: $userInterests', name: 'AiScheduler');
      dev.log('   - User tags: $userTags', name: 'AiScheduler');
      dev.log('   - Work keywords: $workTaskTags', name: 'AiScheduler');
      dev.log('   - Work interests: $workUserInterests', name: 'AiScheduler');

      // Check 1: Task has work-related tags
      if (taskTags != null && taskTags.isNotEmpty) {
        for (final tag in taskTags) {
          for (final workTag in workTaskTags) {
            if (tag.contains(workTag) || workTag.contains(tag)) {
              dev.log('✅ Task identified as WORK: Has work tag "$tag"', name: 'AiScheduler');
              return true;
            }
          }
        }
        dev.log('❌ No work-related tags found in task', name: 'AiScheduler');
      } else {
        dev.log('❌ No task tags found', name: 'AiScheduler');
      }

      // Check 2: User has work-related interests
      if (userInterests != null && userInterests.isNotEmpty) {
        for (final interest in userInterests) {
          final interestStr = interest.toString().toLowerCase();
          for (final workInterest in workUserInterests) {
            if (interestStr.contains(workInterest.toLowerCase()) || 
                workInterest.toLowerCase().contains(interestStr)) {
              dev.log('✅ Task identified as WORK: User has work interest "$interest"', name: 'AiScheduler');
              return true;
            }
          }
        }
        dev.log('❌ No work-related interests found in user data', name: 'AiScheduler');
      } else {
        dev.log('❌ No user interests found', name: 'AiScheduler');
      }

      // Check 3: User has work-related tags
      if (userTags != null && userTags.isNotEmpty) {
        for (final tag in userTags) {
          final tagStr = tag.toString().toLowerCase();
          for (final workTag in workTaskTags) {
            if (tagStr.contains(workTag) || workTag.contains(tagStr)) {
              dev.log('✅ Task identified as WORK: User has work tag "$tag"', name: 'AiScheduler');
              return true;
            }
          }
        }
        dev.log('❌ No work-related tags found in user data', name: 'AiScheduler');
      } else {
        dev.log('❌ No user tags found', name: 'AiScheduler');
      }

      // Check 4: Fallback - check task title/description for work keywords
      final title = task.title.toLowerCase();
      final desc = task.desc.toLowerCase();
      final workKeywords = ['work', 'college', 'office', 'job', 'project', 'meeting', 'client', 'professional'];
      
      dev.log('🔍 Checking title/description for work keywords:', name: 'AiScheduler');
      dev.log('   - Title (lowercase): $title', name: 'AiScheduler');
      dev.log('   - Description (lowercase): $desc', name: 'AiScheduler');
      
      for (final keyword in workKeywords) {
        if (title.contains(keyword) || desc.contains(keyword)) {
          dev.log('✅ Task identified as WORK: Contains keyword "$keyword"', name: 'AiScheduler');
          return true;
        }
      }
      dev.log('❌ No work keywords found in title/description', name: 'AiScheduler');

      dev.log('🎯 FINAL DECISION: Task identified as PERSONAL', name: 'AiScheduler');
      return false;
      
    } catch (e) {
      dev.log('❌ Error checking if task is work-related: $e', name: 'AiScheduler');
      return false;
    }
  }

  /* ----------------------------------------------------------
   * 5. Get blocked slots from existing schedule
   * ---------------------------------------------------------- */
  static Future<List<_BlockedSlot>> _blockedSlots({
    required String uid,
    required DateTime day,
  }) async {
    dev.log('🔍 Fetching blocked slots for UID: $uid, Date: ${DateFormat('yyyy-MM-dd').format(day)}', name: 'AiScheduler');
    
    final snap = await FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: DateFormat('yyyy-MM-dd').format(day))
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      dev.log('✅ No existing blocked slots found', name: 'AiScheduler');
      return [];
    }

    final blockedSlots = (snap.docs.first.data()['orderedTasks'] as List<dynamic>)
        .map((json) {
      final date = DateFormat('yyyy-MM-dd').parseUtc(json['date']).toLocal();
      final start = DateFormat('HH:mm').parseUtc(json['start']).toLocal();
      final realStart = DateTime(date.year, date.month, date.day, start.hour, start.minute);
      final dur = json['durationMin'] as int;
      final slot = _BlockedSlot(
        start: realStart,
        end: realStart.add(Duration(minutes: dur + 15)), // incl. break
      );
      dev.log('   - Blocked: ${DateFormat('HH:mm').format(slot.start)}-${DateFormat('HH:mm').format(slot.end)}', name: 'AiScheduler');
      return slot;
    }).toList();

    dev.log('✅ Found ${blockedSlots.length} blocked slots', name: 'AiScheduler');
    return blockedSlots;
  }

  /* ----------------------------------------------------------
   * 6. Chat-like prompt for single task with user preferences
   * ---------------------------------------------------------- */
  static Future<String> chatSchedule(Task task, {Map<String, dynamic>? userPreferences}) async {
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);
    
    dev.log('🚀 STARTING SINGLE TASK SCHEDULING', name: 'AiScheduler');
    dev.log('📋 TASK DETAILS:', name: 'AiScheduler');
    dev.log('   - ID: ${task.id}', name: 'AiScheduler');
    dev.log('   - Title: ${task.title}', name: 'AiScheduler');
    dev.log('   - Description: ${task.desc}', name: 'AiScheduler');
    dev.log('   - Duration: ${task.durationMin}min', name: 'AiScheduler');
    dev.log('   - Priority: ${task.priority.name}', name: 'AiScheduler');
    dev.log('   - UID: ${task.uid}', name: 'AiScheduler');
    
    // Get user data if not provided
    final userData = userPreferences != null ? 
        {'preferences': userPreferences} : await _getUserData(task.uid);
    final prefs = userData?['preferences'];
    final timeRanges = _parseTimeRanges(prefs);
    
    final blocked = await _blockedSlots(uid: task.uid, day: today);
    
    // Determine if task is work-related
    final isWorkTask = await _isWorkRelatedTask(task);
    
    // Get task tags for better context
    final taskTags = await _getTaskTags(task.id, task.uid);
    
    final workStart = timeRanges['workingHours']!.split('-')[0];
    final workEnd = timeRanges['workingHours']!.split('-')[1];
    final schedulingWindow = isWorkTask ? 
        'ONLY during working hours ($workStart-$workEnd)' : 
        'ONLY outside working hours (before $workStart or after $workEnd)';

    dev.log('🎯 SCHEDULING CONSTRAINTS:', name: 'AiScheduler');
    dev.log('   - Task Type: ${isWorkTask ? "WORK" : "PERSONAL"}', name: 'AiScheduler');
    dev.log('   - Working Hours: $workStart-$workEnd', name: 'AiScheduler');
    dev.log('   - Sleep Schedule: ${timeRanges['sleepSchedule']}', name: 'AiScheduler');
    dev.log('   - Scheduling Window: $schedulingWindow', name: 'AiScheduler');
    dev.log('   - Blocked Slots: ${blocked.length}', name: 'AiScheduler');

    final prompt = StringBuffer()
      ..writeln('You are an intelligent daily planner that respects user preferences.')
      ..writeln('')
      ..writeln('USER PREFERENCES:')
      ..writeln('- Work Type: ${prefs?['workType'] ?? "Flexible"}')
      ..writeln('- Focus Style: ${prefs?['focusStyle'] ?? "Flexible"}')
      ..writeln('- Productivity Goal: ${prefs?['productivityGoal'] ?? "General productivity"}')
      ..writeln('- Working Hours: $workStart-$workEnd')
      ..writeln('- Sleep Schedule: ${timeRanges['sleepSchedule']} (NEVER schedule during sleep)')
      ..writeln('')
      ..writeln('TASK TO SCHEDULE:')
      ..writeln('- Title: ${task.title}')
      ..writeln('- Description: ${task.desc}')
      ..writeln('- Duration: ${task.durationMin} minutes')
      ..writeln('- Priority: ${task.priority.name}')
      ..writeln('- Type: ${isWorkTask ? "WORK-RELATED" : "PERSONAL"}')
      ..writeln('- Tags: ${taskTags?.join(", ") ?? "No tags"}')
      ..writeln('')
      ..writeln('ALREADY BOOKED SLOTS (avoid these):');

    if (blocked.isEmpty) {
      prompt.writeln('- No existing bookings');
    } else {
      for (final slot in blocked) {
        prompt.writeln('- ${DateFormat('HH:mm').format(slot.start)}-${DateFormat('HH:mm').format(slot.end)}');
      }
    }

    prompt
      ..writeln('')
      ..writeln('CRITICAL SCHEDULING RULES:')
      ..writeln('1. WORK TASKS: Schedule ONLY between $workStart-$workEnd')
      ..writeln('2. PERSONAL TASKS: Schedule ONLY outside $workStart-$workEnd')
      ..writeln('3. NEVER during sleep hours (${timeRanges['sleepSchedule']})')
      ..writeln('4. Consider focus style: ${prefs?['focusStyle'] ?? "Flexible"}')
      ..writeln('5. Align with productivity goal: ${prefs?['productivityGoal'] ?? "General productivity"}')
      ..writeln('6. Include 15-minute breaks between tasks')
      ..writeln('7. High priority tasks get optimal focus hours')
      ..writeln('')
      ..writeln('WORK TASK CRITERIA: Tasks with tags: work, work projects, college, student')
      ..writeln('PERSONAL TASK CRITERIA: All other tasks (health, fitness, hobbies, family, etc.)')
      ..writeln('')
      ..writeln('Reply with: "How about HH:MM-HH:MM? [Brief reason based on task type and user preferences]"')
      ..writeln('Example for work task: "How about 14:30-15:15? Perfect work hours slot for your project task."')
      ..writeln('Example for personal task: "How about 18:30-19:15? After work hours for your personal fitness routine."');

    final promptString = prompt.toString();
    dev.log('📤 SENDING PROMPT TO AI:', name: 'AiScheduler');
    dev.log('```\n$promptString\n```', name: 'AiScheduler');

    try {
      final resp = await gemini.generateContent([Content.text(promptString)]);
      final response = resp.text?.trim() ?? 'I need more information to schedule this task.';
      dev.log('📥 AI RESPONSE:', name: 'AiScheduler');
      dev.log('```\n$response\n```', name: 'AiScheduler');
      return response;
    } catch (e) {
      dev.log('❌ Error in chatSchedule: $e', name: 'AiScheduler');
      return 'I encountered an error while scheduling. Please try again.';
    }
  }

  /* ----------------------------------------------------------
   * 7. Insert single slot
   * ---------------------------------------------------------- */
  static Future<void> insertSingleSlot(
    Task task, 
    DateTime startTime, 
    DateTime endTime, 
    {required String userId}
  ) async {
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);

    dev.log('💾 INSERTING SCHEDULE SLOT:', name: 'AiScheduler');
    dev.log('   - User ID: $userId', name: 'AiScheduler');
    dev.log('   - Task: ${task.title}', name: 'AiScheduler');
    dev.log('   - Time: ${DateFormat('HH:mm').format(startTime)}-${DateFormat('HH:mm').format(endTime)}', name: 'AiScheduler');
    dev.log('   - Date: $dateStr', name: 'AiScheduler');

    // Read existing schedule
    final schedSnap = await FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: userId)
        .where('scheduleDate', isEqualTo: dateStr)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    dev.log('   - Existing schedules found: ${schedSnap.docs.length}', name: 'AiScheduler');

    final List<Map<String, dynamic>> merged =
        schedSnap.docs.isEmpty ? [] : List.from(schedSnap.docs.first.data()['orderedTasks']);

    // Determine task type for the reason
    final isWorkTask = await _isWorkRelatedTask(task);
    final taskType = isWorkTask ? 'work' : 'personal';

    final newSlot = {
      'id': task.id,
      'title': task.title,
      'durationMin': task.durationMin,
      'start': DateFormat('HH:mm').format(startTime),
      'date': dateStr,
      'priority': task.priority.name,
      'reason': 'Scheduled during ${taskType} hours considering your preferences',
      'scheduled': true,
      'taskType': taskType,
    };

    merged.add(newSlot);
    dev.log('   - Added new slot: $newSlot', name: 'AiScheduler');

    // Sort by start time
    merged.sort((a, b) => DateFormat('HH:mm')
        .parseUtc(a['start'])
        .compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

    dev.log('   - Final merged schedule has ${merged.length} tasks', name: 'AiScheduler');

    if (schedSnap.docs.isEmpty) {
      dev.log('   - Creating new schedule document', name: 'AiScheduler');
      await FirebaseFirestore.instance.collection('schedules').add({
        'uid': userId,
        'scheduleDate': dateStr,
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } else {
      dev.log('   - Updating existing schedule document: ${schedSnap.docs.first.id}', name: 'AiScheduler');
      await FirebaseFirestore.instance.collection('schedules').doc(schedSnap.docs.first.id).update({
        'orderedTasks': merged,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    dev.log('✅ Schedule saved successfully', name: 'AiScheduler');
  }

  // ... (rest of the code remains the same for bulk optimization)
  /* ----------------------------------------------------------
   * 8. Bulk optimization with user preferences
   * ---------------------------------------------------------- */
  static Future<String> optimiseAndSave(List<Task> raw) async {
    final today = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(today);
    final uid = raw.first.uid;

    dev.log('🚀 STARTING BULK SCHEDULING for $uid', name: 'AiScheduler');
    dev.log('   - Total tasks: ${raw.length}', name: 'AiScheduler');

    // Get user data
    final userData = await _getUserData(uid);
    final prefs = userData?['preferences'];
    final timeRanges = _parseTimeRanges(prefs);

    // Read existing schedule
    final existingSnap = await FirebaseFirestore.instance
        .collection('schedules')
        .where('uid', isEqualTo: uid)
        .where('scheduleDate', isEqualTo: dateStr)
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    final Map<String, dynamic> existingMap = {};
    if (existingSnap.docs.isNotEmpty) {
      for (final slot in (existingSnap.docs.first.data()['orderedTasks'] as List<dynamic>)) {
        existingMap[slot['id'] as String] = slot;
      }
    }

    // Keep only NEW tasks
    final newTasks = raw.where((t) => !existingMap.containsKey(t.id)).toList();
    if (newTasks.isEmpty) {
      dev.log('🤖 All tasks already scheduled', name: 'AiScheduler');
      return existingSnap.docs.isEmpty ? '' : existingSnap.docs.first.id;
    }

    dev.log('   - New tasks to schedule: ${newTasks.length}', name: 'AiScheduler');

    // Get blocked slots
    final blocked = await _blockedSlots(uid: uid, day: today);

    // Separate work and personal tasks
    final workTasks = <Task>[];
    final personalTasks = <Task>[];
    
    for (final task in newTasks) {
      if (await _isWorkRelatedTask(task)) {
        workTasks.add(task);
      } else {
        personalTasks.add(task);
      }
    }

    dev.log('   - Work tasks: ${workTasks.length}', name: 'AiScheduler');
    dev.log('   - Personal tasks: ${personalTasks.length}', name: 'AiScheduler');

    // Get work hours
    final workStart = timeRanges['workingHours']!.split('-')[0];
    final workEnd = timeRanges['workingHours']!.split('-')[1];

    // Build comprehensive prompt
    final buffer = StringBuffer()
      ..writeln('You are an expert daily planner that strictly follows user preferences.')
      ..writeln('')
      ..writeln('USER PREFERENCES:')
      ..writeln('- Work Type: ${prefs?['workType'] ?? "Flexible"}')
      ..writeln('- Focus Style: ${prefs?['focusStyle'] ?? "Flexible"}')
      ..writeln('- Productivity Goal: ${prefs?['productivityGoal'] ?? "General productivity"}')
      ..writeln('- Working Hours: $workStart-$workEnd')
      ..writeln('- Sleep Schedule: ${timeRanges['sleepSchedule']} (NEVER SCHEDULE DURING SLEEP)')
      ..writeln('')
      ..writeln('EXISTING SCHEDULE (avoid these times):');

    if (blocked.isEmpty) {
      buffer.writeln('- No existing bookings');
    } else {
      for (final slot in blocked) {
        buffer.writeln('- ${DateFormat('HH:mm').format(slot.start)}-${DateFormat('HH:mm').format(slot.end)}');
      }
    }

    buffer
      ..writeln('')
      ..writeln('WORK TASKS (schedule ONLY during working hours $workStart-$workEnd):');
    if (workTasks.isEmpty) {
      buffer.writeln('- No work tasks');
    } else {
      for (final t in workTasks) {
        final taskTags = await _getTaskTags(t.id, t.uid);
        buffer.writeln('- ID:${t.id}|TITLE:${t.title}|TAGS:${taskTags?.join(", ") ?? "No tags"}|DURATION:${t.durationMin}min|PRIORITY:${t.priority.name}');
      }
    }

    buffer
      ..writeln('')
      ..writeln('PERSONAL TASKS (schedule ONLY outside working hours - before $workStart or after $workEnd):');
    if (personalTasks.isEmpty) {
      buffer.writeln('- No personal tasks');
    } else {
      for (final t in personalTasks) {
        final taskTags = await _getTaskTags(t.id, t.uid);
        buffer.writeln('- ID:${t.id}|TITLE:${t.title}|TAGS:${taskTags?.join(", ") ?? "No tags"}|DURATION:${t.durationMin}min|PRIORITY:${t.priority.name}');
      }
    }

    buffer
      ..writeln('')
      ..writeln('CRITICAL RULES:')
      ..writeln('1. WORK TASKS: Schedule ONLY between $workStart-$workEnd')
      ..writeln('2. PERSONAL TASKS: Schedule ONLY outside $workStart-$workEnd')
      ..writeln('3. NEVER during ${timeRanges['sleepSchedule']}')
      ..writeln('4. Consider user focus style: ${prefs?['focusStyle']}')
      ..writeln('5. High priority tasks get optimal focus hours')
      ..writeln('6. Include 15-minute breaks between consecutive tasks')
      ..writeln('7. Group similar tasks together when possible')
      ..writeln('')
      ..writeln('WORK TASK CRITERIA: Tasks with tags: work, work projects, college, student')
      ..writeln('PERSONAL TASK CRITERIA: All other tasks')
      ..writeln('')
      ..writeln('Return JSON: [{"id":"taskId","start":"HH:mm","reason":"Explanation based on task type and user preferences"}]');

    final promptString = buffer.toString();
    dev.log('📤 SENDING BULK PROMPT TO AI:', name: 'AiScheduler');
    dev.log('```\n$promptString\n```', name: 'AiScheduler');

    try {
      final resp = await gemini.generateContent([Content.text(promptString)]);
      String jsonStr = (resp.text ?? '[]').trim()
          .replaceFirst(RegExp(r'^```json\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
      
      dev.log('📥 AI BULK RESPONSE:', name: 'AiScheduler');
      dev.log('```\n$jsonStr\n```', name: 'AiScheduler');
      final List<dynamic> timeList = jsonDecode(jsonStr);

      // Merge new slots
      for (final t in timeList) {
        final taskTime = DateFormat('HH:mm').parseUtc(t['start']).toLocal();
        final realStart = DateTime(today.year, today.month, today.day, taskTime.hour, taskTime.minute);

        final task = newTasks.firstWhere((tk) => tk.id == t['id']);
        final isWorkTask = await _isWorkRelatedTask(task);

        existingMap[t['id'] as String] = {
          'id': t['id'],
          'title': task.title,
          'durationMin': task.durationMin,
          'start': DateFormat('HH:mm').format(realStart),
          'date': dateStr,
          'priority': task.priority.name,
          'reason': t['reason'] ?? 'Scheduled during ${isWorkTask ? "work" : "personal"} hours',
          'scheduled': true,
          'taskType': isWorkTask ? 'work' : 'personal',
        };
      }

      // Convert to sorted list
      final merged = existingMap.values.toList()
        ..sort((a, b) =>
            DateFormat('HH:mm').parseUtc(a['start']).compareTo(DateFormat('HH:mm').parseUtc(b['start'])));

      // Save to Firestore
      if (existingSnap.docs.isEmpty) {
        final doc = await FirebaseFirestore.instance.collection('schedules').add({
          'uid': uid,
          'scheduleDate': dateStr,
          'orderedTasks': merged,
          'createdAt': FieldValue.serverTimestamp(),
        });
        dev.log('✅ Created new schedule document: ${doc.id}', name: 'AiScheduler');
        return doc.id;
      } else {
        final id = existingSnap.docs.first.id;
        await FirebaseFirestore.instance.collection('schedules').doc(id).update({
          'orderedTasks': merged,
          'createdAt': FieldValue.serverTimestamp(),
        });
        dev.log('✅ Updated existing schedule document: $id', name: 'AiScheduler');
        return id;
      }
    } catch (e) {
      dev.log('❌ Error in optimiseAndSave: $e', name: 'AiScheduler');
      rethrow;
    }
  }
}

/* ---------- Helper class ---------- */
class _BlockedSlot {
  final DateTime start;
  final DateTime end;
  _BlockedSlot({required this.start, required this.end});
}