// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
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

  // Inclusive audit-date range.
  DateTime? _startDate;
  DateTime? _endDate;

  // Orders this month
  int _ordersThisMonth = 0;

  // Approach and Manufacturing data
  List<SAPMainOrder> _approachOrders = [];
  List<SAPMainOrder> _manufacturingOrders = [];
  double _approachValue = 0;
  double _manufacturingValue = 0;
  double _approachQuantity = 0;
  double _manufacturingQuantity = 0;

  // Employee auth service
  final EmployeeAuthService _authService = EmployeeAuthService(
    Supabase.instance.client,
  );

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;

  // Status lists
  static const List<String> _approachStatuses = [
    'Drawing Submittal',
    'modifications submitted',
    'Approval',
    'Sales',
    'As Built',
    'ادارة تصميم المنتجات',
    'الادارة الهندسه',
    'design studio',
  ];

  static const List<String> _manufacturingStatuses = [
    'Manufacturing Drawing',
    'Review',
    'Master Data',
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

      // The dashboard date filter is based on the audit table.
      // An order belongs to a selected period when its audit row has:
      //   order_id = the order id
      //   field_name = status
      //   new_value = the status used by the dashboard section
      //   changed_at = a date inside the selected range
      final auditRows = await Supabase.instance.client
          .from('order_audit_log')
          .select('order_id, field_name, new_value, changed_at')
          .eq('field_name', 'status')
          .order('changed_at', ascending: false)
          .limit(10000);

      _allOrders = orders;
      _allEmployees = employees;
      _auditLogs = List<Map<String, dynamic>>.from(auditRows);

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
    final orders = _allOrders;
    final employees = _allEmployees;

    // No date range: keep the normal dashboard based on current SAP orders.
    if (_startDate == null && _endDate == null) {
      final statusDist = <String, int>{};
      final statusValues = <String, double>{};
      final statusQuantities = <String, double>{};
      final factories = <String>{};
      final engineerCount = <String, int>{};

      double totalVal = 0;
      double totalQty = 0;
      int thisMonth = 0;
      final now = DateTime.now();
      final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      final approachOrders = <SAPMainOrder>[];
      final manufacturingOrders = <SAPMainOrder>[];
      double approachVal = 0;
      double manufacturingVal = 0;
      double approachQty = 0;
      double manufacturingQty = 0;

      for (final order in orders) {
        final status = order.status.isEmpty ? 'Unknown' : order.status;
        statusDist[status] = (statusDist[status] ?? 0) + 1;
        statusValues[status] = (statusValues[status] ?? 0) + order.value;
        statusQuantities[status] =
            (statusQuantities[status] ?? 0) + order.quantity;

        if (order.factory != null && order.factory!.isNotEmpty) {
          factories.add(order.factory!);
        }
        if (order.salesEngineer.isNotEmpty) {
          engineerCount[order.salesEngineer] =
              (engineerCount[order.salesEngineer] ?? 0) + 1;
        }

        totalVal += order.value;
        totalQty += order.quantity;

        if (order.orderDate != null &&
            order.orderDate!.startsWith(currentMonth)) {
          thisMonth++;
        }

        if (_approachStatuses.contains(order.status)) {
          approachOrders.add(order);
          approachVal += order.value;
          approachQty += order.quantity;
        }
        if (_manufacturingStatuses.contains(order.status)) {
          manufacturingOrders.add(order);
          manufacturingVal += order.value;
          manufacturingQty += order.quantity;
        }
      }

      final recent = List<SAPMainOrder>.from(orders)
        ..sort((a, b) => (b.createdAt ?? DateTime(2000))
            .compareTo(a.createdAt ?? DateTime(2000)));

      if (!mounted) return;
      setState(() {
        _totalOrders = orders.length;
        _totalValue = totalVal;
        _totalQuantity = totalQty;
        _totalEmployees = employees.length;
        _totalFactories = factories.length;
        _statusDistribution = statusDist;
        _statusValues = statusValues;
        _statusQuantities = statusQuantities;
        _recentOrders = recent.take(8).toList();
        _ordersThisMonth = thisMonth;
        _approachOrders = approachOrders;
        _manufacturingOrders = manufacturingOrders;
        _approachValue = approachVal;
        _manufacturingValue = manufacturingVal;
        _approachQuantity = approachQty;
        _manufacturingQuantity = manufacturingQty;
        _isLoading = false;
      });
      return;
    }

    // DATE RANGE:
    // The audit table is the source of truth for counts. Do NOT require the
    // SAP order's CURRENT status to equal the historical audit status.
    final auditIdsByStatus = <String, Set<String>>{};
    final allAuditIds = <String>{};

    for (final log in _auditLogs) {
      final fieldName = log['field_name']?.toString().trim() ?? '';
      final newValue = log['new_value']?.toString().trim() ?? '';
      final orderId = log['order_id']?.toString().trim() ?? '';

      if (fieldName != 'status' ||
          newValue.isEmpty ||
          orderId.isEmpty ||
          orderId == 'bulk_delete' ||
          orderId == 'import_batch') {
        continue;
      }

      final changedAt = _parseAuditDate(log['changed_at']);
      if (changedAt == null || !_isDateInRange(changedAt)) {
        continue;
      }

      // Find the existing SAP order.
      SAPMainOrder? currentOrder;

      for (final order in orders) {
        if (order.id.toString().trim() == orderId) {
          currentOrder = order;
          break;
        }
      }

      // Order does not exist in sap_main_orders.
      if (currentOrder == null) {
        continue;
      }

      // IMPORTANT:
      // Only count it if its CURRENT SAP status is still
      // the same status it entered in the audit log.
      if (currentOrder.status.trim() != newValue) {
        continue;
      }

      // DISTINCT order_id
      allAuditIds.add(orderId);

      auditIdsByStatus
          .putIfAbsent(newValue, () => <String>{})
          .add(orderId);
    }

    // Lookup SAP data only for value/quantity/details. Counts remain based
    // entirely on distinct audit order IDs, including IDs missing from SAP.
    final ordersById = <String, SAPMainOrder>{
      for (final order in orders) order.id.toString(): order,
    };

    List<SAPMainOrder> ordersForIds(Set<String> ids) => orders
        .where((order) => ids.contains(order.id.toString()))
        .toList();

    final approachIds = <String>{};
    final manufacturingIds = <String>{};

    for (final entry in auditIdsByStatus.entries) {
      if (_approachStatuses.contains(entry.key)) {
        approachIds.addAll(entry.value);
      }
      if (_manufacturingStatuses.contains(entry.key)) {
        manufacturingIds.addAll(entry.value);
      }
    }

    final approachOrders = ordersForIds(approachIds);
    final manufacturingOrders = ordersForIds(manufacturingIds);

    final statusDist = <String, int>{};
    final statusValues = <String, double>{};
    final statusQuantities = <String, double>{};

    for (final entry in auditIdsByStatus.entries) {
      statusDist[entry.key] = entry.value.length;

      double value = 0;
      double quantity = 0;
      for (final id in entry.value) {
        final order = ordersById[id];
        if (order != null) {
          value += order.value;
          quantity += order.quantity;
        }
      }
      statusValues[entry.key] = value;
      statusQuantities[entry.key] = quantity;
    }

    double sumValue(Iterable<SAPMainOrder> list) =>
        list.fold(0.0, (sum, order) => sum + order.value);
    double sumQuantity(Iterable<SAPMainOrder> list) =>
        list.fold(0.0, (sum, order) => sum + order.quantity);

    final filteredOrders = ordersForIds(allAuditIds);
    final factories = <String>{};
    final engineerCount = <String, int>{};

    for (final order in filteredOrders) {
      if (order.factory != null && order.factory!.isNotEmpty) {
        factories.add(order.factory!);
      }
      if (order.salesEngineer.isNotEmpty) {
        engineerCount[order.salesEngineer] =
            (engineerCount[order.salesEngineer] ?? 0) + 1;
      }
    }

    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    final thisMonth = filteredOrders.where((order) =>
    order.orderDate != null && order.orderDate!.startsWith(currentMonth)).length;

    final recent = List<SAPMainOrder>.from(filteredOrders)
      ..sort((a, b) => (b.createdAt ?? DateTime(2000))
          .compareTo(a.createdAt ?? DateTime(2000)));

    if (!mounted) return;
    setState(() {
      _totalOrders = allAuditIds.length;
      _totalValue = sumValue(filteredOrders);
      _totalQuantity = sumQuantity(filteredOrders);
      _totalEmployees = employees.length;
      _totalFactories = factories.length;
      _statusDistribution = statusDist;
      _statusValues = statusValues;
      _statusQuantities = statusQuantities;
      _recentOrders = recent.take(8).toList();
      _ordersThisMonth = thisMonth;
      _approachOrders = approachOrders;
      _manufacturingOrders = manufacturingOrders;
      _approachValue = sumValue(approachOrders);
      _manufacturingValue = sumValue(manufacturingOrders);
      _approachQuantity = sumQuantity(approachOrders);
      _manufacturingQuantity = sumQuantity(manufacturingOrders);
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
        padding: const EdgeInsets.all(24),
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

            // Audit date range filter
            _buildDateRangeFilter(),
            const SizedBox(height: 24),

            // Comparison Section
            _buildComparisonSection(),
            const SizedBox(height: 24),

            // Charts Row
            _buildStatusDistributionCard(),
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
            'Audit Date',
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
          Text(
            'Order Breakdown',
            style: GoogleFonts.cairo(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              // Approach Column
              Expanded(
                child: _buildComparisonColumn(
                  title: 'Approach',
                  icon: Icons.design_services,
                  color: Colors.purple,
                  orderCount: _approachOrders.length,
                  totalValue: _approachValue,
                  totalQuantity: _approachQuantity,
                  statuses: _approachStatuses,
                ),
              ),
              const SizedBox(width: 16),
              // Manufacturing Column
              Expanded(
                child: _buildComparisonColumn(
                  title: 'Manufacturing',
                  icon: Icons.precision_manufacturing,
                  color: Colors.orange,
                  orderCount: _manufacturingOrders.length,
                  totalValue: _manufacturingValue,
                  totalQuantity: _manufacturingQuantity,
                  statuses: _manufacturingStatuses,
                ),
              ),
            ],
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
            ...statuses.map((status) {
              final count = _statusDistribution[status] ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
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
                    const SizedBox(width: 6),
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
                      '$count',
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _textColor,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
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


  Widget _buildStatusDistributionCard() {
    // Define all statuses
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
      'Master Data',
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

    // Colors for each status
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

    // Calculate total value per status
    final statusValues = <String, double>{};
    for (var order in _recentOrders.isEmpty ? [] : _recentOrders) {
      // This won't work correctly as _recentOrders only has 8 items
    }

    // Better approach: store all orders with their status and value
    // For now, we'll calculate from _statusDistribution

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [
          BoxShadow(
            color: _isDark ? Colors.black.withOpacity(0.3) : Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Orders by Status',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 20),
          // Table Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: _isDark ? const Color(0xFF334155).withOpacity(0.3) : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('Status', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor))),
                Expanded(flex: 2, child: Text('Count', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor), textAlign: TextAlign.center)),
                Expanded(flex: 2, child: Text('Value', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor), textAlign: TextAlign.right)),
                Expanded(flex: 2, child: Text('%', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor), textAlign: TextAlign.right)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Status Rows
          ...allStatuses.map((status) {
            final count = _statusDistribution[status] ?? 0;
            if (count == 0) return const SizedBox.shrink();

            final color = statusColors[status] ?? Colors.grey;
            final pct = _totalOrders > 0 ? (count / _totalOrders * 100) : 0.0;
            final pctFormatted = pct.toStringAsFixed(2);

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => _showStatusOrders(status),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
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
                          '$pctFormatted%',
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
              ),
            );
          }),
          const SizedBox(height: 16),
          // Total Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.3)),
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
                    '$_totalOrders',
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
                    '\$${_formatNumber(_totalValue)}',
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
                    '100.00%',
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
