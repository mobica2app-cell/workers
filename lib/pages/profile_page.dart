// lib/pages/profile_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
import '../main.dart';
import '../services/sap_service.dart';
import 'login_page.dart';

class ProfilePage extends StatefulWidget {
  final EmployeeAuth? employee;

  const ProfilePage({Key? key, this.employee}) : super(key: key);

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  final EmployeeAuthService _authService = EmployeeAuthService(
    Supabase.instance.client,
  );

  EmployeeAuth? _employee;

  // Theme preference
  bool _isDarkMode = false;
  static const String _themeKey = 'app_theme_preference';

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _backgroundColor =>
      _isDark ? const Color(0xFF000000) : const Color(0xFFF8FAFC);

  Color get _surfaceColor => _isDark ? const Color(0xFF121212) : Colors.white;

  Color get _textColor =>
      _isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0F172A);

  Color get _secondaryTextColor =>
      _isDark ? const Color(0xFFAAAAAA) : const Color(0xFF64748B);

  Color get _borderColor =>
      _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE2E8F0);

  Color get _cardColor => _isDark ? const Color(0xFF121212) : Colors.white;

  Color get _chipBackground =>
      _isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade100;

  @override
  void initState() {
    super.initState();
    _employee = widget.employee;

    // Add this line to listen for theme changes
    ThemeNotifier.instance.addListener(_onThemeChanged);
  }

  // Add this method to handle theme changes
  void _onThemeChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    // Add this line to remove the listener
    ThemeNotifier.instance.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _toggleTheme(bool value) {
    ThemeNotifier.instance.toggleTheme(value);

    // Show confirmation
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          value ? '🌙 Dark mode enabled' : '☀️ Light mode enabled',
          style: GoogleFonts.cairo(),
        ),
        backgroundColor: _isDark
            ? const Color(0xFF000000)
            : const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _showLogoutDialog() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text(
          'Logout',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w600,
            color: _textColor,
          ),
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: GoogleFonts.cairo(color: _secondaryTextColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancel',
              style: GoogleFonts.cairo(color: _secondaryTextColor),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(
              'Logout',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      // Match MainShell logout behavior: preserve Remember Me credentials.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const LoginPage()),
            (route) => false,
      );
    }
  }

  void _showChangePasswordDialog() {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Change Password',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: newPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'New Password',
                labelStyle: GoogleFonts.cairo(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: confirmPasswordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Confirm Password',
                labelStyle: GoogleFonts.cairo(),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () async {
              if (newPasswordController.text !=
                  confirmPasswordController.text) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Passwords do not match',
                      style: GoogleFonts.cairo(),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (newPasswordController.text.length < 8) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Password must be at least 8 characters',
                      style: GoogleFonts.cairo(),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              final success = await _authService.changePassword(
                _employee!.id,
                newPasswordController.text,
              );
              if (mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      success ? 'Password changed!' : 'Failed',
                      style: GoogleFonts.cairo(),
                    ),
                    backgroundColor: success ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.primary,
            ),
            child: Text(
              'Change',
              style: GoogleFonts.cairo(
                color: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_employee == null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: _secondaryTextColor),
              const SizedBox(height: 16),
              Text(
                'Please login first',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  color: _secondaryTextColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: _isDark
                ? const Color(0xFF131313)
                : const Color(0xFF0F172A),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF191919), Color(0xFF353535)],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 40,
                              backgroundColor: Colors.white,
                              child: Text(
                                _employee!.initials,
                                style: GoogleFonts.cairo(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  color: const Color(0xFF000000),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _employee!.fullName,
                                    style: GoogleFonts.cairo(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      _employee!.role ?? 'Employee',
                                      style: GoogleFonts.cairo(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Only the Profile content is shown. My Work and By Role were removed.
        ],
        body: _buildProfileTab(),
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            color: _cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Employee Information',
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildInfoTile(Icons.person, 'Username', _employee!.username),
                  _buildInfoTile(Icons.badge, 'Full Name', _employee!.fullName),
                  if (_employee!.department != null)
                    _buildInfoTile(
                      Icons.business,
                      'Department',
                      _employee!.department!,
                    ),
                  if (_employee!.role != null)
                    _buildInfoTile(Icons.work, 'Role', _employee!.role!),
                  if (_employee!.phoneNumber != null)
                    _buildInfoTile(
                      Icons.phone,
                      'Phone',
                      _employee!.phoneNumber!,
                    ),
                  _buildInfoTile(
                    Icons.calendar_today,
                    'Joined',
                    DateFormat('MMM dd, yyyy').format(_employee!.createdAt),
                  ),
                  if (_employee!.lastLogin != null)
                    _buildInfoTile(
                      Icons.login,
                      'Last Login',
                      DateFormat(
                        'MMM dd, yyyy HH:mm',
                      ).format(_employee!.lastLogin!),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Theme Settings Card
          Card(
            color: _cardColor,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.palette_outlined, color: _textColor, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Appearance',
                        style: GoogleFonts.cairo(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Replace the existing SwitchListTile with this
                  SwitchListTile(
                    title: Text(
                      'Dark Mode',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                    ),
                    subtitle: Text(
                      'Use dark theme throughout the app',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        color: _secondaryTextColor,
                      ),
                    ),
                    value: ThemeNotifier.instance.isDarkMode,
                    // Changed from _isDarkMode
                    onChanged: _toggleTheme,
                    secondary: Icon(
                      ThemeNotifier.instance.isDarkMode
                          ? Icons.dark_mode
                          : Icons.light_mode, // Changed from _isDarkMode
                      color: ThemeNotifier.instance.isDarkMode
                          ? Colors.blue
                          : Colors.orange, // Changed from _isDarkMode
                    ),
                    activeColor: Colors.blue,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showChangePasswordDialog,
              icon: const Icon(Icons.lock_outline),
              label: Text('Change Password', style: GoogleFonts.cairo()),
              style: OutlinedButton.styleFrom(
                foregroundColor: _textColor,
                side: BorderSide(color: _borderColor),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Logout button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showLogoutDialog(),
              icon: const Icon(Icons.logout, color: Colors.red),
              label: Text(
                'Logout',
                style: GoogleFonts.cairo(
                  color: Colors.red,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                backgroundColor: Colors.red.withOpacity(0.05),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoTile(
      IconData icon,
      String label,
      String value, {
        Color? valueColor,
      }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 20, color: _secondaryTextColor),
          const SizedBox(width: 12),
          Text(
            label,
            style: GoogleFonts.cairo(fontSize: 14, color: _secondaryTextColor),
          ),
          const Spacer(),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: valueColor ?? _textColor,
            ),
          ),
        ],
      ),
    );
  }
}
