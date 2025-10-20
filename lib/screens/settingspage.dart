import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:taskhaura/AUTH/login.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final User? user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user!.uid)
          .get();
      setState(() {
        userData = doc.data();
        _loading = false;
      });
    } else {
      setState(() {
        _loading = false;
      });
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.red),
            SizedBox(width: 8),
            Text('Logout'),
          ],
        ),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await FirebaseAuth.instance.signOut();
      // Navigate to login page or root
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginPage()));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildProfileHeader() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF74EC7A).withOpacity(0.8),
            const Color(0xFF74EC7A),
          ],
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(24),
          bottomRight: Radius.circular(24),
        ),
      ),
      child: Column(
        children: [
          // Profile Avatar
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              color: Colors.white,
            ),
            child: ClipOval(
              child: user?.photoURL != null
                  ? CachedNetworkImage(
                      imageUrl: user!.photoURL!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Icon(
                        Icons.person,
                        size: 40,
                        color: Color(0xFF74EC7A),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Icons.person,
                        size: 40,
                        color: Color(0xFF74EC7A),
                      ),
                    )
                  : const Icon(
                      Icons.person,
                      size: 40,
                      color: Color(0xFF74EC7A),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          
          // User Name
          Text(
            userData?['name'] ?? user?.displayName ?? 'User',
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          
          // User Email
          Text(
            user?.email ?? 'No email',
            style: const TextStyle(
              fontSize: 16,
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 8),
          
          // Member since
          if (user?.metadata.creationTime != null)
            Text(
              'Member since ${DateFormat('MMM yyyy').format(user!.metadata.creationTime!)}',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.white60,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: const Color(0xFF74EC7A), size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
    String? subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor ?? const Color(0xFF74EC7A)),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle) : null,
      trailing: trailing ?? const Icon(Icons.chevron_right, color: Colors.grey),
      onTap: onTap,
      contentPadding: EdgeInsets.zero,
      visualDensity: const VisualDensity(vertical: -2),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: const Color(0xFF74EC7A),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Profile Header
          _buildProfileHeader(),
          
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(top: 16, bottom: 20),
              children: [
                // Account Settings
                _buildSettingsCard(
                  'Account',
                  Icons.account_circle,
                  [
                    _buildSettingItem(
                      title: 'Edit Profile',
                      icon: Icons.person_outline,
                      onTap: () {
                        // Navigate to edit profile page
                      },
                    ),
                    _buildSettingItem(
                      title: 'Change Email',
                      icon: Icons.email_outlined,
                      onTap: () {
                        // Navigate to change email page
                      },
                    ),
                    _buildSettingItem(
                      title: 'Change Password',
                      icon: Icons.lock_outline,
                      onTap: () {
                        // Navigate to change password page
                      },
                    ),
                  ],
                ),

                // App Preferences
                _buildSettingsCard(
                  'Preferences',
                  Icons.settings,
                  [
                    _buildSettingItem(
                      title: 'Notification Settings',
                      icon: Icons.notifications_outlined,
                      onTap: () {
                        // Navigate to notification settings
                      },
                    ),
                    _buildSettingItem(
                      title: 'Working Hours',
                      icon: Icons.access_time,
                      subtitle: userData?['workingHours'] ?? '9:00 AM - 5:00 PM',
                      onTap: () {
                        // Navigate to working hours settings
                      },
                    ),
                    _buildSettingItem(
                      title: 'Task Categories',
                      icon: Icons.category_outlined,
                      subtitle: 'Manage your tags',
                      onTap: () {
                        // Navigate to categories management
                      },
                    ),
                  ],
                ),

                // AI Settings
                _buildSettingsCard(
                  'AI Assistant',
                  Icons.auto_awesome,
                  [
                    _buildSettingItem(
                      title: 'AI Preferences',
                      icon: Icons.smart_toy_outlined,
                      onTap: () {
                        // Navigate to AI preferences
                      },
                    ),
                    _buildSettingItem(
                      title: 'Learning Mode',
                      icon: Icons.school_outlined,
                      trailing: Switch(
                        value: true,
                        onChanged: (value) {},
                        activeColor: const Color(0xFF74EC7A),
                      ),
                      onTap: () {},
                    ),
                  ],
                ),

                // Support & About
                _buildSettingsCard(
                  'Support',
                  Icons.help_outline,
                  [
                    _buildSettingItem(
                      title: 'Help & Support',
                      icon: Icons.help_outline,
                      onTap: () {
                        // Navigate to help page
                      },
                    ),
                    _buildSettingItem(
                      title: 'About TaskHaura',
                      icon: Icons.info_outline,
                      onTap: () {
                        _showAboutDialog();
                      },
                    ),
                    _buildSettingItem(
                      title: 'Privacy Policy',
                      icon: Icons.privacy_tip_outlined,
                      onTap: () {
                        // Navigate to privacy policy
                      },
                    ),
                    _buildSettingItem(
                      title: 'Terms of Service',
                      icon: Icons.description_outlined,
                      onTap: () {
                        // Navigate to terms of service
                      },
                    ),
                  ],
                ),

                // Logout Button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Card(
                    color: Colors.red.withOpacity(0.05),
                    elevation: 0,
                    child: _buildSettingItem(
                      title: 'Logout',
                      icon: Icons.logout,
                      iconColor: Colors.red,
                      onTap: _showLogoutDialog,
                    ),
                  ),
                ),

                // App Version
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(
                    child: Text(
                      'TaskHaura v1.0.0',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.analytics_outlined, color: Color(0xFF74EC7A), size: 20),
                SizedBox(width: 8),
                Text(
                  'Your Stats',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatItem('Tasks Completed', '128', Icons.check_circle_outline),
                _buildStatItem('Productivity Score', '85%', Icons.trending_up_outlined),
                _buildStatItem('AI Sessions', '47', Icons.auto_awesome_outlined),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, color: const Color(0xFF74EC7A), size: 24),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF74EC7A),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  void _showAboutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: Color(0xFF74EC7A)),
            SizedBox(width: 8),
            Text('About TaskHaura'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your AI-powered productivity companion that helps you organize, schedule, and complete tasks efficiently.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            const Text(
              'Features:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            _buildFeatureItem('🤖 AI Task Creation & Breakdown'),
            _buildFeatureItem('📅 Smart Scheduling'),
            _buildFeatureItem('🎯 Priority Management'),
            _buildFeatureItem('📊 Progress Tracking'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          const Icon(Icons.circle, size: 6, color: Color(0xFF74EC7A)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }
}

