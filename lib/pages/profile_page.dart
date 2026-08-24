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
      Supabase.instance.client);

  EmployeeAuth? _employee;
  List<_EmployeeWorkItem> _workItems = [];
  List<_EmployeeWorkItem> _filteredWorkItems = [];
  bool _isLoading = true;
  String _workFilter = 'All';
  TabController? _tabController;

  // Theme preference
  bool _isDarkMode = false;
  static const String _themeKey = 'app_theme_preference';

  // Summary counts
  int _totalWork = 0;
  int _salesEngineerCount = 0;
  int _responsibleEngineerCount = 0;
  int _reviewerCount = 0;
  int _correspondenceEngineerCount = 0;

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _chipBackground => _isDark ? const Color(0xFF334155) : Colors.grey.shade100;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _employee = widget.employee;
    _loadWorkData();

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
    _tabController?.dispose();
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
        backgroundColor: value ? const Color(0xFF1E293B) : const Color(0xFF0F172A),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _loadWorkData() async {
    setState(() => _isLoading = true);
    try {
      final sapService = SAPMainService(Supabase.instance.client);
      final allOrders = await sapService.getAllOrders();

      final workItems = <_EmployeeWorkItem>[];
      final employeeName = _employee?.fullName ?? '';

      for (var order in allOrders) {
        // Check Sales Engineer
        if (order.salesEngineer.toLowerCase() == employeeName.toLowerCase()) {
          workItems.add(_EmployeeWorkItem(
            order: order,
            role: 'Sales Engineer',
            roleIcon: Icons.attach_money,
            roleColor: Colors.blue,
          ));
        }
        // Check Responsible Engineer
        if (order.responsibleEngineer != null &&
            order.responsibleEngineer!.toLowerCase() ==
                employeeName.toLowerCase()) {
          workItems.add(_EmployeeWorkItem(
            order: order,
            role: 'Responsible Engineer',
            roleIcon: Icons.engineering,
            roleColor: Colors.orange,
          ));
        }
        // Check Reviewer
        if (order.reviewer != null &&
            order.reviewer!.toLowerCase() == employeeName.toLowerCase()) {
          workItems.add(_EmployeeWorkItem(
            order: order,
            role: 'Reviewer',
            roleIcon: Icons.rate_review,
            roleColor: Colors.purple,
          ));
        }
        // Check Correspondence Engineer (Alternative)
        if (order.correspondenceEngineer != null &&
            order.correspondenceEngineer!.toLowerCase() ==
                employeeName.toLowerCase()) {
          workItems.add(_EmployeeWorkItem(
            order: order,
            role: 'Correspondence Engineer',
            roleIcon: Icons.mail_outline,
            roleColor: Colors.teal,
          ));
        }
      }

      setState(() {
        _workItems = workItems;
        _filteredWorkItems = workItems;
        _totalWork = workItems.length;
        _salesEngineerCount = workItems
            .where((w) => w.role == 'Sales Engineer')
            .length;
        _responsibleEngineerCount = workItems
            .where((w) => w.role == 'Responsible Engineer')
            .length;
        _reviewerCount = workItems
            .where((w) => w.role == 'Reviewer')
            .length;
        _correspondenceEngineerCount = workItems
            .where((w) => w.role == 'Correspondence Engineer')
            .length;
        _isLoading = false;
      });
    } catch (e) {
      print('Error loading work data: $e');
      setState(() => _isLoading = false);
    }
  }

  void _filterWork(String status) {
    setState(() {
      _workFilter = status;
      if (status == 'All') {
        _filteredWorkItems = _workItems;
      } else {
        _filteredWorkItems =
            _workItems.where((w) => w.order.status == status).toList();
      }
    });
  }

  String _formatNumber(double number) {
    if (number == 0) return '0.00';
    final parts = number.toStringAsFixed(2).split('.');
    final buffer = StringBuffer();
    for (int i = 0; i < parts[0].length; i++) {
      if (i > 0 && (parts[0].length - i) % 3 == 0) buffer.write(',');
      buffer.write(parts[0][i]);
    }
    return '${buffer.toString()}.${parts[1]}';
  }

  void _showChangePasswordDialog() {
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) =>
          AlertDialog(
            title: Text('Change Password',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
            content: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: newPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'New Password',
                      labelStyle: GoogleFonts.cairo(),
                      border: const OutlineInputBorder())),
              const SizedBox(height: 12),
              TextField(controller: confirmPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: 'Confirm Password',
                      labelStyle: GoogleFonts.cairo(),
                      border: const OutlineInputBorder())),
            ]),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.cairo())),
              ElevatedButton(
                onPressed: () async {
                  if (newPasswordController.text !=
                      confirmPasswordController.text) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Passwords do not match',
                            style: GoogleFonts.cairo()),
                        backgroundColor: Colors.red));
                    return;
                  }
                  if (newPasswordController.text.length < 4) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text('Password must be at least 4 characters',
                            style: GoogleFonts.cairo()),
                        backgroundColor: Colors.red));
                    return;
                  }
                  final success = await _authService.changePassword(
                      _employee!.id, newPasswordController.text);
                  if (mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        content: Text(success ? 'Password changed!' : 'Failed',
                            style: GoogleFonts.cairo()),
                        backgroundColor: success ? Colors.green : Colors.red));
                  }
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary),
                child: Text(
                    'Change', style: GoogleFonts.cairo(color: Theme.of(context).colorScheme.onPrimary)),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading)
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );

    if (_employee == null) {
      return Scaffold(
        backgroundColor: _backgroundColor,
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.error_outline, size: 64, color: _secondaryTextColor),
            const SizedBox(height: 16),
            Text('Please login first', style: GoogleFonts.cairo(
                fontSize: 18, color: _secondaryTextColor)),
          ]),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _backgroundColor,
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) =>
        [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: const Color(0xFF0F172A),
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF0F172A), Color(0xFF1E293B)])),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            CircleAvatar(radius: 40,
                                backgroundColor: Colors.white,
                                child: Text(_employee!.initials,
                                    style: GoogleFonts.cairo(fontSize: 32,
                                        fontWeight: FontWeight.bold,
                                        color: const Color(0xFF0F172A)))),
                            const SizedBox(width: 16),
                            Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_employee!.fullName,
                                      style: GoogleFonts.cairo(fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Container(padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.2),
                                          borderRadius: BorderRadius.circular(
                                              12)),
                                      child: Text(_employee!.role ?? 'Employee',
                                          style: GoogleFonts.cairo(fontSize: 12,
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600))),
                                ])),
                          ]),
                          const SizedBox(height: 16),
                          Row(children: [
                            _buildStatChip(Icons.work, '$_totalWork Orders'),
                            const SizedBox(width: 12),
                            _buildStatChip(Icons.factory, '${_workItems
                                .map((w) => w.order.factory)
                                .where((f) => f != null)
                                .toSet()
                                .length} Factories'),
                          ]),
                        ]),
                  ),
                ),
              ),
            ),
          ),
          SliverPersistentHeader(pinned: true,
              delegate: _SliverAppBarDelegate(
                TabBar(controller: _tabController,
                    labelColor: Theme.of(context).colorScheme.primary,
                    unselectedLabelColor: _secondaryTextColor,
                    indicatorColor: Theme.of(context).colorScheme.primary,
                    labelStyle: GoogleFonts.cairo(fontWeight: FontWeight.w600,
                        fontSize: 14),
                    tabs: const [Tab(text: 'Profile'), Tab(text: 'My Work'), Tab(
                        text: 'By Role')
                    ]),
                surfaceColor: _surfaceColor,
              )),
        ],
        body: TabBarView(controller: _tabController, children: [
          _buildProfileTab(),
          _buildWorkTab(),
          _buildRoleTab(),
        ]),
      ),
    );
  }

  Widget _buildProfileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Card(
          color: _cardColor,
          child: Padding(padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Employee Information', style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _textColor)),
                const SizedBox(height: 16),
                _buildInfoTile(Icons.person, 'Username', _employee!.username),
                _buildInfoTile(Icons.badge, 'Full Name', _employee!.fullName),
                if (_employee!.department != null) _buildInfoTile(
                    Icons.business, 'Department', _employee!.department!),
                if (_employee!.role != null) _buildInfoTile(
                    Icons.work, 'Role', _employee!.role!),
                if (_employee!.phoneNumber != null) _buildInfoTile(
                    Icons.phone, 'Phone', _employee!.phoneNumber!),
                _buildInfoTile(Icons.calendar_today, 'Joined',
                    DateFormat('MMM dd, yyyy').format(_employee!.createdAt)),
                if (_employee!.lastLogin != null) _buildInfoTile(
                    Icons.login, 'Last Login',
                    DateFormat('MMM dd, yyyy HH:mm').format(
                        _employee!.lastLogin!)),
              ])),
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
                    Text('Appearance', style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: _textColor)),
                  ],
                ),
                const SizedBox(height: 16),
                // Replace the existing SwitchListTile with this
                SwitchListTile(
                  title: Text('Dark Mode', style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: _textColor)),
                  subtitle: Text('Use dark theme throughout the app',
                      style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: _secondaryTextColor)),
                  value: ThemeNotifier.instance.isDarkMode, // Changed from _isDarkMode
                  onChanged: _toggleTheme,
                  secondary: Icon(
                    ThemeNotifier.instance.isDarkMode ? Icons.dark_mode : Icons.light_mode, // Changed from _isDarkMode
                    color: ThemeNotifier.instance.isDarkMode ? Colors.blue : Colors.orange, // Changed from _isDarkMode
                  ),
                  activeColor: Colors.blue,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          color: _cardColor,
          child: Padding(padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Work Summary', style: GoogleFonts.cairo(fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _textColor)),
                const SizedBox(height: 16),
                Row(children: [
                  _buildSummaryCard(
                      'Total', '$_totalWork', Icons.work, Colors.blue),
                  const SizedBox(width: 12),
                  _buildSummaryCard(
                      'Sales Eng.', '$_salesEngineerCount', Icons.attach_money,
                      Colors.green),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _buildSummaryCard('Resp. Eng.', '$_responsibleEngineerCount',
                      Icons.engineering, Colors.orange),
                  const SizedBox(width: 12),
                  _buildSummaryCard(
                      'Reviewer', '$_reviewerCount', Icons.rate_review,
                      Colors.purple),
                ]),
              ])),
        ),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity,
            child: OutlinedButton.icon(onPressed: _showChangePasswordDialog,
                icon: const Icon(Icons.lock_outline),
                label: Text('Change Password', style: GoogleFonts.cairo()),
                style: OutlinedButton.styleFrom(
                    foregroundColor: _textColor,
                    side: BorderSide(color: _borderColor),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))))),
      ]),
    );
  }

  Widget _buildWorkTab() {
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal, child: Row(children: [
          _buildFilterChip('All'),
          _buildFilterChip('Unknown'),
          _buildFilterChip('مطلوب اكوادها الاسترشاديه'),
          _buildFilterChip('Drawing Submittal'),
          _buildFilterChip('Approval'),
          _buildFilterChip('Done'),
        ])),
      ),
      Expanded(
        child: _filteredWorkItems.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.work_off, size: 64, color: _secondaryTextColor),
              const SizedBox(height: 16),
              Text('No work found', style: GoogleFonts.cairo(
                  fontSize: 16, color: _secondaryTextColor))
            ]))
            : ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _filteredWorkItems.length,
            itemBuilder: (context, index) =>
                _buildWorkCard(_filteredWorkItems[index])),
      ),
    ]);
  }

  Widget _buildRoleTab() {
    final roles = [
      'Sales Engineer',
      'Responsible Engineer',
      'Reviewer',
      'Correspondence Engineer'
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: roles.length,
      itemBuilder: (context, index) {
        final role = roles[index];
        final items = _workItems.where((w) => w.role == role).toList();
        if (items.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
                color: items.first.roleColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: items.first.roleColor.withOpacity(0.3))),
            child: Row(children: [
              Icon(
                  items.first.roleIcon, color: items.first.roleColor, size: 20),
              const SizedBox(width: 8),
              Text('$role (${items.length})', style: GoogleFonts.cairo(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: items.first.roleColor)),
            ]),
          ),
          const SizedBox(height: 8),
          ...items.map((item) =>
              Card(
                color: _cardColor,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: CircleAvatar(
                      backgroundColor: item.roleColor.withOpacity(0.1),
                      child: Icon(
                          item.roleIcon, color: item.roleColor, size: 18)),
                  title: Text(item.order.description, style: GoogleFonts.cairo(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _textColor),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      '${item.order.designOrder} • ${item.order.factory ??
                          "N/A"}', style: GoogleFonts.cairo(
                      fontSize: 11, color: _secondaryTextColor)),
                  trailing: Container(padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _getStatusColor(item
                          .order.status).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12)),
                      child: Text(item.order.status.length > 15 ? '${item.order
                          .status.substring(0, 13)}...' : item.order.status,
                          style: GoogleFonts.cairo(fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _getStatusColor(item.order.status)))),
                ),
              )),
          const SizedBox(height: 16),
        ]);
      },
    );
  }

  Widget _buildWorkCard(_EmployeeWorkItem item) {
    return Card(
      color: _cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: item.roleColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4)),
                child: Row(mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(item.roleIcon, size: 12, color: item.roleColor),
                      const SizedBox(width: 4),
                      Text(item.role, style: GoogleFonts.cairo(fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: item.roleColor))
                    ])),
            const SizedBox(width: 8),
            Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: _getStatusColor(item.order.status).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(item.order.status, style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(item.order.status)))),
          ]),
          const SizedBox(height: 10),
          Text(item.order.description, style: GoogleFonts.cairo(fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _textColor),
              maxLines: 2,
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          Row(children: [
            _buildInfoChip(Icons.qr_code, item.order.productCode),
            const SizedBox(width: 8),
            _buildInfoChip(Icons.receipt, item.order.designOrder),
            const SizedBox(width: 8),
            _buildInfoChip(Icons.factory, item.order.factory ?? 'N/A'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            _buildInfoChip(Icons.person, item.order.customerName),
            const SizedBox(width: 8),
            _buildInfoChip(
                Icons.attach_money, '\$${_formatNumber(item.order.value)}'),
          ]),
          if (item.order.deliveryDate != null) ...[
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.local_shipping, size: 12, color: _secondaryTextColor),
              const SizedBox(width: 4),
              Text('Delivery: ${item.order.deliveryDate}',
                  style: GoogleFonts.cairo(
                      fontSize: 11, color: _secondaryTextColor))
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: _chipBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _borderColor)),
        child: Row(mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 11, color: _secondaryTextColor),
              const SizedBox(width: 3),
              Text(text, style: GoogleFonts.cairo(fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: _secondaryTextColor))
            ]));
  }

  Widget _buildInfoTile(IconData icon, String label, String value,
      {Color? valueColor}) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
      Icon(icon, size: 20, color: _secondaryTextColor),
      const SizedBox(width: 12),
      Text(label, style: GoogleFonts.cairo(
          fontSize: 14, color: _secondaryTextColor)),
      const Spacer(),
      Text(value, style: GoogleFonts.cairo(fontSize: 14,
          fontWeight: FontWeight.w600,
          color: valueColor ?? _textColor)),
    ]));
  }

  Widget _buildSummaryCard(String title, String value, IconData icon,
      Color color) {
    return Expanded(child: Container(padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 24), const SizedBox(height: 8),
          Text(value, style: GoogleFonts.cairo(
              fontSize: 24, fontWeight: FontWeight.bold, color: color)),
          Text(title, style: GoogleFonts.cairo(fontSize: 12, color: color)),
        ])));
  }

  Widget _buildFilterChip(String status) {
    final isSelected = _workFilter == status;
    return Padding(padding: const EdgeInsets.only(right: 8),
        child: FilterChip(selected: isSelected,
            label: Text(
                status.length > 20 ? '${status.substring(0, 18)}...' : status,
                style: GoogleFonts.cairo(fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : _textColor)),
            onSelected: (selected) => _filterWork(status),
            selectedColor: Theme.of(context).colorScheme.primary,
            checkmarkColor: Colors.white,
            backgroundColor: _surfaceColor,
            side: BorderSide(
                color: isSelected ? Theme.of(context).colorScheme.primary : _borderColor))
    );
  }

  Widget _buildStatChip(IconData icon, String label) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text(label, style: GoogleFonts.cairo(fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w600))
            ]));
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Done':
        return Colors.green;
      case 'Approval':
        return Colors.green;
      case 'Unknown':
        return _isDark ? Colors.grey.shade400 : Colors.grey;
      default:
        return Colors.orange;
    }
  }
}

class _EmployeeWorkItem {
  final SAPMainOrder order;
  final String role;
  final IconData roleIcon;
  final Color roleColor;

  _EmployeeWorkItem(
      {required this.order, required this.role, required this.roleIcon, required this.roleColor});
}

class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar _tabBar;
  final Color surfaceColor;

  _SliverAppBarDelegate(this._tabBar, {required this.surfaceColor});

  @override double get minExtent => _tabBar.preferredSize.height;

  @override double get maxExtent => _tabBar.preferredSize.height;

  @override Widget build(BuildContext context, double shrinkOffset,
      bool overlapsContent) => Container(color: surfaceColor, child: _tabBar);

  @override bool shouldRebuild(_SliverAppBarDelegate oldDelegate) => false;
}

