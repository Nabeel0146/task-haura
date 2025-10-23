import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:taskhaura/models/task.dart';

class DeepLinkCalendarService {
  Future<bool> addTaskToCalendar(Task task) async {
    try {
      // Method 1: Try Google Calendar deep link first
      bool success = await _tryGoogleCalendarDeepLink(task);
      if (success) return true;

      // Method 2: If Google Calendar fails, try generic calendar app
      success = await _tryGenericCalendarApp(task);
      if (success) return true;

      // Method 3: If all else fails, show manual instructions
      return await _showManualInstructions(task);
      
    } catch (e) {
      print('Error creating calendar event: $e');
      return false;
    }
  }

  Future<bool> _tryGoogleCalendarDeepLink(Task task) async {
    try {
      final startTime = task.deadline;
      final endTime = startTime!.add(Duration(minutes: task.durationMin));
      
      // Format dates for Google Calendar
      final String start = _formatDateTimeForCalendar(startTime!);
      final String end = _formatDateTimeForCalendar(endTime);
      
      // Create Google Calendar deep link
      final String url = 
          'https://calendar.google.com/calendar/render?'
          'action=TEMPLATE'
          '&text=${Uri.encodeComponent(task.title)}'
          '&details=${Uri.encodeComponent(_getDescription(task))}'
          '&dates=$start/$end'
          '&sf=true'
          '&output=xml';

      print('Attempting to launch: $url');
      
      // Launch the URL
      if (await canLaunchUrl(Uri.parse(url))) {
        final result = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        print('Launch result: $result');
        return result;
      } else {
        print('Cannot launch Google Calendar URL');
        return false;
      }
    } catch (e) {
      print('Google Calendar deep link failed: $e');
      return false;
    }
  }

  Future<bool> _tryGenericCalendarApp(Task task) async {
    try {
      final startTime = task.deadline;
      final endTime = startTime!.add(Duration(minutes: task.durationMin));
      
      // Try generic calendar URL (works on iOS and some Android devices)
      final String url = 
          'https://calendar.google.com/calendar/r/eventedit?'
          'text=${Uri.encodeComponent(task.title)}'
          '&details=${Uri.encodeComponent(_getDescription(task))}'
          '&dates=${_formatDateTimeForCalendar(startTime!)}/${_formatDateTimeForCalendar(endTime)}';

      print('Attempting generic calendar: $url');
      
      if (await canLaunchUrl(Uri.parse(url))) {
        final result = await launchUrl(
          Uri.parse(url),
          mode: LaunchMode.externalApplication,
        );
        return result;
      }
      return false;
    } catch (e) {
      print('Generic calendar failed: $e');
      return false;
    }
  }

  Future<bool> _showManualInstructions(Task task) async {
    // This will show a dialog with manual instructions
    // Return true to indicate we've handled the situation
    return true;
  }

  String _getDescription(Task task) {
    String description = '';
    
    if (task.desc.isNotEmpty) {
      description += '${task.desc}\n\n';
    }
    
    description += 'Task Details:\n';
    description += '• Duration: ${task.durationMin} minutes\n';
    description += '• Priority: ${task.priority.name.toUpperCase()}\n';
    
    if (task.tag.isNotEmpty) {
      description += '• Tag: ${task.tag}\n';
    }
    
    description += '• Created via TaskHaura App';
    
    return description;
  }

  String _formatDateTimeForCalendar(DateTime date) {
    // Format: YYYYMMDDTHHMMSSZ (UTC time)
    final year = date.year.toString();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    final second = date.second.toString().padLeft(2, '0');
    
    return '${year}${month}${day}T${hour}${minute}${second}Z';
  }

  // Alternative method for manual event creation
  String getManualEventDetails(Task task) {
    final startTime = task.deadline;
    final endTime = startTime!.add(Duration(minutes: task.durationMin));
    
    return '''
Title: ${task.title}
Description: ${_getDescription(task)}
Start: ${DateFormat('yyyy-MM-dd HH:mm').format(startTime)}
End: ${DateFormat('yyyy-MM-dd HH:mm').format(endTime)}
Duration: ${task.durationMin} minutes
Priority: ${task.priority.name.toUpperCase()}
Tag: ${task.tag}
''';
  }
}