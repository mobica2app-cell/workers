// lib/pages/main_shell.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobitem/pages/analytics_page.dart';
import 'package:mobitem/pages/profile_page.dart';
import 'package:universal_html/html.dart' as html;

import '../services/sap_service.dart';
import 'dashboard_page.dart';
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
  bool _isCollapsed = false;

  // ============================================================
  // THEME
  // ============================================================

  bool get _isDark =>
      Theme.of(context).brightness == Brightness.dark;

  Color get _backgroundColor =>
      _isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC);

  Color get _surfaceColor =>
      _isDark
          ? const Color(0xFF1E293B)
          : Colors.white;

  Color get _textColor =>
      _isDark
          ? const Color(0xFFE2E8F0)
          : const Color(0xFF0F172A);

  Color get _secondaryTextColor =>
      _isDark
          ? const Color(0xFF94A3B8)
          : const Color(0xFF64748B);

  Color get _borderColor =>
      _isDark
          ? const Color(0xFF334155)
          : const Color(0xFFE2E8F0);

  // ============================================================
  // MOBILE BREAKPOINT
  // ============================================================

  bool get _isMobile {
    return MediaQuery.of(context).size.width < 700;
  }

  // ============================================================
  // ROLE
  // ============================================================

  bool get _isHead {
    final role =
        widget.loggedInEmployee?.role
            ?.toLowerCase()
            .trim() ??
            '';

    return role == 'head' ||
        role == 'software head' ||
        role == 'admin';
  }

  // ============================================================
  // HEAD NAVIGATION
  // ============================================================

  final List<_NavItem> _headNavItems = [
    _NavItem(
      icon: Icons.list_alt_outlined,
      activeIcon: Icons.list_alt,
      label: 'Orders',
    ),
    _NavItem(
      icon: Icons.dashboard_outlined,
      activeIcon: Icons.dashboard,
      label: 'Dashboard',
    ),
    _NavItem(
      icon: Icons.analytics_outlined,
      activeIcon: Icons.analytics,
      label: 'Analytics',
    ),
    _NavItem(
      icon: Icons.business_outlined,
      activeIcon: Icons.business,
      label: 'Departments',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  // ============================================================
  // NORMAL USER NAVIGATION
  // ============================================================

  final List<_NavItem> _userNavItems = [
    _NavItem(
      icon: Icons.list_alt_outlined,
      activeIcon: Icons.list_alt,
      label: 'Orders',
    ),
    _NavItem(
      icon: Icons.person_outline,
      activeIcon: Icons.person,
      label: 'Profile',
    ),
  ];

  // ============================================================
  // CURRENT NAVIGATION
  // ============================================================

  List<_NavItem> get _navItems {
    return _isHead
        ? _headNavItems
        : _userNavItems;
  }

  // ============================================================
  // TOGGLE SIDEBAR
  // ============================================================

  void _toggleSidebar() {
    setState(() {
      _isCollapsed = !_isCollapsed;
    });
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    // ==========================================================
    // MOBILE
    // ==========================================================

    if (_isMobile) {
      return _buildMobileLayout();
    }

    // ==========================================================
    // DESKTOP
    // ==========================================================

    return _buildDesktopLayout();
  }

  // ============================================================
  // DESKTOP LAYOUT
  // ============================================================

  Widget _buildDesktopLayout() {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Row(
        children: [

          // ====================================================
          // SIDEBAR
          // ====================================================

          AnimatedContainer(
            duration:
            const Duration(milliseconds: 300),
            curve: Curves.easeInOut,

            width:
            _isCollapsed
                ? 80
                : 240,

            color:
            const Color(0xFF0F172A),

            child: Column(
              children: [

                // ==============================================
                // HEADER
                // ==============================================

                _buildSidebarHeader(),

                const SizedBox(height: 16),

                // ==============================================
                // NAVIGATION
                // ==============================================

                Expanded(
                  child: ListView(
                    padding:
                    const EdgeInsets.symmetric(
                      vertical: 8,
                    ),

                    children:
                    _navItems
                        .asMap()
                        .entries
                        .map(
                          (entry) {
                        final itemIndex =
                            entry.key;

                        final item =
                            entry.value;

                        return _buildNavItem(
                          item,

                          isSelected:
                          itemIndex ==
                              _selectedIndex,

                          onTap: () {
                            setState(() {
                              _selectedIndex =
                                  itemIndex;
                            });
                          },
                        );
                      },
                    )
                        .toList(),
                  ),
                ),

                // ==============================================
                // USER
                // ==============================================

                if (widget.loggedInEmployee != null) ...[
                  const Divider(
                    color: Colors.white10,
                  ),

                  _buildUserSection(),
                ],
              ],
            ),
          ),

          // ====================================================
          // MAIN CONTENT
          // ====================================================

          Expanded(
            child: _buildPage(),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MOBILE LAYOUT
  // ============================================================

  Widget _buildMobileLayout() {
    // Safety check in case screen changes size
    if (_selectedIndex >= _navItems.length) {
      _selectedIndex = 0;
    }

    return Scaffold(
      backgroundColor: _backgroundColor,

      // ========================================================
      // CONTENT
      // ========================================================

      body: SafeArea(
        bottom: false,
        child: _buildPage(),
      ),

      // ========================================================
      // MOBILE BOTTOM NAVIGATION
      // ========================================================

      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: _surfaceColor,

            border: Border(
              top: BorderSide(
                color: _borderColor,
                width: 0.7,
              ),
            ),

            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 12,
                offset: const Offset(0, -3),
              ),
            ],
          ),

          child: NavigationBar(
            selectedIndex: _selectedIndex,

            onDestinationSelected: (index) {
              setState(() {
                _selectedIndex = index;
              });
            },

            height: 68,

            backgroundColor:
            Colors.transparent,

            elevation: 0,

            indicatorColor:
            const Color(0xFF6366F1)
                .withOpacity(0.15),

            labelBehavior:
            NavigationDestinationLabelBehavior
                .alwaysShow,

            destinations:
            _navItems.map(
                  (item) {
                return NavigationDestination(
                  icon: Icon(
                    item.icon,
                    size: 22,
                    color:
                    _secondaryTextColor,
                  ),

                  selectedIcon: Icon(
                    item.activeIcon,
                    size: 23,
                    color:
                    const Color(
                      0xFF6366F1,
                    ),
                  ),

                  label: item.label,
                );
              },
            ).toList(),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // SIDEBAR HEADER
  // ============================================================

  Widget _buildSidebarHeader() {
    return Container(
      padding:
      EdgeInsets.all(
        _isCollapsed
            ? 16
            : 20,
      ),

      decoration:
      const BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.white10,
          ),
        ),
      ),

      child:
      _isCollapsed
          ? _buildCollapsedHeader()
          : _buildExpandedHeader(),
    );
  }

  // ============================================================
  // EXPANDED HEADER
  // ============================================================

  Widget _buildExpandedHeader() {
    return Row(
      children: [

        Container(
          width: 40,
          height: 40,

          decoration:
          BoxDecoration(
            color:
            Colors.white10,
            borderRadius:
            BorderRadius.circular(
              10,
            ),
          ),

          child: const Icon(
            Icons.factory,
            color: Colors.white,
            size: 24,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment:
            CrossAxisAlignment.start,

            mainAxisSize:
            MainAxisSize.min,

            children: [

              const Text(
                'MOBICA',

                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight:
                  FontWeight.bold,
                ),
              ),

              Text(
                _isHead
                    ? 'Admin view'
                    : 'User view',

                style: TextStyle(
                  color:
                  _isHead
                      ? Colors.amber
                      .withOpacity(
                    0.7,
                  )
                      : Colors.white38,

                  fontSize: 10,

                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),

        IconButton(
          onPressed:
          _toggleSidebar,

          icon:
          const Icon(
            Icons.chevron_left,
            color:
            Colors.white54,
            size: 20,
          ),

          splashRadius: 20,

          tooltip:
          'Collapse',
        ),
      ],
    );
  }

  // ============================================================
  // COLLAPSED HEADER
  // ============================================================

  Widget _buildCollapsedHeader() {
    return Column(
      children: [

        Container(
          width: 40,
          height: 40,

          decoration:
          BoxDecoration(
            color:
            Colors.white10,

            borderRadius:
            BorderRadius.circular(
              10,
            ),
          ),

          child: const Icon(
            Icons.factory,
            color: Colors.white,
            size: 24,
          ),
        ),

        const SizedBox(
          height: 12,
        ),

        IconButton(
          onPressed:
          _toggleSidebar,

          icon:
          const Icon(
            Icons.chevron_right,
            color:
            Colors.white54,
            size: 20,
          ),

          splashRadius: 20,

          tooltip:
          'Expand',
        ),
      ],
    );
  }

  // ============================================================
  // CLEAR REMEMBER ME
  // ============================================================

  void _clearRememberMe() {
    try {
      html.window.localStorage
          .remove(
        'remembered_username',
      );

      html.window.localStorage
          .remove(
        'remembered_password',
      );
    } catch (e) {
      print(
        'Error clearing storage: $e',
      );
    }
  }

  // ============================================================
  // LOGOUT DIALOG
  // ============================================================

  void _showLogoutDialog() {
    showDialog(
      context: context,

      builder: (ctx) {
        return AlertDialog(
          backgroundColor:
          _surfaceColor,

          title: Text(
            'Logout',
            style:
            GoogleFonts.cairo(
              fontWeight:
              FontWeight.w600,
              color:
              _textColor,
            ),
          ),

          content: Text(
            'Are you sure you want to logout?',

            style:
            GoogleFonts.cairo(
              color:
              _secondaryTextColor,
            ),
          ),

          actions: [

            TextButton(
              onPressed:
                  () => Navigator.pop(
                ctx,
              ),

              child: Text(
                'Cancel',

                style:
                GoogleFonts.cairo(
                  color:
                  _secondaryTextColor,
                ),
              ),
            ),

            ElevatedButton(
              onPressed: () {

                Navigator.pop(
                  ctx,
                );

                _clearRememberMe();

                Navigator.of(
                  context,
                ).pushAndRemoveUntil(
                  MaterialPageRoute(
                    builder:
                        (context) =>
                    const LoginPage(),
                  ),

                      (route) =>
                  false,
                );
              },

              style:
              ElevatedButton.styleFrom(
                backgroundColor:
                Colors.red,
              ),

              child: Text(
                'Logout',

                style:
                GoogleFonts.cairo(
                  color:
                  Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // DESKTOP NAV ITEM
  // ============================================================

  Widget _buildNavItem(
      _NavItem item, {
        required bool isSelected,
        required VoidCallback onTap,
      }) {
    return Padding(
      padding:
      const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 2,
      ),

      child: Material(
        color:
        Colors.transparent,

        borderRadius:
        BorderRadius.circular(
          10,
        ),

        child: InkWell(
          onTap: onTap,

          borderRadius:
          BorderRadius.circular(
            10,
          ),

          hoverColor:
          Colors.white
              .withOpacity(0.05),

          splashColor:
          const Color(
            0xFF6366F1,
          ).withOpacity(0.1),

          child:
          AnimatedContainer(
            duration:
            const Duration(
              milliseconds: 100,
            ),

            padding:
            EdgeInsets.symmetric(
              horizontal:
              _isCollapsed
                  ? 12
                  : 16,

              vertical: 12,
            ),

            decoration:
            BoxDecoration(
              color:
              isSelected
                  ? const Color(
                0xFF131B2E,
              )
                  : Colors.transparent,

              borderRadius:
              BorderRadius.circular(
                10,
              ),

              border:
              isSelected
                  ? const Border(
                left:
                BorderSide(
                  color:
                  Color(
                    0xFFB7C8E1,
                  ),
                  width: 4,
                ),
              )
                  : null,
            ),

            child:
            _isCollapsed
                ? Tooltip(
              message:
              item.label,

              child:
              Icon(
                isSelected
                    ? item
                    .activeIcon
                    : item.icon,

                color:
                isSelected
                    ? Colors.white
                    : Colors.white54,

                size: 22,
              ),
            )
                : Row(
              children: [

                Icon(
                  isSelected
                      ? item
                      .activeIcon
                      : item.icon,

                  color:
                  isSelected
                      ? Colors.white
                      : Colors.white54,

                  size: 22,
                ),

                const SizedBox(
                  width: 12,
                ),

                Expanded(
                  child: Text(
                    item.label,

                    style:
                    TextStyle(
                      color:
                      isSelected
                          ? Colors.white
                          : Colors.white54,

                      fontSize: 14,

                      fontWeight:
                      isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),

                if (isSelected)
                  Container(
                    width: 4,
                    height: 4,

                    decoration:
                    const BoxDecoration(
                      color:
                      Color(
                        0xFFB7C8E1,
                      ),

                      shape:
                      BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // USER SECTION
  // ============================================================

  Widget _buildUserSection() {

    // ==========================================================
    // COLLAPSED
    // ==========================================================

    if (_isCollapsed) {
      return Padding(
        padding:
        const EdgeInsets.all(
          12,
        ),

        child: IconButton(
          onPressed:
          _showLogoutDialog,

          icon:
          const Icon(
            Icons.logout,
            color:
            Colors.white54,
          ),

          tooltip:
          'Logout',
        ),
      );
    }

    // ==========================================================
    // EXPANDED
    // ==========================================================

    return Padding(
      padding:
      const EdgeInsets.all(
        12,
      ),

      child: Container(
        padding:
        const EdgeInsets.all(
          12,
        ),

        decoration:
        BoxDecoration(
          color:
          Colors.white
              .withOpacity(0.05),

          borderRadius:
          BorderRadius.circular(
            10,
          ),

          border:
          Border.all(
            color:
            Colors.white
                .withOpacity(
              0.1,
            ),
          ),
        ),

        child: Row(
          children: [

            // ==================================================
            // AVATAR
            // ==================================================

            CircleAvatar(
              radius: 18,

              backgroundColor:
              const Color(
                0xFF6366F1,
              ).withOpacity(
                0.3,
              ),

              child: Text(
                widget
                    .loggedInEmployee!
                    .initials,

                style:
                GoogleFonts.cairo(
                  color:
                  Colors.white,

                  fontWeight:
                  FontWeight.w600,

                  fontSize: 14,
                ),
              ),
            ),

            const SizedBox(
              width: 10,
            ),

            // ==================================================
            // USER NAME
            // ==================================================

            Expanded(
              child: Column(
                crossAxisAlignment:
                CrossAxisAlignment.start,

                mainAxisSize:
                MainAxisSize.min,

                children: [

                  Text(
                    widget
                        .loggedInEmployee!
                        .displayName,

                    style:
                    GoogleFonts.cairo(
                      color:
                      Colors.white,

                      fontSize: 13,

                      fontWeight:
                      FontWeight.w600,
                    ),

                    overflow:
                    TextOverflow.ellipsis,
                  ),

                  if (widget
                      .loggedInEmployee!
                      .role !=
                      null)
                    Text(
                      widget
                          .loggedInEmployee!
                          .role!,

                      style:
                      GoogleFonts.cairo(
                        color:
                        Colors.white54,

                        fontSize: 11,
                      ),

                      overflow:
                      TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),

            // ==================================================
            // MENU
            // ==================================================

            PopupMenuButton<String>(
              color:
              const Color(
                0xFF1E293B,
              ),

              shape:
              RoundedRectangleBorder(
                borderRadius:
                BorderRadius.circular(
                  12,
                ),
              ),

              child:
              const Icon(
                Icons.more_vert,

                color:
                Colors.white54,

                size: 20,
              ),

              onSelected:
                  (value) {

                if (value ==
                    'profile') {
                  setState(() {
                    _selectedIndex =
                        _navItems.indexWhere(
                              (item) =>
                          item.label ==
                              'Profile',
                        );
                  });
                }

                if (value ==
                    'logout') {
                  _showLogoutDialog();
                }
              },

              itemBuilder:
                  (context) =>
              [

                PopupMenuItem(
                  value:
                  'profile',

                  child: Row(
                    children: [

                      const Icon(
                        Icons.person_outline,
                        color:
                        Colors.white70,
                        size: 18,
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      Text(
                        'Profile',

                        style:
                        GoogleFonts.cairo(
                          color:
                          Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),

                PopupMenuItem(
                  value:
                  'logout',

                  child: Row(
                    children: [

                      const Icon(
                        Icons.logout,
                        color:
                        Colors.red,
                        size: 18,
                      ),

                      const SizedBox(
                        width: 12,
                      ),

                      Text(
                        'Logout',

                        style:
                        GoogleFonts.cairo(
                          color:
                          Colors.red,
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
    );
  }

  // ============================================================
  // PAGE ROUTING
  // ============================================================

  Widget _buildPage() {

    // ==========================================================
    // HEAD / ADMIN
    // ==========================================================

    if (_isHead) {
      switch (_selectedIndex) {

        case 0:
          return OrdersPage(
            sapService:
            widget.sapService,
            loggedInEmployee:
            widget.loggedInEmployee,
          );

        case 1:
          return DashboardPage(
            sapService:
            widget.sapService,
          );

        case 2:
          return AnalyticsPage(
            sapService:
            widget.sapService,
          );

        case 3:
          return const DepartmentTrackingPage();

        case 4:
          return ProfilePage(
            employee:
            widget.loggedInEmployee,
          );

        default:
          return OrdersPage(
            sapService:
            widget.sapService,
            loggedInEmployee:
            widget.loggedInEmployee,
          );
      }
    }

    // ==========================================================
    // NORMAL USER
    // ==========================================================

    switch (_selectedIndex) {

      case 0:
        return OrdersPage(
          sapService:
          widget.sapService,
          loggedInEmployee:
          widget.loggedInEmployee,
        );

      case 1:
        return ProfilePage(
          employee:
          widget.loggedInEmployee,
        );

      default:
        return OrdersPage(
          sapService:
          widget.sapService,
          loggedInEmployee:
          widget.loggedInEmployee,
        );
    }
  }
}

// ============================================================
// NAV ITEM MODEL
// ============================================================

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}