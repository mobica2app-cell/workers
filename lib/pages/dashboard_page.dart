// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/track_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/sap_service.dart';
import '../main.dart';


class DashboardPage extends StatefulWidget {
  final SAPMainService sapService;

  const DashboardPage({Key? key, required this.sapService}) : super(key: key);

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final Set<String> _selectedStatusFilters = <String>{};
  bool _statusFiltersInitialized = false;
  int? _hoveredPieIndex;

  String _stageGraphGrouping = 'factory';
  final ScrollController _stageGraphScrollController = ScrollController();
  final Set<String> _selectedSubmittalGraphStatuses = {
    ..._beforeApprovalStatuses,
  };
  final Set<String> _selectedApprovalGraphStatuses = {
    ..._approvalStatuses,
  };
  final Set<String> _selectedManufacturingGraphStatuses = {
    ..._manufacturingStatuses,
  };


  bool _isLoading = true;

  // Stats
  int _totalOrders = 0;
  double _totalValue = 0;
  double _totalQuantity = 0;
  int _totalEmployees = 0;
  int _totalFactories = 0;

// Add these fields near the other fields
  Map<String, double> _statusValues = {};
  Map<String, double> _statusQuantities = {};

  // Status distribution
  Map<String, int> _statusDistribution = {};


  // Recent orders
  List<SAPMainOrder> _recentOrders = [];

  // Source data used by the dashboard date filter.
  List<SAPMainOrder> _allOrders = [];
  List<EmployeeAuth> _allEmployees = [];
  List<Map<String, dynamic>> _auditLogs = [];

  // Factory/SLoc descriptions from Supabase factory_names (same mapping as Orders page).
  Map<String, String> _factoryDescriptions = {};

  // Inclusive SAP created_at date range.
  DateTime? _startDate;
  DateTime? _endDate;

  // Orders this month
  int _ordersThisMonth = 0;

  // Approach and Manufacturing data
  List<SAPMainOrder> _beforeApprovalOrders = [];
  List<SAPMainOrder> _approvalOrders = [];
  List<SAPMainOrder> _manufacturingOrders = [];
  double _beforeApprovalValue = 0;
  double _approvalValue = 0;
  double _manufacturingValue = 0;
  double _beforeApprovalQuantity = 0;
  double _approvalQuantity = 0;
  double _manufacturingQuantity = 0;

  // Employee auth service
  final EmployeeAuthService _authService = EmployeeAuthService(
    Supabase.instance.client,
  );

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF000000) : const Color(0xFFF8FAFC);
  Color get _surfaceColor => _isDark ? const Color(0xFF121212) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFF5F5F5) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFFAAAAAA) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE2E8F0);
  Color get _cardColor => _isDark ? const Color(0xFF121212) : Colors.white;

  // Status lists
  static const List<String> _beforeApprovalStatuses = [
    'Drawing Submittal',
    'modifications submitted',
  ];

  static const List<String> _approvalStatuses = [
    'Approval',
    'Sales',
    'As Built',
    'Partition Editing',
  ];

  static const List<String> _manufacturingStatuses = [
    'Manufacturing Drawing',
    'Review',
    'partation  master data',
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);

    try {
      final orders = await widget.sapService.getAllOrders();
      final employees = await _authService.getAllEmployees();

      // Match Orders page factory labels: code (description).
      try {
        final factoryRows = await Supabase.instance.client
            .from('factory_names')
            .select('s_loc, description');
        final descriptions = <String, String>{};
        for (final row in factoryRows) {
          final code = row['s_loc']?.toString().trim() ?? '';
          final description = row['description']?.toString().trim() ?? '';
          if (code.isNotEmpty) {
            descriptions[code.toLowerCase()] = description;
          }
        }
        _factoryDescriptions = descriptions;
      } catch (e) {
        debugPrint('Error loading factory names for dashboard: $e');
      }

      // The dashboard date filter is based on SAP main orders.created_at.
      _allOrders = orders;
      _allEmployees = employees;
      _auditLogs = [];

      _recalculateDashboard();
    } catch (e) {
      debugPrint('Error loading dashboard: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  DateTime? _parseAuditDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString())?.toLocal();
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  bool _isDateInRange(DateTime date) {
    final d = _dateOnly(date);

    if (_startDate != null && d.isBefore(_dateOnly(_startDate!))) {
      return false;
    }

    if (_endDate != null && d.isAfter(_dateOnly(_endDate!))) {
      return false;
    }

    return true;
  }

  /// Returns the unique order IDs that had a matching STATUS audit event
  /// inside the selected date range.
  ///
  /// Important:
  /// - We count an order ID only once per section, even if it has multiple
  ///   audit rows in the range.
  /// - We use audit.new_value, not the order's CURRENT status. This means an
  ///   order that moved from Approach to Manufacturing during the period is
  ///   still counted in Approach for the date on which it entered that stage.
  Set<String> _auditOrderIdsForStatuses(List<String>? allowedStatuses) {
    final ids = <String>{};

    for (final log in _auditLogs) {
      final orderId = log['order_id']?.toString().trim() ?? '';
      if (orderId.isEmpty ||
          orderId == 'bulk_delete' ||
          orderId == 'import_batch') {
        continue;
      }

      final newValue = log['new_value']?.toString().trim() ?? '';

      if (allowedStatuses != null && !allowedStatuses.contains(newValue)) {
        continue;
      }

      final changedAt = _parseAuditDate(log['changed_at']);
      if (changedAt == null) continue;

      if (_startDate != null || _endDate != null) {
        if (!_isDateInRange(changedAt)) continue;
      }

      ids.add(orderId);
    }

    return ids;
  }

  /// Returns the actual SAP orders represented by unique audit order IDs.
  List<SAPMainOrder> _ordersForSection(
      List<SAPMainOrder> orders,
      List<String>? statuses,
      ) {
    // No date filter: keep the original dashboard meaning.
    if (_startDate == null && _endDate == null) {
      if (statuses == null) {
        return List<SAPMainOrder>.from(orders);
      }

      return orders
          .where((o) => statuses.contains(o.status))
          .toList();
    }

    final auditIds = _auditOrderIdsForStatuses(statuses);

    // Return ONLY the SAP orders whose CURRENT status is still one of
    // the requested statuses. This matches the dashboard count logic and
    // the Supabase query:
    //
    // audit: order entered the status during the selected date range
    // AND
    // sap_main_orders: current status is still that status.
    return orders.where((order) {
      final orderId = order.id.toString().trim();

      if (!auditIds.contains(orderId)) {
        return false;
      }

      if (statuses == null) {
        return true;
      }

      return statuses.contains(order.status.trim());
    }).toList();
  }

  void _recalculateDashboard() {
    final employees = _allEmployees;

    // The date filter uses SAP main order.created_at.
    final filteredOrders = _allOrders.where((order) {
      final createdAt = order.createdAt;
      if (createdAt == null) return false;
      return _startDate == null && _endDate == null
          ? true
          : _isDateInRange(createdAt);
    }).toList();

    final statusDist = <String, int>{};
    final statusValues = <String, double>{};
    final statusQuantities = <String, double>{};
    final factories = <String>{};

    double totalVal = 0;
    double totalQty = 0;

    final approachOrders = <SAPMainOrder>[];
    final approvalOrders = <SAPMainOrder>[];
    final manufacturingOrders = <SAPMainOrder>[];
    double approachVal = 0;
    double approvalVal = 0;
    double manufacturingVal = 0;
    double approachQty = 0;
    double approvalQty = 0;
    double manufacturingQty = 0;

    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    for (final order in filteredOrders) {
      final status = order.status.isEmpty ? 'Unknown' : order.status;

      statusDist[status] = (statusDist[status] ?? 0) + 1;
      statusValues[status] = (statusValues[status] ?? 0) + order.value;
      statusQuantities[status] =
          (statusQuantities[status] ?? 0) + order.quantity;

      if (order.factory != null && order.factory!.isNotEmpty) {
        factories.add(order.factory!);
      }

      totalVal += order.value;
      totalQty += order.quantity;

      if (order.createdAt != null &&
          '${order.createdAt!.year}-${order.createdAt!.month.toString().padLeft(2, '0')}' ==
              currentMonth) {
        // Count is based on created_at, consistent with the dashboard date
        // filter.
      }

      if (_beforeApprovalStatuses.contains(order.status)) {
        approachOrders.add(order);
        approachVal += order.value;
        approachQty += order.quantity;
      }

      if (_approvalStatuses.contains(order.status)) {
        approvalOrders.add(order);
        approvalVal += order.value;
        approvalQty += order.quantity;
      }

      if (_manufacturingStatuses.contains(order.status)) {
        manufacturingOrders.add(order);
        manufacturingVal += order.value;
        manufacturingQty += order.quantity;
      }
    }

    final thisMonth = filteredOrders.where((order) {
      final createdAt = order.createdAt;
      if (createdAt == null) return false;
      return createdAt.year == now.year && createdAt.month == now.month;
    }).length;

    final recent = List<SAPMainOrder>.from(filteredOrders)
      ..sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));

    if (!mounted) return;

    setState(() {
      _totalOrders = filteredOrders.length;
      _totalValue = totalVal;
      _totalQuantity = totalQty;
      _totalEmployees = employees.length;
      _totalFactories = factories.length;
      _statusDistribution = statusDist;
      _statusValues = statusValues;
      _statusQuantities = statusQuantities;
      _recentOrders = recent.take(8).toList();
      _ordersThisMonth = thisMonth;
      _beforeApprovalOrders = approachOrders;
      _approvalOrders = approvalOrders;
      _manufacturingOrders = manufacturingOrders;
      _beforeApprovalValue = approachVal;
      _approvalValue = approvalVal;
      _manufacturingValue = manufacturingVal;
      _beforeApprovalQuantity = approachQty;
      _approvalQuantity = approvalQty;
      _manufacturingQuantity = manufacturingQty;
      _isLoading = false;
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

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Done':
        return Colors.green;
      case 'Approval':
        return Colors.green;
      case 'Drawing Submittal':
        return Colors.purple;
      case 'Manufacturing Drawing':
        return Colors.indigo;
      case 'Review':
        return Colors.amber;
      case 'Sales':
        return Colors.deepOrange;
      case 'As Built':
        return Colors.brown;
      case 'Master Data':
        return Colors.cyan;
      case 'partation  master data':
        return Colors.deepPurple;
      case 'ادارة تصميم المنتجات':
        return Colors.teal;
      case 'الادارة الهندسه':
        return Colors.blueGrey;
      case 'design studio':
        return Colors.pink;
      case 'modifications submitted':
        return Colors.lightBlue;
      case 'Unknown':
        return _isDark ? Colors.grey.shade400 : Colors.grey;
      default:
        return Colors.orange;
    }
  }


  void _showStatusOrders(String status) {
    // Keep the dashboard's existing filter/count logic.
    // Show exactly the orders returned by _ordersForSection().
    final statusOrders = _ordersForSection(_allOrders, [status]);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.85,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            // =========================
            // HEADER
            // =========================
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),

                  Expanded(
                    child: Text(
                      '$status (${statusOrders.length} orders)',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                  ),

                  // Close button
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: Icon(
                      Icons.close,
                      color: _secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),

            // =========================
            // FILTER INFO
            // =========================
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              color: _getStatusColor(status).withOpacity(0.05),
              child: Row(
                children: [
                  Icon(
                    Icons.filter_alt_outlined,
                    size: 16,
                    color: _getStatusColor(status),
                  ),
                  const SizedBox(width: 8),

                  Expanded(
                    child: Text(
                      _hasDateRange
                          ? 'Orders ${_getDateFilterLabel()}'
                          : 'Orders • All Time',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _getStatusColor(status),
                      ),
                    ),
                  ),

                  Text(
                    '${statusOrders.length}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _getStatusColor(status),
                    ),
                  ),
                ],
              ),
            ),

            // =========================
            // ORDERS
            // =========================
            Expanded(
              child: statusOrders.isEmpty
                  ? Center(
                child: Text(
                  'No orders found',
                  style: GoogleFonts.cairo(
                    color: _secondaryTextColor,
                  ),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: statusOrders.length,
                itemBuilder: (context, index) {
                  final order = statusOrders[index];
                  final deptColor = _getStatusColor(status);

                  return Card(
                    color: _cardColor,
                    margin: const EdgeInsets.only(bottom: 8),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: deptColor.withOpacity(0.3),
                      ),
                    ),

                    // ==========================================
                    // CLICK ORDER -> OPEN OrderTrackingPage
                    // ==========================================
                    child: InkWell(
                      onTap: () {
                        // Close the bottom sheet first
                        Navigator.pop(sheetContext);

                        // Open the selected order
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderTrackingPage(
                              order: order,
                            ),
                          ),
                        );
                      },
                      borderRadius: BorderRadius.circular(10),

                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            // =========================
                            // DESCRIPTION + STATUS
                            // =========================
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    order.description.isNotEmpty
                                        ? order.description
                                        : 'No description',
                                    style: GoogleFonts.cairo(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: _textColor,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),

                                const SizedBox(width: 8),

                                Container(
                                  padding:
                                  const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: deptColor.withOpacity(0.1),
                                    borderRadius:
                                    BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    status,
                                    style: GoogleFonts.cairo(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: deptColor,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 8),

                            // =========================
                            // DESIGN ORDER + CONTRACT
                            // =========================
                            Row(
                              children: [
                                _buildTaskInfo(
                                  Icons.receipt,
                                  order.designOrder,
                                ),
                                const SizedBox(width: 12),
                                _buildTaskInfo(
                                  Icons.description,
                                  order.contractNumber,
                                ),
                              ],
                            ),

                            const SizedBox(height: 4),

                            // =========================
                            // QTY + VALUE
                            // =========================
                            Row(
                              children: [
                                _buildTaskInfo(
                                  Icons.inventory_2,
                                  'QTY: ${order.quantity} ${order.unitOfMeasure}',
                                ),
                                const SizedBox(width: 12),
                                _buildTaskInfo(
                                  Icons.attach_money,
                                  '\$${_formatNumber(order.value)}',
                                ),
                              ],
                            ),

                            const SizedBox(height: 4),

                            // =========================
                            // FACTORY + CUSTOMER
                            // =========================
                            Row(
                              children: [
                                _buildTaskInfo(
                                  Icons.factory,
                                  order.factory ?? 'N/A',
                                ),

                                const SizedBox(width: 12),

                                Expanded(
                                  child: _buildTaskInfo(
                                    Icons.person,
                                    order.customerName,
                                  ),
                                ),

                                Icon(
                                  Icons.chevron_right,
                                  size: 16,
                                  color: _secondaryTextColor,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDateFilterLabel() {
    if (!_hasDateRange) return 'in All Time';

    if (_startDate != null && _endDate != null) {
      return 'from ${_formatFilterDate(_startDate)} to ${_formatFilterDate(_endDate)}';
    }

    if (_startDate != null) {
      return 'from ${_formatFilterDate(_startDate)} onward';
    }

    return 'up to ${_formatFilterDate(_endDate)}';
  }

  Widget _buildTaskInfo(IconData icon, String text) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: _secondaryTextColor),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: _secondaryTextColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _stageGraphScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      )
          : SingleChildScrollView(
        padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 12 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Text(
                  'Dashboard',
                  style: GoogleFonts.cairo(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('EEEE, MMMM d, yyyy').format(DateTime.now()),
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: _secondaryTextColor,
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  onPressed: _loadDashboardData,
                  icon: Icon(Icons.refresh, color: _secondaryTextColor),
                  tooltip: 'Refresh',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Comparison Section
            _buildComparisonSection(),
            const SizedBox(height: 24),

            // Stage status analytics
            _buildStageStatusGraph(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Icon(
            Icons.date_range_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 21,
          ),
          const SizedBox(width: 10),
          Text(
            'Created Date',
            style: GoogleFonts.cairo(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: _textColor,
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: _buildDateField(
              label: 'Start Date',
              date: _startDate,
              icon: Icons.calendar_month,
              onTap: _pickStartDate,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildDateField(
              label: 'End Date',
              date: _endDate,
              icon: Icons.event,
              onTap: _pickEndDate,
            ),
          ),
          if (_hasDateRange) ...[
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Clear dates',
              onPressed: _clearDateRange,
              icon: Icon(
                Icons.clear,
                color: _secondaryTextColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? _endDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'SELECT START DATE',
    );
    if (picked == null) return;

    final date = DateTime(picked.year, picked.month, picked.day);
    if (_endDate != null && date.isAfter(_dateOnly(_endDate!))) {
      _showSnackBar('Start date cannot be after end date');
      return;
    }

    setState(() => _startDate = date);
    _recalculateDashboard();
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate ?? DateTime.now(),
      firstDate: _startDate ?? DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'SELECT END DATE',
    );
    if (picked == null) return;

    final date = DateTime(picked.year, picked.month, picked.day);
    if (_startDate != null && date.isBefore(_dateOnly(_startDate!))) {
      _showSnackBar('End date cannot be before start date');
      return;
    }

    setState(() => _endDate = date);
    _recalculateDashboard();
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
    _recalculateDashboard();
  }

  String _formatFilterDate(DateTime? date) {
    if (date == null) return 'Select date';
    return DateFormat('dd MMM yyyy').format(date);
  }

  bool get _hasDateRange => _startDate != null || _endDate != null;

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.cairo(
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildDateField({
    required String label,
    required DateTime? date,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: _surfaceColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: date != null
                ? Theme.of(context).colorScheme.primary
                : _borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: date != null
                  ? Theme.of(context).colorScheme.primary
                  : _secondaryTextColor,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                  Text(
                    _formatFilterDate(date),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: _textColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 17,
              color: _secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComparisonSection() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Breakdown', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w700, color: _textColor)),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050
                  ? 3
                  : constraints.maxWidth >= 620
                  ? 2
                  : 1;
              final gap = 14.0;
              final cardWidth = (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(width: cardWidth, child: _buildComparisonColumn(
                    title: 'Submittal', icon: Icons.draw, color: Colors.purple,
                    orderCount: _beforeApprovalOrders.length, totalValue: _beforeApprovalValue,
                    totalQuantity: _beforeApprovalQuantity, statuses: _beforeApprovalStatuses,
                  )),
                  SizedBox(width: cardWidth, child: _buildComparisonColumn(
                    title: 'Approval', icon: Icons.approval, color: Colors.green,
                    orderCount: _approvalOrders.length, totalValue: _approvalValue,
                    totalQuantity: _approvalQuantity, statuses: _approvalStatuses,
                  )),
                  SizedBox(width: cardWidth, child: _buildComparisonColumn(
                    title: 'Manufacturing', icon: Icons.precision_manufacturing, color: Colors.orange,
                    orderCount: _manufacturingOrders.length, totalValue: _manufacturingValue,
                    totalQuantity: _manufacturingQuantity, statuses: _manufacturingStatuses,
                  )),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonColumn({
    required String title,
    required IconData icon,
    required Color color,
    required int orderCount,
    required double totalValue,
    required double totalQuantity,
    required List<String>? statuses,
  })
  {
    return Container(
      height: 520,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.cairo(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildComparisonRow('Orders', '$orderCount', color),
          const SizedBox(height: 8),
          _buildComparisonRow('Value', '\$${_formatNumber(totalValue)}', color),
          const SizedBox(height: 8),
          _buildComparisonRow('QTY', totalQuantity.toStringAsFixed(0), color),
          const SizedBox(height: 16),
          if (statuses != null && statuses.isNotEmpty) ...[
            Divider(color: color.withOpacity(0.3)),
            const SizedBox(height: 8),
            Text(
              'Statuses (${statuses.length})',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _secondaryTextColor,
              ),
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final counts = statuses
                    .map((status) => _statusDistribution[status] ?? 0)
                    .toList();
                final total = counts.fold<int>(0, (sum, count) => sum + count);

                return Column(
                  children: [
                    SizedBox(
                      height: 170,
                      child: Center(
                        child: SizedBox(
                          width: 170,
                          height: 170,
                          child: PieChart(
                            PieChartData(
                              startDegreeOffset: -90,
                              sectionsSpace: 3,
                              centerSpaceRadius: 42,
                              sections: statuses.asMap().entries.map((entry) {
                                final status = entry.value;
                                final count = counts[entry.key];
                                final percent = total == 0 ? 0.0 : count / total * 100;
                                return PieChartSectionData(
                                  value: count > 0 ? count.toDouble() : 0.0001,
                                  color: _getStatusColor(status),
                                  radius: 28,
                                  title: '',
                                  titleStyle: const TextStyle(
                                    color: Colors.transparent,
                                    fontSize: 0,
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      '$total orders',
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...statuses.asMap().entries.map((entry) {
                      final status = entry.value;
                      final count = counts[entry.key];
                      final percent = total == 0 ? 0.0 : count / total * 100;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _getStatusColor(status),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                status,
                                style: GoogleFonts.cairo(
                                  fontSize: 10,
                                  color: _secondaryTextColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${percent.toStringAsFixed(1)}%',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _textColor,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '$count',
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                color: _secondaryTextColor,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildComparisonRow(String label, String value, Color color) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.cairo(
            fontSize: 12,
            color: _secondaryTextColor,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: _textColor,
          ),
        ),
      ],
    );
  }




  void _showStageGraphOrders({
    required String category,
    required String status,
    required List<String> Function(SAPMainOrder) categoriesForOrder,
  }) {
    final matchingOrders = _allOrders.where((order) {
      return order.status.trim() == status &&
          categoriesForOrder(order).contains(category);
    }).toList()
      ..sort((a, b) => (b.orderDate ?? '').compareTo(a.orderDate ?? ''));

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.of(sheetContext).size.height * 0.82,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          category,
                          style: GoogleFonts.cairo(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: _textColor,
                          ),
                        ),
                        Text(
                          '$status • ${matchingOrders.length} orders',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: _getStatusColor(status),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: Icon(Icons.close, color: _secondaryTextColor),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _borderColor),
            Expanded(
              child: matchingOrders.isEmpty
                  ? Center(
                child: Text('No orders found',
                    style: GoogleFonts.cairo(color: _secondaryTextColor)),
              )
                  : ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: matchingOrders.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final order = matchingOrders[index];
                  return Card(
                    color: _cardColor,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: _borderColor),
                    ),
                    child: ListTile(
                      title: Text(
                        order.description.isEmpty
                            ? 'No description'
                            : order.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                      ),
                      subtitle: Text(
                        'Order: ${order.designOrder}  •  Contract: ${order.contractNumber}\n'
                            'Factory: ${order.factory ?? 'N/A'}  •  Qty: ${order.quantity}',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          color: _secondaryTextColor,
                        ),
                      ),
                      trailing: Icon(Icons.chevron_right,
                          color: _secondaryTextColor),
                      onTap: () {
                        Navigator.pop(sheetContext);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderTrackingPage(order: order),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStageStatusGraph() {
    final stageStatuses = <String, List<String>>{
      'Submittal': _beforeApprovalStatuses,
      'Approval': _approvalStatuses,
      'Manufacturing': _manufacturingStatuses,
    };
    final selectedByStage = <String, Set<String>>{
      'Submittal': _selectedSubmittalGraphStatuses,
      'Approval': _selectedApprovalGraphStatuses,
      'Manufacturing': _selectedManufacturingGraphStatuses,
    };
    final stageColors = <String, Color>{
      'Submittal': Colors.purple,
      'Approval': Colors.green,
      'Manufacturing': Colors.orange,
    };

    List<String> categoriesForOrder(SAPMainOrder order) {
      switch (_stageGraphGrouping) {
        case 'date':
        // Group by SAP order_date by month (chronological key: yyyy-MM).
          final rawOrderDate = order.orderDate?.trim() ?? '';
          final parsedOrderDate = DateTime.tryParse(rawOrderDate);
          return [
            parsedOrderDate == null
                ? (rawOrderDate.isEmpty ? 'Unknown date' : rawOrderDate)
                : DateFormat('yyyy-MM').format(parsedOrderDate),
          ];
        case 'employee':
        // Count each order under one employee only. Never use sales_engineer.
        // The model has no dedicated assignedEmployee property, so use the
        // correspondence employee as the assigned-person field; if empty,
        // fall back to responsible_engineer.
          bool isValidEmployee(String value) {
            final normalized = value.trim().toLowerCase();
            return normalized.isNotEmpty &&
                normalized != 'null' &&
                normalized != 'n/a' &&
                normalized != 'none' &&
                normalized != '-';
          }

          final assignedEmployee = order.correspondenceEngineer?.trim() ?? '';
          if (isValidEmployee(assignedEmployee)) {
            return [assignedEmployee];
          }

          final responsibleEngineer = order.responsibleEngineer?.trim() ?? '';
          return isValidEmployee(responsibleEngineer)
              ? [responsibleEngineer]
              : ['Unassigned'];
        case 'factory':
        default:
          final factory = order.factory?.trim() ?? '';
          if (factory.isEmpty) return ['Unknown factory'];
          final description =
              _factoryDescriptions[factory.toLowerCase()]?.trim() ?? '';
          return [
            description.isEmpty ? factory : description,
          ];
      }
    }

    final activeStatuses = <String>[
      for (final stage in stageStatuses.keys)
        ...stageStatuses[stage]!.where(selectedByStage[stage]!.contains),
    ];

    final categories = <String>{};
    for (final order in _allOrders) {
      if (activeStatuses.contains(order.status.trim())) {
        categories.addAll(categoriesForOrder(order));
      }
    }
    final sortedCategories = categories.toList()..sort();
    // Keep every category; the chart scrolls horizontally when needed.
    final visibleCategories = sortedCategories;

    final selectedCount = selectedByStage.values
        .fold<int>(0, (sum, selected) => sum + selected.length);

    Widget stageFilter(String stage, List<String> statuses) {
      final selected = selectedByStage[stage]!;
      final color = stageColors[stage]!;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
        decoration: BoxDecoration(
          color: color.withOpacity(0.045),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stage,
                    style: GoogleFonts.cairo(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Checkbox(
                  value: statuses.every(selected.contains),
                  tristate: true,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onChanged: (value) => setState(() {
                    if (value == true) {
                      selected.addAll(statuses);
                    } else {
                      selected.removeAll(statuses);
                    }
                  }),
                ),
              ],
            ),
            ...statuses.map((status) => CheckboxListTile(
              dense: true,
              minVerticalPadding: 0,
              contentPadding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(
                status,
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  color: _textColor,
                ),
              ),
              value: selected.contains(status),
              activeColor: color,
              onChanged: (checked) => setState(() {
                if (checked == true) {
                  selected.add(status);
                } else {
                  selected.remove(status);
                }
              }),
            )),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _isDark
                ? Colors.black.withOpacity(0.25)
                : Colors.black.withOpacity(0.035),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Text(
                'Stage Status Analytics',
                style: GoogleFonts.cairo(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String>(
                  value: _stageGraphGrouping,
                  decoration: InputDecoration(
                    labelText: 'Group graph by',
                    labelStyle: GoogleFonts.cairo(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  dropdownColor: _cardColor,
                  items: const [
                    DropdownMenuItem(value: 'factory', child: Text('Factories')),
                    DropdownMenuItem(value: 'date', child: Text('Dates (month)')),
                    DropdownMenuItem(value: 'employee', child: Text('Employees')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _stageGraphGrouping = value);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Select statuses in each stage to compare order counts by factory, date, or employee.',
            style: GoogleFonts.cairo(
              fontSize: 12,
              color: _secondaryTextColor,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              TextButton(
                onPressed: () => setState(() {
                  _selectedSubmittalGraphStatuses.addAll(_beforeApprovalStatuses);
                  _selectedApprovalGraphStatuses.addAll(_approvalStatuses);
                  _selectedManufacturingGraphStatuses.addAll(_manufacturingStatuses);
                }),
                child: const Text('Select all'),
              ),
              TextButton(
                onPressed: () => setState(() {
                  _selectedSubmittalGraphStatuses.clear();
                  _selectedApprovalGraphStatuses.clear();
                  _selectedManufacturingGraphStatuses.clear();
                }),
                child: const Text('Clear all'),
              ),
              const Spacer(),
              Text(
                '$selectedCount selected',
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: _secondaryTextColor,
                ),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1000
                  ? 3
                  : constraints.maxWidth >= 650
                  ? 2
                  : 1;
              final gap = 8.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: stageStatuses.entries.map((entry) {
                  return SizedBox(
                    width: width,
                    child: stageFilter(entry.key, entry.value),
                  );
                }).toList(),
              );
            },
          ),
          const SizedBox(height: 14),
          if (activeStatuses.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'Select at least one stage status to display the graph.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(color: _secondaryTextColor),
                ),
              ),
            )
          else if (visibleCategories.isEmpty)
            Padding(
              padding: const EdgeInsets.all(28),
              child: Center(
                child: Text(
                  'No matching orders for the selected filters.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(color: _secondaryTextColor),
                ),
              ),
            )
          else
            SizedBox(
              height: 440,
              child: LayoutBuilder(
                builder: (context, chartConstraints) {
                  final chartWidth = (visibleCategories.length * 120.0)
                      .clamp(chartConstraints.maxWidth, 100000.0);
                  return Scrollbar(
                      controller: _stageGraphScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      interactive: true,
                      notificationPredicate: (notification) =>
                      notification.metrics.axis == Axis.horizontal,
                      child: SingleChildScrollView(
                        controller: _stageGraphScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: chartWidth,
                          child: BarChart(
                            BarChartData(
                              alignment: BarChartAlignment.spaceAround,
                              maxY: (() {
                                var maxValue = 0;
                                for (final category in visibleCategories) {
                                  for (final status in activeStatuses) {
                                    final count = _allOrders.where((order) {
                                      return order.status.trim() == status &&
                                          categoriesForOrder(order).contains(category);
                                    }).length;
                                    if (count > maxValue) maxValue = count;
                                  }
                                }
                                return (maxValue + 1).toDouble();
                              })(),
                              barTouchData: BarTouchData(
                                enabled: true,
                                handleBuiltInTouches: true,
                                touchCallback: (event, response) {
                                  if (!event.isInterestedForInteractions ||
                                      response == null ||
                                      response.spot == null ||
                                      event is! FlTapUpEvent) {
                                    return;
                                  }
                                  final categoryIndex =
                                      response.spot!.touchedBarGroupIndex;
                                  final statusIndex =
                                      response.spot!.touchedRodDataIndex;
                                  if (categoryIndex < 0 ||
                                      categoryIndex >= visibleCategories.length ||
                                      statusIndex < 0 ||
                                      statusIndex >= activeStatuses.length) {
                                    return;
                                  }
                                  _showStageGraphOrders(
                                    category: visibleCategories[categoryIndex],
                                    status: activeStatuses[statusIndex],
                                    categoriesForOrder: (order) =>
                                        categoriesForOrder(order),
                                  );
                                },
                                touchTooltipData: BarTouchTooltipData(
                                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                                    final category = visibleCategories[group.x.toInt()];
                                    final status = activeStatuses[rodIndex];
                                    return BarTooltipItem(
                                      '$category\n$status: ${rod.toY.round()} orders',
                                      TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    );
                                  },
                                ),
                              ),
                              titlesData: FlTitlesData(
                                topTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                rightTitles: const AxisTitles(
                                  sideTitles: SideTitles(showTitles: false),
                                ),
                                leftTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 44,
                                    getTitlesWidget: (value, meta) => Text(
                                      value.toInt().toString(),
                                      style: TextStyle(
                                        color: _secondaryTextColor,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: 70,
                                    getTitlesWidget: (value, meta) {
                                      final index = value.toInt();
                                      if (index < 0 || index >= visibleCategories.length) {
                                        return const SizedBox.shrink();
                                      }
                                      final category = visibleCategories[index];
                                      final parsedMonth = _stageGraphGrouping == 'date'
                                          ? DateTime.tryParse('$category-01')
                                          : null;
                                      final label = parsedMonth == null
                                          ? category
                                          : DateFormat('MMM yyyy').format(parsedMonth);
                                      return SideTitleWidget(
                                        meta: meta,
                                        space: 10,
                                        child: SizedBox(
                                          width: 100,
                                          child: Text(
                                            label,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _secondaryTextColor,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              gridData: FlGridData(
                                show: true,
                                drawVerticalLine: false,
                                getDrawingHorizontalLine: (value) => FlLine(
                                  color: _borderColor.withOpacity(0.7),
                                  strokeWidth: 0.7,
                                ),
                              ),
                              borderData: FlBorderData(show: false),
                              barGroups: List.generate(visibleCategories.length, (index) {
                                final category = visibleCategories[index];
                                return BarChartGroupData(
                                  x: index,
                                  barsSpace: 3,
                                  barRods: activeStatuses.map((status) {
                                    final count = _allOrders.where((order) {
                                      return order.status.trim() == status &&
                                          categoriesForOrder(order).contains(category);
                                    }).length;
                                    return BarChartRodData(
                                      toY: count.toDouble(),
                                      color: _getStatusColor(status),
                                      width: activeStatuses.length > 8 ? 8 : 16,
                                      borderRadius: BorderRadius.circular(3),
                                    );
                                  }).toList(),
                                );
                              }),
                            ),
                          ),
                        ),
                      ));
                },
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: activeStatuses.map((status) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: _getStatusColor(status),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    status,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: _secondaryTextColor,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusDistributionCard() {
    final allStatuses = [
      'Drawing Submittal',
      'Approval',
      'modifications submitted',
      'Manufacturing Drawing',
      'Done',
      'Task Done',
      'مطلوب اكوادها الاسترشاديه',
      'تحت المراجعة',
      'Review',
      'Sales',
      'As Built',
      'Tasks',
      'planning',
      'partation  master data',
      'الادارة الهندسه',
      'design studio',
      'imported',
      'ادارة تصميم المنتجات',
    ];

    final statusColors = <String, Color>{
      'Drawing Submittal': Colors.purple,
      'Approval': Colors.green,
      'modifications submitted': Colors.lightBlue,
      'Manufacturing Drawing': Colors.indigo,
      'Done': Colors.green.shade700,
      'Task Done': Colors.teal,
      'مطلوب اكوادها الاسترشاديه': Colors.blue,
      'تحت المراجعة': Colors.orange,
      'Review': Colors.amber,
      'Master Data': Colors.cyan,
      'Sales': Colors.deepOrange,
      'As Built': Colors.brown,
      'Tasks': Colors.lime,
      'planning': Colors.pink,
      'partation  master data': Colors.deepPurple,
      'الادارة الهندسه': Colors.blueGrey,
      'design studio': Colors.red,
      'imported': Colors.grey,
      'ادارة تصميم المنتجات': Colors.teal,
    };

    if (!_statusFiltersInitialized) {
      _selectedStatusFilters.addAll(allStatuses);
      _statusFiltersInitialized = true;
    }

    final selectedStatuses = allStatuses
        .where((status) => _selectedStatusFilters.contains(status))
        .toList();

    final selectedTotalOrders = selectedStatuses.fold<int>(
      0,
          (sum, status) => sum + (_statusDistribution[status] ?? 0),
    );

    final selectedTotalValue = selectedStatuses.fold<double>(
      0,
          (sum, status) => sum + (_statusValues[status] ?? 0),
    );

    final selectedPercentage = _totalOrders > 0
        ? selectedTotalOrders / _totalOrders * 100
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _isDark
                ? Colors.black.withOpacity(0.3)
                : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Orders by Status',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedStatusFilters.addAll(allStatuses);
                  });
                },
                icon: const Icon(Icons.check_box, size: 18),
                label: Text(
                  'Check All',
                  style: GoogleFonts.cairo(fontSize: 12),
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedStatusFilters.clear();
                  });
                },
                icon: const Icon(Icons.check_box_outline_blank, size: 18),
                label: Text(
                  'Uncheck All',
                  style: GoogleFonts.cairo(fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 600;
              final chartSize = isMobile
                  ? (constraints.maxWidth - 20).clamp(260.0, 360.0).toDouble()
                  : (constraints.maxWidth * 0.48).clamp(380.0, 560.0).toDouble();
              final entries = selectedStatuses
                  .where((status) => (_statusDistribution[status] ?? 0) > 0)
                  .toList();
              final chart = SizedBox(
                width: double.infinity,
                height: chartSize,
                child: entries.isEmpty
                    ? Center(
                  child: Text(
                    'Select at least one status with orders to display the chart',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.cairo(
                      fontSize: isMobile ? 14 : 16,
                      color: _secondaryTextColor,
                    ),
                  ),
                )
                    : Stack(
                  clipBehavior: Clip.none,
                  children: [
                    PieChart(
                      PieChartData(
                        centerSpaceRadius: chartSize * 0.245,
                        sectionsSpace: 4,
                        pieTouchData: PieTouchData(
                          // Hover updates the in-chart tooltip; tapping still opens orders.
                          touchCallback: (event, response) {
                            final touched = response?.touchedSection;
                            final index = touched?.touchedSectionIndex;
                            if (index != _hoveredPieIndex && mounted) {
                              setState(() {
                                _hoveredPieIndex =
                                index != null && index >= 0 && index < entries.length
                                    ? index
                                    : null;
                              });
                            }

                            if (event is FlTapUpEvent &&
                                index != null &&
                                index >= 0 &&
                                index < entries.length) {
                              _showStatusOrders(entries[index]);
                            }
                          },
                        ),
                        sections: entries.map((status) {
                          final count = _statusDistribution[status] ?? 0;
                          final pct = _totalOrders == 0
                              ? 0.0
                              : count / _totalOrders * 100;
                          // Give tiny categories a minimum visible wedge.
                          // The floor is intentionally small so large slices
                          // remain dominant while small statuses stay tappable.
                          final maxCount = entries.fold<int>(
                            0,
                                (largest, item) =>
                            (_statusDistribution[item] ?? 0) > largest
                                ? (_statusDistribution[item] ?? 0)
                                : largest,
                          );
                          final minimumSliceValue = maxCount * 0.025;
                          return PieChartSectionData(
                            value: count.toDouble() < minimumSliceValue
                                ? minimumSliceValue
                                : count.toDouble(),
                            color: _getStatusColor(status),
                            radius: chartSize * 0.19,
                            // Keep the slices clean; details appear on hover.
                            title: '',
                            titleStyle: const TextStyle(
                              color: Colors.transparent,
                              fontSize: 0,
                            ),
                            badgeWidget: null,
                          );
                        }).toList(),
                      ),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutCubic,
                    ),
                    if (_hoveredPieIndex != null &&
                        _hoveredPieIndex! >= 0 &&
                        _hoveredPieIndex! < entries.length)
                      Positioned(
                        top: 8,
                        left: 0,
                        right: 0,
                        child: IgnorePointer(
                          child: Center(
                            child: Builder(
                              builder: (context) {
                                final status = entries[_hoveredPieIndex!];
                                final count = _statusDistribution[status] ?? 0;
                                final pct = _totalOrders > 0
                                    ? count / _totalOrders * 100
                                    : 0.0;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _isDark
                                        ? const Color(0xFF303030)
                                        : const Color(0xFF1F2937),
                                    borderRadius: BorderRadius.circular(8),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.18),
                                        blurRadius: 10,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    '$status • ${pct.toStringAsFixed(2)}% • $count orders',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );

              return Container(
                width: double.infinity,
                padding: EdgeInsets.all(isMobile ? 12 : 22),
                decoration: BoxDecoration(
                  color: _isDark ? Colors.white.withOpacity(0.025) : const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _borderColor),
                ),
                child: Column(
                  children: [
                    chart,
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: _isDark
                  ? const Color(0xFF2A2A2A).withOpacity(0.3)
                  : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Status',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Count',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Value',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '%',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          ...allStatuses.map((status) {
            final count = _statusDistribution[status] ?? 0;
            if (count == 0) return const SizedBox.shrink();

            final color = statusColors[status] ?? Colors.grey;
            final pct =
            _totalOrders > 0 ? count / _totalOrders * 100 : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding:
                const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Row(
                        children: [
                          Checkbox(
                            value: _selectedStatusFilters.contains(status),
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                            onChanged: (checked) {
                              setState(() {
                                if (checked == true) {
                                  _selectedStatusFilters.add(status);
                                } else {
                                  _selectedStatusFilters.remove(status);
                                }
                              });
                            },
                          ),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () => _showStatusOrders(status),
                              child: Text(
                                status,
                                style: GoogleFonts.cairo(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: _textColor,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '$count',
                        style: GoogleFonts.cairo(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _textColor,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '\$${_formatNumber(_statusValues[status] ?? 0)}',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF059669),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${pct.toStringAsFixed(2)}%',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(context)
                    .colorScheme
                    .primary
                    .withOpacity(0.3),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Total',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '$selectedTotalOrders',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '\$${_formatNumber(selectedTotalValue)}',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF059669),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    '${selectedPercentage.toStringAsFixed(2)}%',
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
