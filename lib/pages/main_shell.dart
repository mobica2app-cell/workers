// lib/pages/main_shell.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobitem/pages/analytics_page.dart';
import 'package:mobitem/pages/employee_tracking_page.dart';
import 'package:mobitem/pages/profile_page.dart';
import 'package:universal_html/html.dart' as html;

import '../services/sap_service.dart';
import 'dashboard_page.dart';
import 'department_tracking_page.dart';
import 'login_page.dart';
import 'orders_page.dart';
import 'ai_assistant_page.dart';

class MainShell extends StatefulWidget {
  final SAPMainService sapService;
  final EmployeeAuth? loggedInEmployee;
  final bool guestMode;

  const MainShell({
    Key? key,
    required this.sapService,
    this.loggedInEmployee,
    this.guestMode = false,
  }) : super(key: key);

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _selectedIndex = 0;
  bool _isCollapsed = false;
  bool _aiPanelVisible = false;
  bool _aiMaximized = false;

  // Sidebar logo animation assets. Keep these paths in sync with pubspec.yaml.
  static const String _logoExpandVideo =
      'assets/animations/mobica_logo_forward.mp4';
  static const String _logoCollapseVideo =
      'assets/animations/mobica_logo_reverse.mp4';
  static const String _logoMarkImage = 'assets/images/mobica_m.png';
  static const String _logoFullImage = 'assets/images/logo.png';

  VideoPlayerController? _logoVideoController;
  bool _isSidebarAnimating = false;
  String _logoDebugStatus = 'Logo animations ready';
  String? _logoDebugError;

  @override
  void initState() {
    super.initState();
  }

  void _logLogoVideo(String message) {
    final line = '[SIDEBAR VIDEO] $message';
    debugPrint(line);
    if (mounted) {
      setState(() {
        _logoDebugStatus = message;
      });
    }
  }

  // ============================================================
  // THEME
  // ============================================================

  bool get _isDark =>
      Theme.of(context).brightness == Brightness.dark;

  Color get _backgroundColor =>
      _isDark
          ? const Color(0xFF000000)
          : const Color(0xFFF8FAFC);

  Color get _surfaceColor =>
      _isDark
          ? const Color(0xFF121212)
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
          ? const Color(0xFF2A2A2A)
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
      icon: Icons.people_alt_outlined,
      activeIcon: Icons.people_alt,
      label: 'Employees',
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
    if (widget.guestMode) return [_headNavItems.first];
    return _isHead
        ? _headNavItems
        : _userNavItems;
  }

  // ============================================================
  // TOGGLE SIDEBAR
  // ============================================================

  void _toggleSidebar() {
    if (_isSidebarAnimating) return;

    final expanding = _isCollapsed;
    setState(() {
      _isSidebarAnimating = true;
      _logoDebugStatus = 'Refreshing logo animation asset';
      _logoDebugError = null;
    });

    _playLogoTransition(expanding: expanding);
  }

  Future<void> _playLogoTransition({required bool expanding}) async {
    // A NEW controller is created for every transition. This avoids reusing
    // a completed/stale platform player after seekTo(Duration.zero).
    final assetPath = expanding ? _logoExpandVideo : _logoCollapseVideo;
    VideoPlayerController? controller;
    var listenerAttached = false;
    var transitionStarted = false;
    final transitionStopwatch = Stopwatch();
    const sidebarTransitionDuration = Duration(milliseconds: 300);
    final completed = Completer<void>();

    void listener() {
      if (!mounted || completed.isCompleted || controller == null) return;

      final value = controller!.value;
      if (value.hasError) {
        completed.completeError(
          StateError(value.errorDescription ?? 'Logo animation failed'),
        );
      } else if (value.isCompleted) {
        completed.complete();
      }
    }

    try {
      debugPrint('[SIDEBAR VIDEO] Creating fresh player for $assetPath');
      controller = VideoPlayerController.asset(assetPath);

      // Fully initialize a fresh player before showing it.
      await controller.initialize();
      await controller.setLooping(false);
      await controller.setVolume(0);
      await controller.setPlaybackSpeed(2.0);
      await controller.seekTo(Duration.zero);

      if (!mounted) return;

      // Start the logo video and sidebar width animation together.
      setState(() {
        _logoVideoController = controller;
        _isCollapsed = !expanding;
        _logoDebugStatus =
        'Playing ${expanding ? 'expand' : 'collapse'} animation';
      });
      transitionStarted = true;
      transitionStopwatch.start();

      controller.addListener(listener);
      listenerAttached = true;

      // Start playback only after the fresh controller is visible.
      await controller.play();
      await completed.future.timeout(
        controller.value.duration + const Duration(seconds: 5),
      );

      if (!mounted) return;

      // Keep the sidebar at its new width; replace the video with the
      // destination static logo as soon as playback finishes.
      setState(() {
        _logoVideoController = null;
        _logoDebugStatus = 'Showing destination logo';
      });
    } catch (error, stackTrace) {
      _logoDebugError = error.toString();
      debugPrint('[SIDEBAR VIDEO] Fresh asset playback failed: $error');
      debugPrint('$stackTrace');

      // Keep the UI usable if the video cannot be loaded or played.
      if (mounted) {
        setState(() {
          _logoVideoController = null;
          _isCollapsed = !expanding;
          _logoDebugStatus = 'Video unavailable; showing static logo';
        });
        transitionStarted = true;
        transitionStopwatch.start();
      }
    } finally {
      if (listenerAttached && controller != null) {
        controller.removeListener(listener);
      }

      if (controller != null) {
        try {
          await controller.pause();
        } catch (_) {}
        try {
          await controller.dispose();
        } catch (_) {}
      }

      if (transitionStarted) {
        final remaining =
            sidebarTransitionDuration - transitionStopwatch.elapsed;
        if (remaining > Duration.zero) {
          await Future.delayed(remaining);
        }
      }

      if (mounted) {
        setState(() {
          _logoVideoController = null;
          _isSidebarAnimating = false;
          _logoDebugStatus = 'Ready';
        });
      }
    }
  }

  @override
  void dispose() {
    _logoVideoController?.dispose();
    super.dispose();
  }

  bool get _canUseAi =>
      !widget.guestMode &&
          (widget.loggedInEmployee?.role ?? '').trim().toLowerCase() == 'head' &&
          (widget.loggedInEmployee?.fullName ?? '').trim().toLowerCase() == 'admin' ||
          (widget.loggedInEmployee?.fullName ?? '').trim().toLowerCase() == 'mohamed saied' ;

  void _openAiAssistant() {
    if (!_canUseAi) return;
    setState(() {
      _aiPanelVisible = true;
      _aiMaximized = false;
    });
  }

  void _minimizeAiAssistant() {
    setState(() => _aiPanelVisible = false);
  }

  void _toggleAiMaximized() {
    setState(() => _aiMaximized = !_aiMaximized);
  }

  Widget _withAiOverlay(Widget content) {
    if (!_canUseAi) return content;
    final size = MediaQuery.of(context).size;
    final mobile = size.width < 700;
    final expanded = _aiMaximized;
    final panelWidth = expanded
        ? (mobile ? size.width - 24 : (size.width * .78).clamp(520.0, 980.0))
        : (size.width - 32).clamp(300.0, 420.0);
    final panelHeight = expanded
        ? (size.height - 24).clamp(360.0, 1100.0)
        : (size.height * .72).clamp(400.0, 650.0);

    return Stack(fit: StackFit.expand, children: [
      content,
      Positioned(
        right: expanded && mobile ? 12 : 20,
        left: expanded && mobile ? 12 : null,
        bottom: expanded ? 12 : 20,
        top: expanded ? 12 : null,
        width: expanded && mobile ? null : panelWidth,
        height: expanded ? null : panelHeight,
        child: Offstage(
          offstage: !_aiPanelVisible,
          child: AnimatedOpacity(
            opacity: _aiPanelVisible ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(.22), blurRadius: 34, offset: const Offset(0, 12))],
              ),
              child: AiAssistantPage(
                key: const ValueKey('persistent_mood_ai_chat'),
                embedded: true,
                isMaximized: _aiMaximized,
                onMinimize: _minimizeAiAssistant,
                onToggleMaximize: _toggleAiMaximized,
              ),
            ),
          ),
        ),
      ),
    ]);
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
      floatingActionButton: (_canUseAi && !_aiPanelVisible)
          ? FloatingActionButton.extended(
        heroTag: 'mood_ai_desktop',
        onPressed: _openAiAssistant,
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('MOOD AI'),
      )
          : null,
      body: _withAiOverlay(Row(
        children: [

          // ====================================================
          // SIDEBAR
          // ====================================================

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
              width: _isCollapsed ? 80 : 240,
              decoration: BoxDecoration(
                color: const Color(0xFF08090C),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: Colors.white.withOpacity(0.07),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.16),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
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
                  // CELEBRATION BANNER
                  // ==============================================

                  /*_buildCelebrationBanner(),*/

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
          ),

          // ====================================================
          // MAIN CONTENT
          // ====================================================

          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _surfaceColor,
                    border: Border.all(
                      color: _borderColor.withOpacity(0.75),
                    ),
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(_isDark ? 0.20 : 0.04),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: _buildPage(),
                ),
              ),
            ),
          ),
        ],
      )),
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
      floatingActionButton: (_canUseAi && !_aiPanelVisible)
          ? FloatingActionButton.extended(
        heroTag: 'mood_ai_mobile',
        onPressed: _openAiAssistant,
        backgroundColor: const Color(0xFFDC2626),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.auto_awesome),
        label: const Text('MOOD AI'),
      )
          : null,

      // ========================================================
      // CONTENT
      // ========================================================

      body: _withAiOverlay(SafeArea(
        bottom: false,
        child: _buildPage(),
      )),

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
            const Color(0xFFDC2626)
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
                      0xFFDC2626,
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
    return IgnorePointer(
      ignoring: _isSidebarAnimating,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: _isCollapsed ? 12 : 10,
          vertical: _isCollapsed ? 12 : 14,
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
      ),
    );
  }

  Widget _buildSidebarLogo({required bool expanded}) {
    final controller = _logoVideoController;

    // Keep the destination image mounted and painted underneath the video.
    // When the video ends, removing its layer reveals an already-rendered
    // image instead of waiting for Image.asset to load.
    return Stack(
      fit: StackFit.expand,
      alignment: expanded ? Alignment.centerLeft : Alignment.center,
      children: [
        Image.asset(
          expanded ? _logoFullImage : _logoMarkImage,
          fit: BoxFit.contain,
          alignment: expanded ? Alignment.centerLeft : Alignment.center,
          gaplessPlayback: true,
        ),
        if (controller != null && controller.value.isInitialized)
          FittedBox(
            fit: BoxFit.contain,
            alignment: expanded ? Alignment.centerLeft : Alignment.center,
            child: SizedBox(
              width: controller.value.size.width,
              height: controller.value.size.height,
              child: VideoPlayer(controller),
            ),
          ),
      ],
    );
  }

  // ============================================================
  //   // EXPANDED HEADER
  // ============================================================

  Widget _buildExpandedHeader() {
    return SizedBox(
      height: 116,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Give the full logo/video the entire available header area.
          // The collapse control is overlaid so it does not reduce logo width.
          Padding(
            padding: const EdgeInsets.only(right: 22),
            child: _buildSidebarLogo(expanded: true),
          ),
          if (!_isSidebarAnimating)
            Positioned(
              right: 0,
              top: 0,
              child: IconButton(
                onPressed: _toggleSidebar,
                icon: const Icon(
                  Icons.chevron_left,
                  color: Colors.white54,
                  size: 20,
                ),
                tooltip: 'Collapse',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                visualDensity: VisualDensity.compact,
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // COLLAPSED HEADER
  // ============================================================

  Widget _buildCollapsedHeader() {
    return Column(
      children: [
        SizedBox(
          width: 48,
          height: 48,
          child: _buildSidebarLogo(expanded: false),
        ),
        const SizedBox(height: 8),
        if (!_isSidebarAnimating)
          IconButton(
            onPressed: _toggleSidebar,
            icon: const Icon(
              Icons.chevron_right,
              color: Colors.white54,
              size: 20,
            ),
            splashRadius: 20,
            tooltip: 'Expand',
          ),
      ],
    );
  }

  // ============================================================
  // CLEAR REMEMBER ME
  // ============================================================

  void _clearRememberMe() {
    try {
      html.window.localStorage.remove('remembered_username');
      html.window.localStorage.remove('remembered_password');
      html.window.localStorage.remove('mood_session_token');
    } catch (e) {
      print('Error clearing storage: $e');
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
          14,
        ),

        child: InkWell(
          onTap: onTap,

          borderRadius:
          BorderRadius.circular(
            14,
          ),

          hoverColor:
          Colors.white
              .withOpacity(0.05),

          splashColor:
          const Color(
            0xFFDC2626,
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

            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFFDC2626).withOpacity(0.14)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? const Color(0xFFDC2626).withOpacity(0.30)
                    : Colors.transparent,
                width: 1,
              ),
            ),

            child: LayoutBuilder(
              builder: (context, constraints) {
                // During the 240px <-> 80px sidebar transition, the width
                // changes continuously. Decide from the actual available
                // width rather than the target `_isCollapsed` state, so the
                // expanded Row is never laid out inside the narrow sidebar.
                final showExpandedContent = constraints.maxWidth >= 110;

                if (!showExpandedContent) {
                  return Tooltip(
                    message: item.label,
                    child: Center(
                      child: Icon(
                        isSelected ? item.activeIcon : item.icon,
                        color: isSelected
                            ? const Color(0xFFFF6B6B)
                            : Colors.white60,
                        size: 22,
                      ),
                    ),
                  );
                }

                return Row(
                  children: [
                    Icon(
                      isSelected ? item.activeIcon : item.icon,
                      color: isSelected ? Colors.white : Colors.white54,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white54,
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Container(
                        width: 4,
                        height: 4,
                        decoration: const BoxDecoration(
                          color: Color(0xFFB7C8E1),
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CELEBRATION BANNER
  // ============================================================

  Widget _buildCelebrationBanner() {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: _isCollapsed ? 12 : 14,
        vertical: 10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: _isCollapsed ? 48 : 110,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.05),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
          ),
          child: _isCollapsed
              ? Tooltip(
            message: '6th October Anniversary',
            child: Image.network(
              'https://tcztkkexgzxlurvhibmc.supabase.co/storage/v1/object/public/imagess/Egyptian%20Flag.png',
              fit: BoxFit.cover,
            ),
          )
              : Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                'https://tcztkkexgzxlurvhibmc.supabase.co/storage/v1/object/public/imagess/Egyptian%20Flag.png',
                fit: BoxFit.cover,
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withOpacity(0.65),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: Text(
                  '6th October Anniversary',
                  style: GoogleFonts.cairo(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    shadows: const [
                      Shadow(
                        blurRadius: 4,
                        color: Colors.black54,
                      ),
                    ],
                  ),
                ),
              ),
            ],
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
            size: 20,
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
                0xFFDC2626,
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
            // Logout
            // ==================================================

            IconButton(
              onPressed:
              _showLogoutDialog,

              icon:
              const Icon(
                size: 20,
                Icons.logout,
                color:
                Colors.red,
              ),

              tooltip:
              'Logout',
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
            readOnly: widget.guestMode,
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
          return EmployeeTrackingPage(
            loggedInEmployee:
            widget.loggedInEmployee!,
          );

        case 5:
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
            readOnly: widget.guestMode,
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
          readOnly: widget.guestMode,
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
          readOnly: widget.guestMode,
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

