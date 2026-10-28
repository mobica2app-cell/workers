// lib/pages/dashboard_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/track_order.dart';
import 'package:mobitem/services/csv_export_service.dart';
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
  final Set<String> _selectedApprovalGraphStatuses = {..._approvalStatuses};
  final Set<String> _selectedManufacturingGraphStatuses = {
    ..._manufacturingStatuses,
  };

  // Independent filters and grouping for the circular chart.
  String _circularGraphGrouping = 'factory';
  int? _hoveredCircularPieIndex;
  final Set<String> _selectedCircularSubmittalStatuses = {
    ..._beforeApprovalStatuses,
  };
  final Set<String> _selectedCircularApprovalStatuses = {..._approvalStatuses};
  final Set<String> _selectedCircularManufacturingStatuses = {
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

  // Dashboard explorer and activity state.
  final TextEditingController _orderSearchController = TextEditingController();
  final GlobalKey _orderExplorerKey = GlobalKey();
  String? _selectedFactoryFilter;
  String? _selectedOrderStatusFilter;
  String? _attentionFilter;
  String _orderSort = 'Newest';
  String _datePreset = 'all';
  bool _showAllExplorerOrders = false;
  bool _isExporting = false;
  List<Map<String, dynamic>> _recentActivity = [];
  bool _activityLoadFailed = false;
  DateTime? _lastRefreshedAt;

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
  List<BoxShadow> get _dashboardCardShadows => [
    BoxShadow(
      color: Colors.black.withOpacity(_isDark ? 0.24 : 0.045),
      blurRadius: 18,
      offset: const Offset(0, 6),
    ),
  ];

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

      // Keep the activity feed separate from stage graph calculations. The
      // feed is a short, recent snapshot and must not be used as full history.
      var recentActivity = <Map<String, dynamic>>[];
      var activityLoadFailed = false;
      try {
        final activityRows = await Supabase.instance.client
            .from('order_audit_log')
            .select(
              'order_id, design_order, field_name, old_value, new_value, '
              'changed_by, changed_at, action_type, notes',
            )
            .order('changed_at', ascending: false)
            .limit(12);
        recentActivity = List<Map<String, dynamic>>.from(activityRows);
      } catch (e) {
        activityLoadFailed = true;
        debugPrint('Error loading recent order activity: $e');
      }

      // The dashboard date filter is based on SAP main orders.created_at.
      _allOrders = orders;
      if (_selectedOrderStatusFilter != null &&
          !_allOrders.any(
            (order) => order.status.trim() == _selectedOrderStatusFilter,
          )) {
        _selectedOrderStatusFilter = null;
      }
      if (_selectedFactoryFilter != null &&
          !_allOrders.any(
            (order) => (order.factory?.trim() ?? '') == _selectedFactoryFilter,
          )) {
        _selectedFactoryFilter = null;
      }
      _allEmployees = employees;
      _recentActivity = recentActivity;
      _activityLoadFailed = activityLoadFailed;
      _lastRefreshedAt = DateTime.now();
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

  List<SAPMainOrder> get _dateFilteredOrders => _allOrders.where((order) {
    if (!_hasDateRange) return true;
    final createdAt = order.createdAt;
    return createdAt != null && _isDateInRange(createdAt);
  }).toList();

  List<SAPMainOrder> get _filteredExplorerOrders {
    final query = _orderSearchController.text.trim().toLowerCase();
    final orders = _dateFilteredOrders.where((order) {
      if (_selectedOrderStatusFilter != null &&
          order.status.trim() != _selectedOrderStatusFilter) {
        return false;
      }

      if (_selectedFactoryFilter != null &&
          (order.factory?.trim() ?? '') != _selectedFactoryFilter) {
        return false;
      }

      if (_attentionFilter == 'overdue_delivery' &&
          !_hasOverdueDelivery(order)) {
        return false;
      }
      if (_attentionFilter == 'missing_delivery' &&
          (order.deliveryDate?.trim().isNotEmpty ?? false)) {
        return false;
      }
      if (_attentionFilter == 'missing_engineer' &&
          order.salesEngineer.trim().isNotEmpty) {
        return false;
      }

      if (query.isEmpty) return true;
      final searchable = <String>[
        order.designOrder,
        order.contractNumber,
        order.customerName,
        order.description,
        order.salesEngineer,
        order.productCode,
        order.itemNumber,
        order.status,
        order.factory ?? '',
      ].join(' ').toLowerCase();
      return searchable.contains(query);
    }).toList();

    switch (_orderSort) {
      case 'Highest value':
        orders.sort((a, b) => b.value.compareTo(a.value));
        break;
      case 'Largest quantity':
        orders.sort((a, b) => b.quantity.compareTo(a.quantity));
        break;
      case 'Customer A–Z':
        orders.sort(
          (a, b) => a.customerName.toLowerCase().compareTo(
            b.customerName.toLowerCase(),
          ),
        );
        break;
      default:
        orders.sort(
          (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
            a.createdAt ?? DateTime(2000),
          ),
        );
    }
    return orders;
  }

  DateTime? _parseOrderDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    return DateTime.tryParse(value.trim())?.toLocal();
  }

  bool _hasOverdueDelivery(SAPMainOrder order) {
    final deliveryDate = _parseOrderDate(order.deliveryDate);
    return deliveryDate != null &&
        _dateOnly(deliveryDate).isBefore(_dateOnly(DateTime.now()));
  }

  String _factoryLabel(String? factory) {
    final code = factory?.trim() ?? '';
    if (code.isEmpty) return 'No factory';
    final description = _factoryDescriptions[code.toLowerCase()]?.trim() ?? '';
    return description.isEmpty ? code : '$code · $description';
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

      return orders.where((o) => statuses.contains(o.status)).toList();
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
    final filteredOrders = _dateFilteredOrders;

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
      ..sort(
        (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
          a.createdAt ?? DateTime(2000),
        ),
      );

    if (!mounted) return;

    setState(() {
      _totalOrders = filteredOrders.length;
      _totalValue = totalVal;
      _totalQuantity = totalQty;
      _totalEmployees = employees.where((employee) => employee.isActive).length;
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
        return Colors.deepOrangeAccent;
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
    _orderSearchController.dispose();
    super.dispose();
  }

  Widget _buildGroupingTab(
      String value,
      String label,
      String selectedValue,
      ValueChanged<String> onSelected,
      ) {
    final selected = selectedValue == value;
    final primaryColor = Theme.of(context).colorScheme.primary;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
      selected: selected,
      onSelected: (_) => onSelected(value),
      selectedColor: primaryColor.withOpacity(_isDark ? 0.28 : 0.14),
      backgroundColor: _cardColor,
      side: BorderSide(color: selected ? primaryColor : _borderColor),
      labelStyle: TextStyle(color: selected ? primaryColor : _textColor),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    );
  }

  Widget _buildDashboardOverview() {
    final activeEmployees = _allEmployees
        .where((employee) => employee.isActive)
        .length;
    final lastUpdated = _lastRefreshedAt == null
        ? 'Not refreshed yet'
        : 'Updated ${DateFormat('h:mm a').format(_lastRefreshedAt!)}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: _dashboardCardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.dashboard_customize_outlined,
                  color: Theme.of(context).colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Overview',
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                    Text(
                      'Orders · ${_hasDateRange ? _getDateFilterLabel() : 'All time'} · $lastUpdated',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'How to read these numbers',
                onPressed: _showDataNotes,
                icon: Icon(Icons.info_outline, color: _secondaryTextColor),
              ),
            ],
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050
                  ? 5
                  : constraints.maxWidth >= 650
                  ? 3
                  : 2;
              final gap = 10.0;
              final width =
                  (constraints.maxWidth - gap * (columns - 1)) / columns;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  SizedBox(
                    width: width,
                    child: _buildMetricCard(
                      label: 'Active orders',
                      value: NumberFormat.decimalPattern().format(_totalOrders),
                      caption: 'Tap to explore',
                      icon: Icons.receipt_long_outlined,
                      color: Colors.blue,
                      onTap: _scrollToOrderExplorer,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildMetricCard(
                      label: 'Pipeline value',
                      value: '\$${_formatNumber(_totalValue)}',
                      caption: 'Tap for status split',
                      icon: Icons.payments_outlined,
                      color: Colors.teal,
                      onTap: () =>
                          _showStatusMetricBreakdown(valueMetric: true),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildMetricCard(
                      label: 'Quantity',
                      value: NumberFormat.decimalPattern().format(
                        _totalQuantity,
                      ),
                      caption: 'Mixed units · tap to split',
                      icon: Icons.inventory_2_outlined,
                      color: Colors.deepOrange,
                      onTap: () =>
                          _showStatusMetricBreakdown(valueMetric: false),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildMetricCard(
                      label: 'Factories',
                      value: '$_totalFactories',
                      caption: 'Tap for order split',
                      icon: Icons.factory_outlined,
                      color: Colors.indigo,
                      onTap: _showFactoryBreakdown,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: _buildMetricCard(
                      label: 'Active employees',
                      value: '$activeEmployees',
                      caption: 'Tap to browse staff',
                      icon: Icons.groups_outlined,
                      color: Colors.purple,
                      onTap: _showEmployeeDirectory,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 11),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(_isDark ? 0.09 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withOpacity(0.18)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.lightbulb_outline_rounded,
                  size: 17,
                  color: Colors.amber.shade700,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Value and quantity summarize the current orders. Archived orders are excluded from these totals.',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: _secondaryTextColor,
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

  Widget _buildMetricCard({
    required String label,
    required String value,
    required String caption,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          height: 132,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color.withOpacity(_isDark ? 0.17 : 0.10), _cardColor],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withOpacity(_isDark ? 0.34 : 0.24)),
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(_isDark ? 0.06 : 0.07),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                right: -2,
                bottom: -9,
                child: Icon(icon, size: 58, color: color.withOpacity(0.07)),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: color.withOpacity(_isDark ? 0.22 : 0.14),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, size: 18, color: color),
                      ),
                      const Spacer(),
                      Icon(Icons.arrow_outward_rounded, size: 15, color: color),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 1),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      value,
                      style: GoogleFonts.cairo(
                        fontSize: 22,
                        height: 1.15,
                        fontWeight: FontWeight.w800,
                        color: _textColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardSheetFrame({
    required BuildContext sheetContext,
    required double heightFactor,
    required Widget child,
  }) {
    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.of(sheetContext).size.height * heightFactor,
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.fromLTRB(18, 9, 18, 16),
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          border: Border.all(color: _borderColor),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(_isDark ? 0.4 : 0.12),
              blurRadius: 24,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: child,
      ),
    );
  }

  Widget _buildDashboardSheetHeader({
    required BuildContext sheetContext,
    required String title,
    required String subtitle,
    required IconData icon,
    Color? accentColor,
  }) {
    final accent = accentColor ?? Theme.of(context).colorScheme.primary;
    return Column(
      children: [
        Container(
          width: 38,
          height: 4,
          decoration: BoxDecoration(
            color: _secondaryTextColor.withOpacity(0.35),
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withOpacity(_isDark ? 0.2 : 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: accent, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _textColor,
                    ),
                  ),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: _secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(sheetContext),
              style: IconButton.styleFrom(
                backgroundColor: _surfaceColor,
                foregroundColor: _secondaryTextColor,
              ),
              icon: const Icon(Icons.close_rounded, size: 18),
            ),
          ],
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  void _showDataNotes() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        titlePadding: const EdgeInsets.fromLTRB(22, 22, 18, 8),
        contentPadding: const EdgeInsets.fromLTRB(22, 8, 22, 10),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(
                Icons.insights_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'How to read the dashboard',
                style: GoogleFonts.cairo(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: _textColor,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.pop(dialogContext),
              icon: Icon(Icons.close_rounded, color: _secondaryTextColor),
            ),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _buildDataNoteItem(
                  Icons.storage_rounded,
                  'Live order scope',
                  'Totals include current orders. Archived orders are stored separately and excluded here.',
                ),
                _buildDataNoteItem(
                  Icons.calendar_month_rounded,
                  'Date fields',
                  'Presets filter created_at. Existing stage charts keep their current all-active-order scope and group by order_date.',
                ),
                _buildDataNoteItem(
                  Icons.payments_rounded,
                  'Value and quantity',
                  'Order value sums the recorded values. Quantity may combine different units of measure.',
                ),
                _buildDataNoteItem(
                  Icons.factory_rounded,
                  'Factories and people',
                  'Factory names use the descriptions. Employee totals include active accounts.',
                ),
                _buildDataNoteItem(
                  Icons.history_rounded,
                  'Activity feed',
                  'Shows recent changes recorded in order history. It is not a complete audit history.',
                ),
              ],
            ),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
        actions: [
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: Text('Got it', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Widget _buildDataNoteItem(IconData icon, String title, String description) {
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark
            ? Colors.white.withOpacity(0.035)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: primary.withOpacity(0.11),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    height: 1.45,
                    color: _secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToOrderExplorer() {
    final target = _orderExplorerKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  void _showStatusMetricBreakdown({required bool valueMetric}) {
    final metrics = valueMetric ? _statusValues : _statusQuantities;
    final entries = metrics.entries.where((entry) => entry.value != 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final title = valueMetric
        ? 'Pipeline value by status'
        : 'Quantity by status';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _buildDashboardSheetFrame(
        sheetContext: sheetContext,
        heightFactor: 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDashboardSheetHeader(
              sheetContext: sheetContext,
              title: title,
              subtitle: valueMetric
                  ? 'Select a status to open matching orders.'
                  : 'Quantities keep the units stored on each order.',
              icon: valueMetric
                  ? Icons.payments_rounded
                  : Icons.inventory_2_rounded,
              accentColor: valueMetric ? Colors.teal : Colors.deepOrange,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entries.length} statuses',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                  ),
                  Text(
                    valueMetric
                        ? '\$${_formatNumber(_totalValue)}'
                        : NumberFormat.decimalPattern().format(_totalQuantity),
                    style: GoogleFonts.cairo(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'No values for this date range',
                        style: GoogleFonts.cairo(color: _secondaryTextColor),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final value = valueMetric
                            ? '\$${_formatNumber(entry.value)}'
                            : NumberFormat.decimalPattern().format(entry.value);
                        final metricTotal = entries.fold<double>(
                          0,
                          (sum, item) => sum + item.value,
                        );
                        final share = metricTotal == 0
                            ? 0.0
                            : (entry.value / metricTotal)
                                  .clamp(0.0, 1.0)
                                  .toDouble();
                        final color = _getStatusColor(entry.key);
                        return Material(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () {
                              setState(
                                () => _selectedOrderStatusFilter = entry.key,
                              );
                              Navigator.pop(sheetContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _scrollToOrderExplorer();
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: color,
                                          borderRadius: BorderRadius.circular(
                                            4,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 9),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              entry.key,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.cairo(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: _textColor,
                                              ),
                                            ),
                                            Text(
                                              '${_statusDistribution[entry.key] ?? 0} orders',
                                              style: GoogleFonts.cairo(
                                                fontSize: 10,
                                                color: _secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        value,
                                        style: GoogleFonts.cairo(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w800,
                                          color: _textColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: LinearProgressIndicator(
                                      value: share,
                                      minHeight: 5,
                                      backgroundColor: color.withOpacity(0.12),
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        color,
                                      ),
                                    ),
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

  void _showFactoryBreakdown() {
    final byFactory = <String, int>{};
    final valueByFactory = <String, double>{};
    for (final order in _dateFilteredOrders) {
      final factory = order.factory?.trim() ?? '';
      byFactory[factory] = (byFactory[factory] ?? 0) + 1;
      valueByFactory[factory] = (valueByFactory[factory] ?? 0) + order.value;
    }
    final entries = byFactory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _buildDashboardSheetFrame(
        sheetContext: sheetContext,
        heightFactor: 0.78,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDashboardSheetHeader(
              sheetContext: sheetContext,
              title: 'Orders by factory',
              subtitle: 'Select a factory to filter the order explorer.',
              icon: Icons.factory_rounded,
              accentColor: Colors.indigo,
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: Colors.indigo.withOpacity(0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${entries.length} factory groups',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                  ),
                  Text(
                    '${_dateFilteredOrders.length} orders',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: entries.isEmpty
                  ? Center(
                      child: Text(
                        'No factory data for this date range.',
                        style: GoogleFonts.cairo(color: _secondaryTextColor),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 8),
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final share = _dateFilteredOrders.isEmpty
                            ? 0.0
                            : (entry.value / _dateFilteredOrders.length)
                                  .clamp(0.0, 1.0)
                                  .toDouble();
                        return Material(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            onTap: () {
                              setState(
                                () => _selectedFactoryFilter = entry.key,
                              );
                              Navigator.pop(sheetContext);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _scrollToOrderExplorer();
                              });
                            },
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                              padding: const EdgeInsets.all(13),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Column(
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: Colors.indigo.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(
                                            11,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.factory_rounded,
                                          size: 18,
                                          color: Colors.indigo,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              _factoryLabel(entry.key),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.cairo(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: _textColor,
                                              ),
                                            ),
                                            Text(
                                              '${entry.value} orders',
                                              style: GoogleFonts.cairo(
                                                fontSize: 10,
                                                color: _secondaryTextColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '\$${_formatNumber(valueByFactory[entry.key] ?? 0)}',
                                        style: GoogleFonts.cairo(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w800,
                                          color: _textColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(20),
                                    child: LinearProgressIndicator(
                                      value: share,
                                      minHeight: 5,
                                      backgroundColor: Colors.indigo
                                          .withOpacity(0.1),
                                      valueColor:
                                          const AlwaysStoppedAnimation<Color>(
                                            Colors.indigo,
                                          ),
                                    ),
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

  void _showEmployeeDirectory() {
    var query = '';
    String? departmentFilter;
    var activeOnly = true;
    final departments =
        _allEmployees
            .map((employee) => employee.department?.trim() ?? '')
            .where((department) => department.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final employees =
              _allEmployees.where((employee) {
                if (activeOnly && !employee.isActive) return false;
                if (departmentFilter != null &&
                    employee.department != departmentFilter) {
                  return false;
                }
                final searchText = query.trim().toLowerCase();
                return searchText.isEmpty ||
                    employee.fullName.toLowerCase().contains(searchText) ||
                    employee.username.toLowerCase().contains(searchText) ||
                    (employee.role ?? '').toLowerCase().contains(searchText);
              }).toList()..sort(
                (a, b) => a.fullName.toLowerCase().compareTo(
                  b.fullName.toLowerCase(),
                ),
              );
          return _buildDashboardSheetFrame(
            sheetContext: sheetContext,
            heightFactor: 0.88,
            child: Column(
              children: [
                _buildDashboardSheetHeader(
                  sheetContext: sheetContext,
                  title: 'Employee directory',
                  subtitle: 'Search by name, account, role, or department.',
                  icon: Icons.groups_rounded,
                  accentColor: Colors.purple,
                ),
                TextField(
                  onChanged: (value) => setSheetState(() => query = value),
                  style: GoogleFonts.cairo(color: _textColor),
                  decoration: InputDecoration(
                    hintText: 'Search name, username, or role',
                    hintStyle: GoogleFonts.cairo(
                      fontSize: 11,
                      color: _secondaryTextColor,
                    ),
                    prefixIcon: const Icon(Icons.search),
                    prefixIconColor: Theme.of(context).colorScheme.primary,
                    filled: true,
                    fillColor: _surfaceColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: _borderColor),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  children: [
                    FilterChip(
                      label: const Text('Active only'),
                      selected: activeOnly,
                      onSelected: (value) =>
                          setSheetState(() => activeOnly = value),
                    ),
                    ChoiceChip(
                      label: const Text('All departments'),
                      selected: departmentFilter == null,
                      onSelected: (_) =>
                          setSheetState(() => departmentFilter = null),
                    ),
                    ...departments.map(
                      (department) => ChoiceChip(
                        label: Text(department),
                        selected: departmentFilter == department,
                        onSelected: (_) => setSheetState(
                          () =>
                              departmentFilter = departmentFilter == department
                              ? null
                              : department,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  margin: const EdgeInsets.only(top: 2, bottom: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.people_alt_outlined,
                        size: 15,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '${employees.length} matching employees',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textColor,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: employees.isEmpty
                      ? Center(
                          child: Text(
                            'No employees match these filters',
                            style: GoogleFonts.cairo(
                              color: _secondaryTextColor,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(bottom: 8),
                          itemCount: employees.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 7),
                          itemBuilder: (context, index) {
                            final employee = employees[index];
                            final employeeColor = employee.isActive
                                ? Colors.green
                                : _secondaryTextColor;
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: _cardColor,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: _borderColor),
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 21,
                                    backgroundColor: Colors.purple.withOpacity(
                                      0.1,
                                    ),
                                    child: Text(
                                      employee.initials,
                                      style: const TextStyle(
                                        color: Colors.purple,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 11),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          employee.displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: _textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 1),
                                        Text(
                                          [employee.department, employee.role]
                                              .where(
                                                (part) =>
                                                    part?.trim().isNotEmpty ??
                                                    false,
                                              )
                                              .join(' · '),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                            fontSize: 10,
                                            color: _secondaryTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: employeeColor.withOpacity(0.11),
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      employee.isActive ? 'Active' : 'Inactive',
                                      style: GoogleFonts.cairo(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: employeeColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildOrderExplorer() {
    final baseOrders = _dateFilteredOrders;
    final statuses =
        baseOrders.map((order) => order.status.trim()).toSet().toList()
          ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final factories =
        baseOrders.map((order) => order.factory?.trim() ?? '').toSet().toList()
          ..sort(
            (a, b) =>
                _factoryLabel(a)
                    .toLowerCase()
                    .compareTo(_factoryLabel(b).toLowerCase()),
          );
    final orders = _filteredExplorerOrders;
    final shownOrders = _showAllExplorerOrders
        ? orders
        : orders.take(8).toList();
    final totalValue = orders.fold<double>(
      0,
      (sum, order) => sum + order.value,
    );

    return Container(
      key: _orderExplorerKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: _dashboardCardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.manage_search,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Order explorer',
                  style: GoogleFonts.cairo(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: orders.isEmpty || _isExporting
                    ? null
                    : _exportFilteredOrders,
                icon: _isExporting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.file_download_outlined, size: 17),
                label: Text(_isExporting ? 'Exporting' : 'Export'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  textStyle: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 3),
              IconButton.filledTonal(
                tooltip: 'Clear order filters',
                onPressed: _clearOrderExplorerFilters,
                style: IconButton.styleFrom(
                  backgroundColor: _surfaceColor,
                  foregroundColor: _secondaryTextColor,
                ),
                icon: const Icon(Icons.filter_alt_off_outlined, size: 18),
              ),
            ],
          ),
          Text(
            'Search and open a live order. Filters here do not change the existing charts.',
            style: GoogleFonts.cairo(fontSize: 11, color: _secondaryTextColor),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _orderSearchController,
            onChanged: (_) => setState(() => _showAllExplorerOrders = false),
            style: GoogleFonts.cairo(color: _textColor),
            decoration: InputDecoration(
              hintText: 'Search order, contract, customer, product, engineer…',
              hintStyle: GoogleFonts.cairo(
                fontSize: 12,
                color: _secondaryTextColor,
              ),
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _orderSearchController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      onPressed: () {
                        _orderSearchController.clear();
                        setState(() => _showAllExplorerOrders = false);
                      },
                      icon: const Icon(Icons.close),
                    ),
              filled: true,
              fillColor: _surfaceColor,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _borderColor),
              ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 560
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              final selectedStatus =
                  statuses.contains(_selectedOrderStatusFilter)
                  ? _selectedOrderStatusFilter ?? '__all__'
                  : '__all__';
              final selectedFactory = _selectedFactoryFilter == null
                  ? '__all__'
                  : factories.contains(_selectedFactoryFilter)
                  ? (_selectedFactoryFilter!.isEmpty
                        ? '__missing__'
                        : _selectedFactoryFilter!)
                  : '__all__';
              return Wrap(
                spacing: 10,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      value: selectedStatus,
                      isExpanded: true,
                      decoration: _filterDecoration('Status'),
                      items: [
                        const DropdownMenuItem(
                          value: '__all__',
                          child: Text('All statuses'),
                        ),
                        ...statuses.map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(
                              status,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _selectedOrderStatusFilter =
                            value == null || value == '__all__' ? null : value;
                      }),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      value: selectedFactory,
                      isExpanded: true,
                      decoration: _filterDecoration('Factory'),
                      items: [
                        const DropdownMenuItem(
                          value: '__all__',
                          child: Text('All factories'),
                        ),
                        ...factories.map(
                          (factory) => DropdownMenuItem(
                            value: factory.isEmpty ? '__missing__' : factory,
                            child: Text(
                              factory.isEmpty
                                  ? 'No factory recorded'
                                  : _factoryLabel(factory),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => setState(() {
                        _selectedFactoryFilter =
                            value == null || value == '__all__'
                            ? null
                            : value == '__missing__'
                            ? ''
                            : value;
                      }),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Attention filters',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _buildAttentionChip(
                'Overdue delivery',
                'overdue_delivery',
                baseOrders.where(_hasOverdueDelivery).length,
                Colors.red,
              ),
              _buildAttentionChip(
                'Missing delivery date',
                'missing_delivery',
                baseOrders
                    .where(
                      (order) => order.deliveryDate?.trim().isNotEmpty != true,
                    )
                    .length,
                Colors.orange,
              ),
              _buildAttentionChip(
                'Missing sales engineer',
                'missing_engineer',
                baseOrders
                    .where((order) => order.salesEngineer.trim().isEmpty)
                    .length,
                Colors.deepPurple,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 7,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Sort:',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: _secondaryTextColor,
                      ),
                    ),
                    ...[
                      'Newest',
                      'Highest value',
                      'Largest quantity',
                      'Customer A–Z',
                    ].map(
                      (sort) => ChoiceChip(
                        label: Text(
                          sort,
                          style: GoogleFonts.cairo(fontSize: 10),
                        ),
                        selected: _orderSort == sort,
                        onSelected: (_) => setState(() => _orderSort = sort),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: _isDark
                  ? Colors.white.withOpacity(0.035)
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _borderColor),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${orders.length} matching orders',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                  ),
                ),
                Text(
                  'Value: \$${_formatNumber(totalValue)}',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (shownOrders.isEmpty)
            Padding(
              padding: const EdgeInsets.all(26),
              child: Center(
                child: Text(
                  'No orders match these filters.',
                  style: GoogleFonts.cairo(color: _secondaryTextColor),
                ),
              ),
            )
          else
            ...shownOrders.map(_buildExplorerOrderCard),
          if (orders.length > 8)
            Center(
              child: TextButton.icon(
                onPressed: () => setState(
                  () => _showAllExplorerOrders = !_showAllExplorerOrders,
                ),
                icon: Icon(
                  _showAllExplorerOrders
                      ? Icons.expand_less
                      : Icons.expand_more,
                ),
                label: Text(
                  _showAllExplorerOrders
                      ? 'Show fewer orders'
                      : 'Show all ${orders.length} orders',
                  style: GoogleFonts.cairo(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  InputDecoration _filterDecoration(String label) => InputDecoration(
    labelText: label,
    labelStyle: GoogleFonts.cairo(fontSize: 11, color: _secondaryTextColor),
    filled: true,
    fillColor: _surfaceColor,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _borderColor),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: _borderColor),
    ),
  );

  Widget _buildAttentionChip(
    String label,
    String value,
    int count,
    Color color,
  ) {
    final selected = _attentionFilter == value;
    return FilterChip(
      label: Text('$label · $count', style: GoogleFonts.cairo(fontSize: 10)),
      selected: selected,
      onSelected: count == 0
          ? null
          : (_) => setState(() {
              _attentionFilter = selected ? null : value;
              _showAllExplorerOrders = false;
            }),
      avatar: Icon(Icons.flag_outlined, size: 14, color: color),
      selectedColor: color.withOpacity(0.14),
      checkmarkColor: color,
      side: BorderSide(color: selected ? color : _borderColor),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildExplorerOrderCard(SAPMainOrder order) {
    final statusColor = _getStatusColor(order.status);
    final createdDate = order.createdAt == null
        ? 'Created date unavailable'
        : DateFormat('dd MMM yyyy').format(order.createdAt!.toLocal());
    return Card(
      color: _surfaceColor,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(top: 9),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: _borderColor.withOpacity(0.9)),
      ),
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => OrderTrackingPage(order: order)),
        ),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      order.description.trim().isEmpty
                          ? 'No description'
                          : order.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: _textColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(_isDark ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: statusColor.withOpacity(0.2)),
                    ),
                    child: Text(
                      order.status,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  _buildOrderMeta(
                    Icons.tag_rounded,
                    'Design ${order.designOrder}',
                  ),
                  _buildOrderMeta(
                    Icons.description_outlined,
                    'Contract ${order.contractNumber}',
                  ),
                  _buildOrderMeta(
                    Icons.person_outline,
                    order.customerName.isEmpty
                        ? 'Customer missing'
                        : order.customerName,
                  ),
                  _buildOrderMeta(
                    Icons.factory_outlined,
                    _factoryLabel(order.factory),
                  ),
                  _buildOrderMeta(Icons.calendar_today_outlined, createdDate),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 11),
                child: Divider(height: 1, color: _borderColor),
              ),
              Row(
                children: [
                  Expanded(
                    child: _buildOrderMetric(
                      icon: Icons.inventory_2_rounded,
                      label: 'QUANTITY',
                      value:
                          '${NumberFormat.decimalPattern().format(order.quantity)} ${order.unitOfMeasure}',
                      color: Colors.deepOrange,
                    ),
                  ),
                  Container(width: 1, height: 36, color: _borderColor),
                  Expanded(
                    child: _buildOrderMetric(
                      icon: Icons.payments_rounded,
                      label: 'ORDER VALUE',
                      value: '\$${_formatNumber(order.value)}',
                      color: Colors.teal,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _secondaryTextColor,
                    size: 20,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderMeta(IconData icon, String text) => Container(
    constraints: const BoxConstraints(maxWidth: 260),
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _isDark ? Colors.white.withOpacity(0.04) : const Color(0xFFF8FAFC),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: _borderColor.withOpacity(0.8)),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _secondaryTextColor),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: _secondaryTextColor,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildOrderMetric({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color.withOpacity(_isDark ? 0.18 : 0.1),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.35,
                  color: _secondaryTextColor,
                ),
              ),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: _textColor,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  void _clearOrderExplorerFilters() {
    _orderSearchController.clear();
    setState(() {
      _selectedFactoryFilter = null;
      _selectedOrderStatusFilter = null;
      _attentionFilter = null;
      _orderSort = 'Newest';
      _showAllExplorerOrders = false;
    });
  }

  Future<void> _exportFilteredOrders() async {
    final orders = _filteredExplorerOrders;
    if (orders.isEmpty || _isExporting) return;
    setState(() => _isExporting = true);
    try {
      final location = await ExcelExportService.exportOrdersToExcel(orders);
      if (mounted) {
        _showSnackBar(
          kIsWeb
              ? 'Excel file downloaded: $location'
              : 'Excel file saved: $location',
        );
      }
    } catch (e) {
      debugPrint('Could not export dashboard orders: $e');
      if (mounted) _showSnackBar('Could not export these orders.');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Widget _buildRecentActivityCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: _dashboardCardShadows,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Recent order activity',
                  style: GoogleFonts.cairo(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
              ),
              Text(
                '${_recentActivity.length} events',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  color: _secondaryTextColor,
                ),
              ),
            ],
          ),
          Text(
            'Latest entries from order_audit_log. Tap an event to open its order when it is still active.',
            style: GoogleFonts.cairo(fontSize: 11, color: _secondaryTextColor),
          ),
          const SizedBox(height: 8),
          if (_recentActivity.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Row(
                children: [
                  Icon(
                    _activityLoadFailed
                        ? Icons.lock_outline
                        : Icons.inbox_outlined,
                    color: _secondaryTextColor,
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      _activityLoadFailed
                          ? 'Recent activity is unavailable for this account.'
                          : 'No audit entries were returned.',
                      style: GoogleFonts.cairo(color: _secondaryTextColor),
                    ),
                  ),
                ],
              ),
            )
          else
            ..._recentActivity.take(8).map(_buildActivityRow),
        ],
      ),
    );
  }

  Widget _buildActivityRow(Map<String, dynamic> activity) {
    final order = _findOrderForActivity(activity);
    final field = activity['field_name']?.toString().trim() ?? 'order';
    final oldValue = activity['old_value']?.toString().trim() ?? '';
    final newValue = activity['new_value']?.toString().trim() ?? '';
    final action = activity['action_type']?.toString().trim() ?? 'update';
    final changedBy =
        activity['changed_by']?.toString().trim() ?? 'Unknown user';
    final designOrder = activity['design_order']?.toString().trim() ?? '';
    final changedAt = _parseAuditDate(activity['changed_at']);
    final eventText = oldValue.isEmpty && newValue.isEmpty
        ? '$action · ${activity['notes']?.toString().trim() ?? ''}'
        : oldValue.isEmpty
        ? '$field set to $newValue'
        : newValue.isEmpty
        ? '$field cleared (was $oldValue)'
        : '$field: $oldValue → $newValue';
    final compactEvent = eventText.length > 105
        ? '${eventText.substring(0, 102)}…'
        : eventText;

    return Card(
      color: _surfaceColor,
      elevation: 0,
      margin: const EdgeInsets.only(top: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: _borderColor),
      ),
      child: InkWell(
        onTap: order == null
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => OrderTrackingPage(order: order),
                ),
              ),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  field.toLowerCase() == 'status'
                      ? Icons.swap_horiz
                      : Icons.edit_outlined,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Order ${designOrder.isNotEmpty ? designOrder : activity['order_id'] ?? 'unknown'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                    Text(
                      compactEvent,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        color: _secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$changedBy${changedAt == null ? '' : ' · ${DateFormat('dd MMM, h:mm a').format(changedAt)}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 9,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (order != null)
                Icon(Icons.chevron_right, size: 18, color: _secondaryTextColor),
            ],
          ),
        ),
      ),
    );
  }

  SAPMainOrder? _findOrderForActivity(Map<String, dynamic> activity) {
    final orderId = activity['order_id']?.toString().trim() ?? '';
    final designOrder = activity['design_order']?.toString().trim() ?? '';
    for (final order in _allOrders) {
      if ((orderId.isNotEmpty && order.id == orderId) ||
          (designOrder.isNotEmpty && order.designOrder == designOrder)) {
        return order;
      }
    }
    return null;
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
              padding: EdgeInsets.all(
                MediaQuery.of(context).size.width < 600 ? 8 : 24,
              ),
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
                  SizedBox(
                    height: MediaQuery.of(context).size.width < 600 ? 12 : 24,
                  ),

                  _buildDateRangeFilter(),
                  SizedBox(
                    height: MediaQuery.of(context).size.width < 600 ? 12 : 20,
                  ),

                  _buildDashboardOverview(),
                  const SizedBox(height: 20),

                  _buildOrderExplorer(),
                  const SizedBox(height: 20),

                  _buildRecentActivityCard(),
                  const SizedBox(height: 24),

                  // Comparison Section
                  _buildComparisonSection(),
                  SizedBox(
                    height: MediaQuery.of(context).size.width < 600 ? 12 : 24,
                  ),

                  // Stage status analytics
                  _buildStageStatusGraph(),
                  const SizedBox(height: 24),
                  _buildCircularStageStatusGraph(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildDateRangeFilter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.date_range_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Created date range',
                      style: GoogleFonts.cairo(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                    Text(
                      'Overview and explorer use the order creation date',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (_hasDateRange)
                TextButton.icon(
                  onPressed: _clearDateRange,
                  icon: const Icon(Icons.clear, size: 16),
                  label: Text('Clear', style: GoogleFonts.cairo(fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildDatePresetChip('All time', 'all'),
              _buildDatePresetChip('7 days', '7d'),
              _buildDatePresetChip('30 days', '30d'),
              _buildDatePresetChip('This month', 'month'),
              _buildDatePresetChip('Year to date', 'ytd'),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final fieldWidth = constraints.maxWidth >= 580
                  ? (constraints.maxWidth - 10) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  SizedBox(
                    width: fieldWidth,
                    child: _buildDateField(
                      label: 'Custom start date',
                      date: _startDate,
                      icon: Icons.calendar_month,
                      onTap: _pickStartDate,
                    ),
                  ),
                  SizedBox(
                    width: fieldWidth,
                    child: _buildDateField(
                      label: 'Custom end date',
                      date: _endDate,
                      icon: Icons.event,
                      onTap: _pickEndDate,
                    ),
                  ),
                ],
              );
            },
          ),
          if (_hasDateRange) ...[
            const SizedBox(height: 8),
            Text(
              _getDateFilterLabel(),
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatePresetChip(String label, String value) {
    final selected = _datePreset == value;
    return ChoiceChip(
      label: Text(label, style: GoogleFonts.cairo(fontSize: 11)),
      selected: selected,
      onSelected: (_) => _applyDatePreset(value),
      selectedColor: Theme.of(context).colorScheme.primary.withOpacity(0.14),
      backgroundColor: _surfaceColor,
      side: BorderSide(
        color: selected ? Theme.of(context).colorScheme.primary : _borderColor,
      ),
      labelStyle: TextStyle(
        color: selected ? Theme.of(context).colorScheme.primary : _textColor,
        fontWeight: FontWeight.w600,
      ),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  void _applyDatePreset(String preset) {
    final today = _dateOnly(DateTime.now());
    DateTime? start;
    DateTime? end;
    switch (preset) {
      case '7d':
        start = today.subtract(const Duration(days: 6));
        end = today;
        break;
      case '30d':
        start = today.subtract(const Duration(days: 29));
        end = today;
        break;
      case 'month':
        start = DateTime(today.year, today.month);
        end = today;
        break;
      case 'ytd':
        start = DateTime(today.year, 1, 1);
        end = today;
        break;
    }
    setState(() {
      _datePreset = preset;
      _startDate = start;
      _endDate = end;
      _selectedFactoryFilter = null;
      _selectedOrderStatusFilter = null;
      _attentionFilter = null;
    });
    _recalculateDashboard();
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

    setState(() {
      _startDate = date;
      _datePreset = 'custom';
      _selectedFactoryFilter = null;
      _selectedOrderStatusFilter = null;
      _attentionFilter = null;
    });
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

    setState(() {
      _endDate = date;
      _datePreset = 'custom';
      _selectedFactoryFilter = null;
      _selectedOrderStatusFilter = null;
      _attentionFilter = null;
    });
    _recalculateDashboard();
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _datePreset = 'all';
      _selectedFactoryFilter = null;
      _selectedOrderStatusFilter = null;
      _attentionFilter = null;
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
          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
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
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.all(isMobile ? 12 : 20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order Breakdown', style: GoogleFonts.cairo(
              fontSize: isMobile ? 18 : 20,
              fontWeight: FontWeight.w700, color: _textColor)),
          SizedBox(height: isMobile ? 10 : 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 1050 ? 3 :
              constraints.maxWidth >= 620 ? 2 : 1;
              final gap = isMobile ? 8.0 : 14.0;
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
  }) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: isMobile ? 17 : 20),
            ),
            const SizedBox(width: 7),
            Expanded(child: Text(title, style: GoogleFonts.cairo(
                fontSize: isMobile ? 14 : 16,
                fontWeight: FontWeight.w700, color: color))),
          ]),
          SizedBox(height: isMobile ? 8 : 12),
          _buildComparisonRow('Orders', '$orderCount', color),
          const SizedBox(height: 4),
          _buildComparisonRow('Value', '\$${_formatNumber(totalValue)}', color),
          const SizedBox(height: 4),
          _buildComparisonRow('QTY', totalQuantity.toStringAsFixed(0), color),
          if (statuses != null && statuses.isNotEmpty) ...[
            Divider(color: color.withOpacity(0.3), height: isMobile ? 16 : 22),
            Text('Status breakdown', style: GoogleFonts.cairo(
                fontSize: isMobile ? 11 : 12,
                fontWeight: FontWeight.w700, color: _secondaryTextColor)),
            const SizedBox(height: 6),
            Builder(builder: (context) {
              final counts = statuses.map((status) => _statusDistribution[status] ?? 0).toList();
              final total = counts.fold<int>(0, (sum, count) => sum + count);
              final legend = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: statuses.asMap().entries.map((entry) {
                  final status = entry.value;
                  final count = counts[entry.key];
                  final percent = total == 0 ? 0.0 : count / total * 100;
                  return Padding(
                    padding: EdgeInsets.only(bottom: isMobile ? 3 : 5),
                    child: Row(children: [
                      Container(width: 7, height: 7, decoration: BoxDecoration(
                          color: _getStatusColor(status), shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Expanded(child: Text(status, maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(fontSize: isMobile ? 9 : 10,
                              color: _secondaryTextColor))),
                      Text('${percent.toStringAsFixed(0)}%  $count',
                          style: GoogleFonts.cairo(fontSize: isMobile ? 9 : 10,
                              fontWeight: FontWeight.w700, color: _textColor)),
                    ]),
                  );
                }).toList(),
              );
              final pie = SizedBox(
                width: isMobile ? 92 : 120,
                height: isMobile ? 92 : 120,
                child: PieChart(PieChartData(
                  startDegreeOffset: -90,
                  sectionsSpace: 2,
                  centerSpaceRadius: isMobile ? 23 : 30,
                  sections: statuses.asMap().entries.map((entry) {
                    final count = counts[entry.key];
                    return PieChartSectionData(
                      value: count > 0 ? count.toDouble() : 0.0001,
                      color: _getStatusColor(entry.value),
                      radius: isMobile ? 18 : 23,
                      title: '',
                    );
                  }).toList(),
                )),
              );
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  pie,
                  SizedBox(width: isMobile ? 8 : 12),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$total orders', style: GoogleFonts.cairo(
                          fontSize: isMobile ? 11 : 12,
                          fontWeight: FontWeight.w700, color: _textColor)),
                      const SizedBox(height: 5),
                      legend,
                    ],
                  )),
                ],
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
          style: GoogleFonts.cairo(fontSize: 12, color: _secondaryTextColor),
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
    final isMobile = MediaQuery.of(context).size.width < 600;
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
                normalized != 'no one' &&
                normalized != 'header' &&
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
        padding: EdgeInsets.fromLTRB(isMobile ? 5 : 9, 7, isMobile ? 3 : 9, 7),
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
              horizontalTitleGap: 6,
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
      padding: EdgeInsets.all(MediaQuery.of(context).size.width < 600 ? 10 : 16),
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
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildGroupingTab('factory', 'Factories', _stageGraphGrouping,
                          (value) => setState(() => _stageGraphGrouping = value)),
                  _buildGroupingTab('date', 'Dates', _stageGraphGrouping,
                          (value) => setState(() => _stageGraphGrouping = value)),
                  _buildGroupingTab('employee', 'Employees', _stageGraphGrouping,
                          (value) => setState(() => _stageGraphGrouping = value)),
                ],
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
                  : constraints.maxWidth >= 320
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
              height: MediaQuery.of(context).size.width < 600 ? 600 : 380,
              child: LayoutBuilder(
                builder: (context, chartConstraints) {
                  final isMobileChart = MediaQuery.of(context).size.width < 600;
                  final chartWidth = (visibleCategories.length * (isMobileChart ? 260.0 : 145.0))
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
                                        fontSize: MediaQuery.of(context).size.width < 600 ? 20 : 13,
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
                                    reservedSize: MediaQuery.of(context).size.width < 600 ? 72 : 50,
                                    getTitlesWidget: (value, meta) => Text(
                                      value.toInt().toString(),
                                      style: TextStyle(
                                        color: _secondaryTextColor,
                                        fontSize: MediaQuery.of(context).size.width < 600 ? 20 : 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                                bottomTitles: AxisTitles(
                                  sideTitles: SideTitles(
                                    showTitles: true,
                                    reservedSize: MediaQuery.of(context).size.width < 600 ? 140 : 82,
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
                                        space: MediaQuery.of(context).size.width < 600 ? 16 : 10,
                                        child: SizedBox(
                                          width: MediaQuery.of(context).size.width < 600 ? 240 : 100,
                                          child: Text(
                                            label,
                                            maxLines: MediaQuery.of(context).size.width < 600 ? 4 : 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                              color: _secondaryTextColor,
                                              fontSize: MediaQuery.of(context).size.width < 600 ? 18 : 11,
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
                                      width: MediaQuery.of(context).size.width < 600
                                          ? (activeStatuses.length > 8 ? 18 : 32)
                                          : (activeStatuses.length > 8 ? 10 : 20),
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

  Widget _buildCircularStageStatusGraph() {
    final stageStatuses = <String, List<String>>{
      'Submittal': _beforeApprovalStatuses,
      'Approval': _approvalStatuses,
      'Manufacturing': _manufacturingStatuses,
    };
    final selectedByStage = <String, Set<String>>{
      'Submittal': _selectedCircularSubmittalStatuses,
      'Approval': _selectedCircularApprovalStatuses,
      'Manufacturing': _selectedCircularManufacturingStatuses,
    };
    final stageColors = <String, Color>{
      'Submittal': Colors.purple,
      'Approval': Colors.green,
      'Manufacturing': Colors.orange,
    };
    final isMobile = MediaQuery.of(context).size.width < 600;
    // Cycle through a broad palette so every category remains distinguishable,
    // even when there are many slices.
    const circularPalette = <Color>[
      Color(0xFF2563EB), Color(0xFFDC2626), Color(0xFF059669),
      Color(0xFF9333EA), Color(0xFFD97706), Color(0xFF0891B2),
      Color(0xFFDB2777), Color(0xFF4F46E5), Color(0xFF65A30D),
      Color(0xFFEA580C), Color(0xFF0F766E), Color(0xFF7C3AED),
      Color(0xFFB91C1C), Color(0xFF0284C7), Color(0xFF854D0E),
      Color(0xFFBE185D), Color(0xFF4338CA), Color(0xFF15803D),
      Color(0xFF6D28D9), Color(0xFF0E7490),
    ];
    Color circularColor(int index) => circularPalette[index % circularPalette.length];

    // Years with less than 5% of filtered orders are combined into one "Other" slice.
    final smallDateYears = <String>{};

    List<String> categoriesForOrder(SAPMainOrder order) {
      switch (_circularGraphGrouping) {
        case 'date':
          final rawDate = order.orderDate?.trim() ?? '';
          final parsedDate = DateTime.tryParse(rawDate);
          if (parsedDate == null) {
            return [rawDate.isEmpty ? 'Unknown date' : 'Other'];
          }
          final year = parsedDate.year.toString();
          // Small years stay as a single yearly slice; larger years expand into months.
          return [
            smallDateYears.contains(year)
                ? year
                : DateFormat('yyyy-MM').format(parsedDate),
          ];
        case 'employee':
          bool valid(String value) {
            final v = value.trim().toLowerCase();
            return v.isNotEmpty &&
                !{'null', 'n/a', 'none', 'no one', 'header', '-'}.contains(v);
          }

          final assigned = order.correspondenceEngineer?.trim() ?? '';
          if (valid(assigned)) return [assigned];
          final responsible = order.responsibleEngineer?.trim() ?? '';
          return [valid(responsible) ? responsible : 'Unassigned'];
        case 'factory':
        default:
          final factory = order.factory?.trim() ?? '';
          if (factory.isEmpty) return ['Unknown factory'];
          final description = _factoryDescriptions[factory.toLowerCase()]?.trim() ?? '';
          return [description.isEmpty ? factory : description];
      }
    }

    final activeStatuses = <String>[
      for (final stage in stageStatuses.keys)
        ...stageStatuses[stage]!.where(selectedByStage[stage]!.contains),
    ];

    // Decide the date granularity independently for each year using the
    // currently selected statuses. Years below 5% remain one yearly slice;
    // years at or above 5% are split into monthly slices.
    if (_circularGraphGrouping == 'date') {
      final yearCounts = <String, int>{};
      var selectedOrderCount = 0;
      for (final order in _allOrders) {
        if (!activeStatuses.contains(order.status.trim())) continue;
        selectedOrderCount++;
        final parsedDate = DateTime.tryParse(order.orderDate?.trim() ?? '');
        if (parsedDate != null) {
          final year = parsedDate.year.toString();
          yearCounts[year] = (yearCounts[year] ?? 0) + 1;
        }
      }
      if (selectedOrderCount > 0) {
        for (final entry in yearCounts.entries) {
          if (entry.value / selectedOrderCount < 0.10) {
            smallDateYears.add(entry.key);
          }
        }
      }
    }
    final categories = <String>{};
    for (final order in _allOrders) {
      if (activeStatuses.contains(order.status.trim())) {
        categories.addAll(categoriesForOrder(order));
      }
    }
    final sortedCategories = categories.toList()..sort();
    final counts = sortedCategories.map((category) => _allOrders.where((order) =>
    activeStatuses.contains(order.status.trim()) &&
        categoriesForOrder(order).contains(category)).length).toList();
    final total = counts.fold<int>(0, (sum, count) => sum + count);
    final selectedCount = selectedByStage.values.fold<int>(
        0, (sum, selected) => sum + selected.length);

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
            Row(children: [
              Expanded(child: Text(stage, style: GoogleFonts.cairo(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700))),
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
            ]),
            ...statuses.map((status) => CheckboxListTile(
              dense: true,
              minVerticalPadding: 0,
              contentPadding: EdgeInsets.zero,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(status, style: GoogleFonts.cairo(fontSize: 10, color: _textColor)),
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

    final chartContent = activeStatuses.isEmpty || sortedCategories.isEmpty || total == 0
        ? Padding(
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Text(
          activeStatuses.isEmpty
              ? 'Select at least one stage status to display the chart.'
              : 'No matching orders for the selected filters.',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(color: _secondaryTextColor),
        ),
      ),
    )
        : Column(
      children: [
        SizedBox(
          height: isMobile ? 340 : 390,
          child: Stack(
            children: [
              PieChart(PieChartData(
                startDegreeOffset: -90,
                sectionsSpace: 2,
                centerSpaceRadius: isMobile ? 44 : 58,
                pieTouchData: PieTouchData(
                  touchCallback: (event, response) {
                    final touchedIndex = response?.touchedSection?.touchedSectionIndex;
                    if (event is FlPointerHoverEvent || event is FlPanUpdateEvent) {
                      if (mounted && _hoveredCircularPieIndex != touchedIndex) {
                        setState(() => _hoveredCircularPieIndex = touchedIndex);
                      }
                    }
                    if (event is! FlTapUpEvent || touchedIndex == null ||
                        touchedIndex < 0 || touchedIndex >= sortedCategories.length) return;
                    final category = sortedCategories[touchedIndex];
                    final matchingOrders = _allOrders.where((order) =>
                    activeStatuses.contains(order.status.trim()) &&
                        categoriesForOrder(order).contains(category)).toList()
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
                        child: Column(children: [
                          Padding(
                            padding: const EdgeInsets.all(18),
                            child: Row(children: [
                              Expanded(child: Text('$category • ${matchingOrders.length} orders',
                                  style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w700, color: _textColor))),
                              IconButton(onPressed: () => Navigator.pop(sheetContext),
                                  icon: Icon(Icons.close, color: _secondaryTextColor)),
                            ]),
                          ),
                          Divider(height: 1, color: _borderColor),
                          Expanded(
                            child: matchingOrders.isEmpty
                                ? Center(child: Text('No orders found', style: GoogleFonts.cairo(color: _secondaryTextColor)))
                                : ListView.builder(
                              padding: const EdgeInsets.all(14),
                              itemCount: matchingOrders.length,
                              itemBuilder: (context, index) {
                                final order = matchingOrders[index];
                                return Card(
                                  color: _cardColor,
                                  child: ListTile(
                                    title: Text(order.description.isEmpty ? 'No description' : order.description,
                                        maxLines: 2, overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.cairo(color: _textColor, fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                        'Status: ${order.status}\nOrder: ${order.designOrder} • Contract: ${order.contractNumber}\nFactory: ${order.factory ?? 'N/A'} • Qty: ${order.quantity}',
                                        style: GoogleFonts.cairo(fontSize: 11, color: _secondaryTextColor)),
                                    trailing: Icon(Icons.chevron_right, color: _secondaryTextColor),
                                    onTap: () {
                                      Navigator.pop(sheetContext);
                                      Navigator.push(context, MaterialPageRoute(
                                          builder: (_) => OrderTrackingPage(order: order)));
                                    },
                                  ),
                                );
                              },
                            ),
                          ),
                        ]),
                      ),
                    );
                  },
                ),
                sections: List.generate(sortedCategories.length, (index) {
                  final count = counts[index];
                  final maxCount = counts.fold<int>(0, (largest, value) => value > largest ? value : largest);
                  // fl_chart has no minimum-angle option. A small visual floor keeps
                  // low-count categories visible; tooltips and order lists use real counts.
                  final minimumSliceValue = maxCount * 0.025;
                  return PieChartSectionData(
                    value: count.toDouble() < minimumSliceValue ? minimumSliceValue : count.toDouble(),
                    color: circularColor(index),
                    radius: isMobile ? 82 : 92,
                    title: '',
                  );
                }),
              )),
              if (_hoveredCircularPieIndex != null &&
                  _hoveredCircularPieIndex! >= 0 &&
                  _hoveredCircularPieIndex! < sortedCategories.length)
                Positioned(
                  top: 8, left: 8, right: 8,
                  child: IgnorePointer(
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _borderColor),
                          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8)],
                        ),
                        child: Builder(builder: (context) {
                          final i = _hoveredCircularPieIndex!;
                          final category = sortedCategories[i];
                          final categoryOrders = _allOrders.where((order) =>
                          activeStatuses.contains(order.status.trim()) &&
                              categoriesForOrder(order).contains(category)).toList();
                          return Text(
                            '$category\n${categoryOrders.length} orders',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.cairo(color: _textColor, fontSize: 12, fontWeight: FontWeight.w700),
                          );
                        }),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Text(
          '$total orders across ${sortedCategories.length} ${_circularGraphGrouping == 'factory' ? 'factories' : _circularGraphGrouping == 'employee' ? 'employees' : 'date groups'}',
          textAlign: TextAlign.center,
          style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: _textColor),
        ),
        const SizedBox(height: 14),

      ],
    );

    final categoryLegend = total == 0
        ? const SizedBox.shrink()
        : Wrap(
      spacing: 14,
      runSpacing: 10,
      children: List.generate(sortedCategories.length, (index) {
        final category = sortedCategories[index];
        final color = circularColor(index);
        return InkWell(
          onTap: () {
            final matchingOrders = _allOrders.where((order) =>
            activeStatuses.contains(order.status.trim()) &&
                categoriesForOrder(order).contains(category)).toList();
            if (matchingOrders.isNotEmpty) {
              final firstStatus = activeStatuses.firstWhere(
                    (status) => matchingOrders.any(
                        (order) => order.status.trim() == status),
                orElse: () => activeStatuses.first,
              );
              _showStageGraphOrders(
                category: category,
                status: firstStatus,
                categoriesForOrder: categoriesForOrder,
              );
            }
          },
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isMobile ? 170 : 240),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '$category  ${(counts[index] / total * 100).toStringAsFixed(1)}% • ${counts[index]} orders',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: _textColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );

    final selectionPanel = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                onPressed: () => setState(() {
                  _selectedCircularSubmittalStatuses.addAll(_beforeApprovalStatuses);
                  _selectedCircularApprovalStatuses.addAll(_approvalStatuses);
                  _selectedCircularManufacturingStatuses.addAll(_manufacturingStatuses);
                }),
                child: const Text('Select all'),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact),
                onPressed: () => setState(() {
                  _selectedCircularSubmittalStatuses.clear();
                  _selectedCircularApprovalStatuses.clear();
                  _selectedCircularManufacturingStatuses.clear();
                }),
                child: const Text('Clear all'),
              ),
            ]),
        Text('$selectedCount selected', style: GoogleFonts.cairo(fontSize: 11, color: _secondaryTextColor)),
        const SizedBox(height: 8),
        ...stageStatuses.entries.map((entry) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: stageFilter(entry.key, entry.value),
        )),
      ],
    );

    return Container(
      padding: EdgeInsets.all(isMobile ? 10 : 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borderColor),
        boxShadow: [BoxShadow(
            color: _isDark ? Colors.black.withOpacity(0.25) : Colors.black.withOpacity(0.035),
            blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 10,
              children: [
                Text('Circular Stage Status Analytics',
                    style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w700, color: _textColor)),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildGroupingTab('factory', 'Factories', _circularGraphGrouping,
                            (value) => setState(() => _circularGraphGrouping = value)),
                    _buildGroupingTab('date', 'Dates', _circularGraphGrouping,
                            (value) => setState(() => _circularGraphGrouping = value)),
                    _buildGroupingTab('employee', 'Employees', _circularGraphGrouping,
                            (value) => setState(() => _circularGraphGrouping = value)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Circular breakdown of orders by the selected grouping and stage statuses.',
                style: GoogleFonts.cairo(fontSize: 12, color: _secondaryTextColor)),
            const SizedBox(height: 14),
            chartContent,
            const SizedBox(height: 12),
            selectionPanel,
          ] else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        alignment: WrapAlignment.start,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          Text('Circular Stage Status Analytics',
                              style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w700, color: _textColor)),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _buildGroupingTab('factory', 'Factories', _circularGraphGrouping,
                                      (value) => setState(() => _circularGraphGrouping = value)),
                              _buildGroupingTab('date', 'Dates', _circularGraphGrouping,
                                      (value) => setState(() => _circularGraphGrouping = value)),
                              _buildGroupingTab('employee', 'Employees', _circularGraphGrouping,
                                      (value) => setState(() => _circularGraphGrouping = value)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Circular breakdown of orders by the selected grouping and stage statuses.',
                          style: GoogleFonts.cairo(fontSize: 12, color: _secondaryTextColor)),
                      const SizedBox(height: 14),
                      chartContent,
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                SizedBox(
                  width: 300,
                  child: selectionPanel,
                ),
              ],
            ),
          if (total > 0) ...[
            const SizedBox(height: 16),
            Divider(color: _borderColor, height: 1),
            const SizedBox(height: 12),
            Text(
              'Order distribution',
              style: GoogleFonts.cairo(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: _textColor,
              ),
            ),
            const SizedBox(height: 10),
            categoryLegend,
          ],
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
