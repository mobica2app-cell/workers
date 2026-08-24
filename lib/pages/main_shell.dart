// lib/pages/main_shell.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobitem/pages/analytics_page.dart';
import 'package:mobitem/pages/profile_page.dart';
import 'package:universal_html/html.dart' as html;
import 'dashboard_page.dart';
import '../services/sap_service.dart';
import 'department_tracking_page.dart';
import 'login_page.dart';
import 'orders_page.dart';

class MainShell extends StatefulWidget {
  final SAPMainService sapService;
  final EmployeeAuth? loggedInEmployee;

  const MainShell({
    Key? key,
    required this.sapService,
    this.loggedInEmployee,
  }) : super(key: key);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  bool get _isHead {
    final role = widget.loggedInEmployee?.role?.toLowerCase() ?? '';
    return role == 'head' || role == 'software head' || role == 'admin';
  }

  final List<_NavItem> _headNavItems = [
    _NavItem(icon: Icons.list_alt, label: 'Orders'),
    _NavItem(icon: Icons.dashboard_outlined, label: 'Dashboard'),
    _NavItem(icon: Icons.analytics_outlined, label: 'Analytics'),
    _NavItem(icon: Icons.person, label: 'Profile'),
    _NavItem(icon: Icons.business, label: 'Departments'),
  ];

  final List<_NavItem> _userNavItems = [
    _NavItem(icon: Icons.list_alt, label: 'Orders'),
    _NavItem(icon: Icons.person, label: 'Profile'),
  ];

  List<_NavItem> get _navItems {
    return _isHead ? _headNavItems : _userNavItems;
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 700;

    print('📱 Screen width: $screenWidth, isMobile: $isMobile');

    if (isMobile) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: _buildPage(),
        bottomNavigationBar: _buildBottomNavBar(),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Row(
        children: [
          _buildSidebar(),
          Expanded(child: _buildPage()),
        ],
      ),
    );
  }

  // Sidebar for desktop
  Widget _buildSidebar() {
    return Container(
      width: 240,
      color: const Color(0xFF0F172A),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.factory, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('MOBICA', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(
                    _isHead ? 'Admin view' : 'User view',
                    style: TextStyle(color: _isHead ? Colors.amber.withOpacity(0.7) : Colors.white38, fontSize: 10, letterSpacing: 0.3),
                  ),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ..._navItems.map((item) {
            final itemIndex = _navItems.indexOf(item);
            return _buildNavItem(
              item,
              isSelected: itemIndex == _selectedIndex,
              onTap: () {
                setState(() => _selectedIndex = itemIndex);
              },
            );
          }),
          const Spacer(),
          if (widget.loggedInEmployee != null) ...[
            const Divider(color: Colors.white10),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withOpacity(0.1)),
                ),
                child: Row(children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: const Color(0xFF6366F1).withOpacity(0.3),
                    child: Text(widget.loggedInEmployee!.initials, style: GoogleFonts.cairo(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(widget.loggedInEmployee!.displayName, style: GoogleFonts.cairo(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                      if (widget.loggedInEmployee!.role != null)
                        Text(widget.loggedInEmployee!.role!, style: GoogleFonts.cairo(color: Colors.white54, fontSize: 11), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  IconButton(
                    icon: const Icon(Icons.logout, color: Colors.white38, size: 18),
                    onPressed: () => _showLogoutDialog(),
                    tooltip: 'Logout',
                  ),
                ]),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // Bottom Navigation Bar for mobile
  Widget _buildBottomNavBar() {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor,
        border: Border(top: BorderSide(color: _borderColor)),
      ),
      child: SafeArea(
        child: Row(
          children: _navItems.map((item) {
            final itemIndex = _navItems.indexOf(item);
            final isSelected = itemIndex == _selectedIndex;
            return Expanded(
              child: InkWell(
                onTap: () {
                  setState(() => _selectedIndex = itemIndex);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        item.icon,
                        color: isSelected ? const Color(0xFF6366F1) : _secondaryTextColor,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                          color: isSelected ? const Color(0xFF6366F1) : _secondaryTextColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _clearRememberMe() {
    try {
      html.window.localStorage.remove('remembered_username');
      html.window.localStorage.remove('remembered_password');
    } catch (e) {
      print('Error clearing storage: $e');
    }
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surfaceColor,
        title: Text('Logout', style: GoogleFonts.cairo(fontWeight: FontWeight.w600, color: _textColor)),
        content: Text('Are you sure you want to logout?', style: GoogleFonts.cairo(color: _secondaryTextColor)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.cairo(color: _secondaryTextColor)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clearRememberMe();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (context) => const LoginPage()),
                    (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Logout', style: GoogleFonts.cairo(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(_NavItem item, {required bool isSelected, required VoidCallback onTap}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: isSelected ? const Color(0xFF131B2E) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: isSelected
                ? const BoxDecoration(
              border: Border(left: BorderSide(color: Color(0xFFB7C8E1), width: 4)),
              borderRadius: BorderRadius.all(Radius.circular(8)),
            )
                : null,
            child: Row(children: [
              Icon(item.icon, color: isSelected ? Colors.white : Colors.white54, size: 20),
              const SizedBox(width: 12),
              Text(item.label, style: TextStyle(color: isSelected ? Colors.white : Colors.white54, fontSize: 14, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400)),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _buildPage() {
    if (_isHead) {
      switch (_selectedIndex) {
        case 0: return OrdersPage(sapService: widget.sapService, loggedInEmployee: widget.loggedInEmployee);
        case 1: return DashboardPage(sapService: widget.sapService);
        case 2: return AnalyticsPage(sapService: widget.sapService);
        case 3: return ProfilePage(employee: widget.loggedInEmployee);
        case 4: return const DepartmentTrackingPage();
        default: return OrdersPage(sapService: widget.sapService, loggedInEmployee: widget.loggedInEmployee);
      }
    } else {
      switch (_selectedIndex) {
        case 0: return OrdersPage(sapService: widget.sapService, loggedInEmployee: widget.loggedInEmployee);
        case 1: return ProfilePage(employee: widget.loggedInEmployee);
        default: return OrdersPage(sapService: widget.sapService, loggedInEmployee: widget.loggedInEmployee);
      }
    }
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  _NavItem({required this.icon, required this.label});
}