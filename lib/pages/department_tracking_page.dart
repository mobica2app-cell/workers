// lib/pages/department_tracking_page.dart
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/track_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;
import '../main.dart';
import '../services/audit_service.dart';
import '../services/sap_service.dart';

class DepartmentTrackingPage extends StatefulWidget {
  final EmployeeAuth? loggedInEmployee;

  const DepartmentTrackingPage({
    Key? key,
    this.loggedInEmployee,
  }) : super(key: key);

  @override
  State<DepartmentTrackingPage> createState() => _DepartmentTrackingPageState();
}

class _DepartmentTrackingPageState extends State<DepartmentTrackingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final EmployeeAuthService _authService = EmployeeAuthService(Supabase.instance.client);
  final SAPMainService _sapService = SAPMainService(Supabase.instance.client);
  final AuditService _auditService = AuditService(Supabase.instance.client);

  List<EmployeeAuth> _allEmployees = [];
  List<SAPMainOrder> _allOrders = [];
  List<Map<String, dynamic>> _auditLogs = [];
  Map<String, List<EmployeeAuth>> _departmentsMap = {};
  bool _isLoading = true;
  String _dateFilter = 'all';
  DateTime? _startDate;
  DateTime? _endDate;
  List<Map<String, dynamic>> _filteredAuditLogs = [];

  // Store completed order IDs with their completion date from audit logs
  Map<String, DateTime> _completedOrderDates = {};

  // Store orders with no audit log (for "All" filter)
  Set<String> _ordersWithoutAudit = {};

  final Set<String> _contractCountEmployees = <String>{};

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F9FA);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : Colors.grey.shade200;
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _mutedColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

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
            color: Colors.white,
          ),
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  int _getEmployeeStatusCount(
      EmployeeAuth employee,
      String targetStatus,
      ) {
    int count = 0;

    for (final order in _allOrders) {
      // Employee assignment
      bool belongsToEmployee = false;

      if (order.correspondenceEngineer == employee.fullName) {
        belongsToEmployee = true;
      } else if (order.responsibleEngineer == employee.fullName) {
        belongsToEmployee = true;
      }

      if (!belongsToEmployee) continue;

      // CURRENT SAP STATUS must be exactly this status
      if (order.status.trim() != targetStatus) {
        continue;
      }

      // No date filter = count current status
      if (!_hasDateRange) {
        count++;
        continue;
      }

      // Find audit date for THIS order and THIS status
      DateTime? matchingDate;

      for (final log in _auditLogs) {
        final orderId = log['order_id']?.toString().trim() ?? '';
        final fieldName = log['field_name']?.toString().trim() ?? '';
        final newValue = log['new_value']?.toString().trim() ?? '';

        if (orderId != order.id.toString().trim()) continue;
        if (fieldName != 'status') continue;
        if (newValue != targetStatus) continue;

        final changedAt = _parseTimestamp(
          log['changed_at']?.toString() ?? '',
        );

        if (changedAt == null) continue;

        if (matchingDate == null ||
            matchingDate.isBefore(changedAt)) {
          matchingDate = changedAt;
        }
      }

      if (matchingDate == null) continue;

      final dateOnly = _dateOnly(matchingDate);

      if (_startDate != null &&
          dateOnly.isBefore(_dateOnly(_startDate!))) {
        continue;
      }

      if (_endDate != null &&
          dateOnly.isAfter(_dateOnly(_endDate!))) {
        continue;
      }

      count++;
    }

    return count;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final employees = await _authService.getAllEmployees();
      final orders = await _sapService.getAllOrders();

      // Fetch only status changes to Done/Task Done/planning from audit logs
      final supabase = Supabase.instance.client;
      final doneAuditLogs = await supabase
          .from('order_audit_log')
          .select('*')
          .eq('field_name', 'status')
          .or('new_value.eq.Done,new_value.eq.Task Done,new_value.eq.planning')
          .order('changed_at', ascending: false)
          .limit(10000);

      print('Total orders: ${orders.length}');
      print('Done audit logs: ${doneAuditLogs.length}');

      // Count locked orders in SAP
      int lockedOrders = 0;
      for (var order in orders) {
        if (order.status == 'Done' || order.status == 'Task Done' || order.status == 'planning') {
          lockedOrders++;
        }
      }
      print('Locked orders in SAP: $lockedOrders');

      final deptMap = <String, List<EmployeeAuth>>{};
      for (var emp in employees) {
        final dept = emp.department ?? 'No Department';
        deptMap.putIfAbsent(dept, () => []).add(emp);
      }

      // Build completion dates using the SAME logic as the dashboard:
      //
      // 1. The audit log says the order entered Done / Task Done / planning.
      // 2. The order must still exist in sap_main_orders.
      // 3. Its CURRENT SAP status must still equal the audit new_value.
      //
      // This prevents an order that went:
      //   Done -> Review
      // from still appearing as Done.
      final completedDates = <String, DateTime>{};

      for (var log in doneAuditLogs) {
        final orderId = log['order_id']?.toString().trim() ?? '';
        final fieldName = log['field_name']?.toString().trim() ?? '';
        final newValue = log['new_value']?.toString().trim() ?? '';

        if (fieldName != 'status' ||
            (newValue != 'Done' &&
                newValue != 'Task Done' &&
                newValue != 'planning') ||
            orderId.isEmpty ||
            orderId == 'bulk_delete' ||
            orderId == 'import_batch') {
          continue;
        }

        // Find the real SAP order. Do not construct a fake SAPMainOrder.
        SAPMainOrder? currentOrder;
        for (final order in orders) {
          if (order.id.toString().trim() == orderId) {
            currentOrder = order;
            break;
          }
        }

        if (currentOrder == null) continue;

        // EXACTLY like the dashboard/Supabase logic:
        // only keep it if the CURRENT status is still the status
        // recorded by this audit event.
        if (currentOrder.status.trim() != newValue) continue;

        final changedAt = _parseTimestamp(
          log['changed_at']?.toString() ?? '',
        );
        if (changedAt == null) continue;

        // Keep the latest matching audit date for this currently-completed order.
        if (!completedDates.containsKey(orderId) ||
            completedDates[orderId]!.isBefore(changedAt)) {
          completedDates[orderId] = changedAt;
        }
      }

      print('Orders with completed dates: ${completedDates.length}');

      setState(() {
        _allEmployees = employees;
        _allOrders = orders;
        _auditLogs = doneAuditLogs;
        _departmentsMap = deptMap;
        _completedOrderDates = completedDates;
        _isLoading = false;
      });

      _applyFilters();
    } catch (e) {
      print('Error loading departments: $e');
      setState(() => _isLoading = false);
    }
  }

  // Add this helper method
  DateTime? _parseTimestamp(String timestampStr) {
    if (timestampStr.isEmpty) return null;

    try {
      // Try parsing with milliseconds and timezone
      return DateTime.parse(timestampStr);
    } catch (e) {
      // Try without timezone
      try {
        return DateTime.parse(timestampStr.replaceAll('+00', ''));
      } catch (e2) {
        // Try with manual parsing for format: 2026-08-16 08:56:36.332+00
        try {
          final parts = timestampStr.split(' ');
          if (parts.length >= 2) {
            final datePart = parts[0];
            final timePart = parts[1].split('+')[0].split('.')[0]; // Remove milliseconds and timezone
            final dateTimeStr = '$datePart $timePart';
            return DateTime.parse(dateTimeStr);
          }
        } catch (e3) {
          print('Failed to parse timestamp: $timestampStr');
        }
      }
    }
    return null;
  }

  void _applyFilters() {
    setState(() {
      _filteredAuditLogs = _auditLogs.where((log) {
        final orderId = log['order_id']?.toString().trim() ?? '';
        final fieldName = log['field_name']?.toString().trim() ?? '';
        final newValue = log['new_value']?.toString().trim() ?? '';

        // Only Done / Task Done / planning status changes.
        if (fieldName != 'status' ||
            (newValue != 'Done' &&
                newValue != 'Task Done' &&
                newValue != 'planning')) {
          return false;
        }

        if (orderId.isEmpty ||
            orderId == 'bulk_delete' ||
            orderId == 'import_batch') {
          return false;
        }

        // Find the existing order in SAP.
        SAPMainOrder? currentOrder;
        for (final order in _allOrders) {
          if (order.id.toString().trim() == orderId) {
            currentOrder = order;
            break;
          }
        }

        // Must exist in sap_main_orders.
        if (currentOrder == null) return false;

        // IMPORTANT:
        // The audit row must match the CURRENT SAP status.
        //
        // Example:
        //   20 Aug -> Done
        //   25 Aug -> Review
        //
        // This order is NOT a Done order anymore.
        if (currentOrder.status.trim() != newValue) {
          return false;
        }

        // Inclusive custom date range based on changed_at.
        if (_startDate != null || _endDate != null) {
          final changedAt = _parseTimestamp(
            log['changed_at']?.toString() ?? '',
          );
          if (changedAt == null) return false;

          final dateOnly = DateTime(
            changedAt.year,
            changedAt.month,
            changedAt.day,
          );

          if (_startDate != null &&
              dateOnly.isBefore(_dateOnly(_startDate!))) {
            return false;
          }

          if (_endDate != null &&
              dateOnly.isAfter(_dateOnly(_endDate!))) {
            return false;
          }
        }

        // No search filter here.
        return true;
      }).toList();
    });
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
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

    if (_endDate != null && picked.isAfter(_endDate!)) {
      _showSnackBar('Start date cannot be after end date');
      return;
    }

    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);
      _dateFilter = 'custom';
    });
    _applyFilters();
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

    setState(() {
      _endDate = DateTime(picked.year, picked.month, picked.day);
      _dateFilter = 'custom';
    });
    _applyFilters();
  }

  void _clearDateRange() {
    setState(() {
      _startDate = null;
      _endDate = null;
      _dateFilter = 'all';
    });
    _applyFilters();
  }

  String _formatFilterDate(DateTime? date) {
    if (date == null) return 'Select date';
    return DateFormat('dd MMM yyyy').format(date);
  }

  bool get _hasDateRange => _startDate != null || _endDate != null;

  // Get employee's tasks with priority logic (correspondence > responsible)
  List<SAPMainOrder> _getEmployeeTasks(EmployeeAuth employee) {
    final assignedOrders = <String, SAPMainOrder>{};

    for (var order in _allOrders) {
      if (order.correspondenceEngineer == employee.fullName) {
        assignedOrders[order.id] = order;
      } else if (order.responsibleEngineer == employee.fullName) {
        if (!assignedOrders.containsKey(order.id)) {
          assignedOrders[order.id] = order;
        }
      }
    }

    return assignedOrders.values.toList();
  }

  // Get completed count for employee
  int _getEmployeeCompleted(EmployeeAuth employee) {
    int count = 0;

    for (var order in _allOrders) {
      bool belongsToEmployee = false;

      if (order.correspondenceEngineer == employee.fullName) {
        belongsToEmployee = true;
      } else if (order.responsibleEngineer == employee.fullName) {
        belongsToEmployee = true;
      }

      if (!belongsToEmployee) continue;

      if (order.status != 'Done' &&
          order.status != 'Task Done' &&
          order.status != 'planning') {
        continue;
      }

      if (!_hasDateRange) {
        count++;
        continue;
      }

      final completionDate = _completedOrderDates[order.id];
      if (completionDate == null) continue;

      final dateOnly = _dateOnly(completionDate);

      if (_startDate != null &&
          dateOnly.isBefore(_dateOnly(_startDate!))) {
        continue;
      }

      if (_endDate != null &&
          dateOnly.isAfter(_dateOnly(_endDate!))) {
        continue;
      }

      count++;
    }

    return count;
  }

  Color _getDepartmentColor(String department) {
    switch (department) {
      case 'Technical Office': return Colors.blue;
      case 'Projects Design': return Colors.purple;
      case 'Sofa Section': return Colors.orange;
      case 'Product Section': return Colors.teal;
      case 'Partation Section': return Colors.indigo;
      case 'Cladding Section': return Colors.brown;
      case 'Solid Work Section': return Colors.pink;
      case 'Data Entry': return Colors.cyan;
      case 'Management': return Colors.deepOrange;
      default: return _isDark ? Colors.grey.shade400 : Colors.grey;
    }
  }

  IconData _getDepartmentIcon(String department) {
    switch (department) {
      case 'Technical Office': return Icons.engineering;
      case 'Projects Design': return Icons.design_services;
      case 'Sofa Section': return Icons.chair;
      case 'Product Section': return Icons.inventory_2;
      case 'Partation Section': return Icons.grid_view;
      case 'Cladding Section': return Icons.layers;
      case 'Solid Work Section': return Icons.architecture;
      case 'Data Entry': return Icons.keyboard;
      case 'Management': return Icons.business;
      default: return Icons.business;
    }
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  bool _samePerson(String? a, String? b) {
    if (a == null || b == null) return false;

    final first = _normalize(a);
    final second = _normalize(b);

    return first.isNotEmpty && first == second;
  }

  void _openOrderTracking(SAPMainOrder order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OrderTrackingPage(order: order),
      ),
    ).then((_) {
      if (mounted) _loadData();
    });
  }

  Widget _buildAssignmentLine({
    required String label,
    required String? name,
    required IconData icon,
    required Color color,
  }) {
    final value = name?.trim() ?? '';
    if (value.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(
            '$label: ',
            style: GoogleFonts.cairo(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: _secondaryTextColor,
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: _textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkloadOrderCard(
      SAPMainOrder order,
      String stage, {
        bool showAssignmentEditors = false,
        void Function(SAPMainOrder updatedOrder)? onOrderUpdated,
      }) {
    final actualStage = _currentStageForStatus(order.status) ?? stage;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openOrderTracking(order),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _mutedColor,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _borderColor),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 720;

              final orderInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.contractNumber.isNotEmpty
                              ? order.contractNumber
                              : 'no contract number',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _textColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.open_in_new,
                        size: 13,
                        color: _secondaryTextColor,
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${order.itemNumber} | ${order.customerName}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      color: _secondaryTextColor,
                    ),
                  ),
                  _buildAssignmentLine(
                    label: 'Engineer',
                    name: order.responsibleEngineer,
                    icon: Icons.engineering,
                    color: Colors.orange,
                  ),
                  _buildAssignmentLine(
                    label: 'Reviewer',
                    name: order.reviewer,
                    icon: Icons.rate_review,
                    color: Colors.purple,
                  ),
                  _buildAssignmentLine(
                    label: 'Alternative',
                    name: order.correspondenceEngineer,
                    icon: Icons.alt_route,
                    color: Colors.teal,
                  ),
                  if (showAssignmentEditors) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _buildTrackingEmployeeDropdown(
                            label: 'Responsible Engineer',
                            currentValue: order.responsibleEngineer,
                            field: 'responsible_engineer',
                            order: order,
                            onUpdated: onOrderUpdated,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildTrackingEmployeeDropdown(
                            label: 'Reviewer',
                            currentValue: order.reviewer,
                            field: 'reviewer',
                            order: order,
                            onUpdated: onOrderUpdated,
                          ),
                        ),
                      ],
                    ),
                  ],

                ],
              );

              final stageInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Current Workload Stage',
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 5),
                  _buildStatusBadge(actualStage),
                  const SizedBox(height: 8),
                  Text(
                    'Status: ${order.status}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                ],
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    orderInfo,
                    const SizedBox(height: 10),
                    stageInfo,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: orderInfo),
                  const SizedBox(width: 18),
                  Expanded(flex: 2, child: stageInfo),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _showWorkloadStageOrders(
      String employeeName,
      String stage,
      List<SAPMainOrder> orders,
      ) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: _cardColor,
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 1100,
              maxHeight: 700,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bar_chart,
                        color: _secondaryTextColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '$employeeName — All Workload Statuses',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _textColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${orders.length} orders',
                          style: GoogleFonts.cairo(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        icon: Icon(
                          Icons.close,
                          color: _secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: _borderColor),
                  const SizedBox(height: 8),
                  Expanded(
                    child: orders.isEmpty
                        ? Center(
                      child: Text(
                        'No workload orders found',
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          color: _secondaryTextColor,
                        ),
                      ),
                    )
                        : ListView.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        return _buildWorkloadOrderCard(
                          orders[index],
                          stage,
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  int _progressForOrder(SAPMainOrder order) {
    switch (_normalize(order.status)) {
      case 'done':
      case 'task done':
      case 'planning':
      case 'completed':
        return 100;

      case 'master data':
        return 90;

      case 'manufacturing drawing':
        return 80;

      case 'modifications submitted':
      case 'modification submitted':
      case 'modification':
        return 60;

      case 'approval':
        return 40;

      case 'drawing submittal':
      case 'drawing submission':
      case 'drawing submitted':
        return 20;

      default:
        return 0;
    }
  }

  int _averageProgress(List<SAPMainOrder> orders) {
    if (orders.isEmpty) return 0;

    final total = orders.fold<int>(
      0,
          (sum, order) => sum + _progressForOrder(order),
    );

    return (total / orders.length).round();
  }

  Color _statusColor(String status) {
    switch (_normalize(status)) {
      case 'done':
      case 'task done':
      case 'planning':
      case 'completed':
        return Colors.green;
      case 'master data':
        return Colors.teal;
      case 'manufacturing drawing':
      case 'manufacturing':
        return Colors.deepPurple;
      case 'modifications submitted':
      case 'modification submitted':
      case 'modification':
        return Colors.orange;
      case 'approval':
        return Colors.blue;
      case 'drawing submittal':
      case 'drawing submission':
      case 'drawing submitted':
        return Colors.indigo;
      default:
        return _secondaryTextColor;
    }
  }

  Widget _buildStatusBadge(String status) {
    final color = _statusColor(status);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.isEmpty ? 'Unknown' : status,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.cairo(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  String? _currentStageForStatus(String status) {
    final value = _normalize(status);

    if (value == 'drawing submittal' ||
        value == 'drawing submission' ||
        value == 'drawing submitted') {
      return 'Drawing Submittal';
    }
    if (value == 'task' || value == 'tasks' || value == 'task done') {
      return 'Task';
    }
    if (value == 'modification' ||
        value == 'modifications' ||
        value == 'modification submitted' ||
        value == 'modifications submitted') {
      return 'Modification';
    }
    if (value == 'manufacturing drawing' ||
        value == 'manufacturing' ||
        value == 'manifactury') {
      return 'Manufacturing';
    }
    if (value == 'review') {
      return 'Review';
    }
    // _normalize collapses repeated spaces, so compare using the normalized
    // form while keeping the exact graph label requested by the user.
    if (value == 'partation master data') {
      return 'partation  master data';
    }
    return null;
  }

  Map<String, int> _unassignedWorkloadCounts() {
    var header = 0;
    var noOne = 0;
    var notAssigned = 0;

    for (final order in _allOrders) {
      if (_currentStageForStatus(order.status) == null) continue;

      // Use the same ownership priority as the workload graph.
      final alternative = order.correspondenceEngineer?.trim() ?? '';
      final responsible = order.responsibleEngineer?.trim() ?? '';
      final owner = alternative.isNotEmpty ? alternative : responsible;
      final normalizedOwner = _normalize(owner);

      if (normalizedOwner == 'header') {
        header++;
      } else if (normalizedOwner == 'no one') {
        noOne++;
      } else if (normalizedOwner.isEmpty) {
        notAssigned++;
      }
    }

    return {
      'Header': header,
      'No One': noOne,
      'Not Assigned Yet': notAssigned,
    };
  }

  Map<String, Map<String, int>> _currentWorkloadByEmployee() {
    final result = <String, Map<String, int>>{};

    Map<String, int> stagesFor(String employee) {
      return result.putIfAbsent(
        _normalize(employee),
            () => <String, int>{
          'Drawing Submittal': 0,
          'Task': 0,
          'Modification': 0,
          'Manufacturing': 0,
          'Review': 0,
          'partation  master data': 0,
        },
      );
    }

    for (final order in _allOrders) {
      final stage = _currentStageForStatus(order.status);
      if (stage == null) continue;

      // Alternative Engineer owns the workload whenever the row has one.
      // Otherwise the Responsible Engineer owns it.
      final alternative = order.correspondenceEngineer?.trim() ?? '';
      final responsible = order.responsibleEngineer?.trim() ?? '';
      final owner = alternative.isNotEmpty ? alternative : responsible;
      final normalizedOwner = _normalize(owner);

      // Header, No One, and unassigned work are shown as counts above the
      // graph, not as employee bars.
      if (normalizedOwner.isEmpty ||
          normalizedOwner == 'header' ||
          normalizedOwner == 'no one') {
        continue;
      }

      final stages = stagesFor(owner);
      stages[stage] = (stages[stage] ?? 0) + 1;
    }

    return result;
  }

  List<SAPMainOrder> _allOrdersForEmployeeStage(
      String employeeName,
      String stage,
      ) {
    // Build the popup from the exact same full _allOrders collection used by the
    // workload graph. Do NOT deduplicate by order id here: every row in
    // sap_main_allOrders is an order/item row and must be displayed.
    final result = <SAPMainOrder>[];

    for (final order in _allOrders) {
      final currentStage = _currentStageForStatus(order.status);
      if (currentStage == null) continue;

      final alternative = order.correspondenceEngineer?.trim() ?? '';
      final responsible = order.responsibleEngineer?.trim() ?? '';
      final owner = alternative.isNotEmpty ? alternative : responsible;

      if (!_samePerson(owner, employeeName)) continue;

      result.add(order);
    }

    result.sort((a, b) {
      final contractCompare =
      a.contractNumber.toString().compareTo(b.contractNumber.toString());
      if (contractCompare != 0) return contractCompare;
      final itemCompare =
      a.itemNumber.toString().compareTo(b.itemNumber.toString());
      if (itemCompare != 0) return itemCompare;
      return a.id.compareTo(b.id);
    });

    return result;
  }

  List<SAPMainOrder> _allOrdersForSpecialWorkload(String special) {
    final result = <SAPMainOrder>[];

    for (final order in _allOrders) {
      if (_currentStageForStatus(order.status) == null) continue;

      final alternative = order.correspondenceEngineer?.trim() ?? '';
      final responsible = order.responsibleEngineer?.trim() ?? '';
      final owner = alternative.isNotEmpty ? alternative : responsible;
      final normalizedOwner = _normalize(owner);

      final matches = switch (special) {
        'Header' => normalizedOwner == 'header',
        'No One' => normalizedOwner == 'no one',
        'Not Assigned Yet' => normalizedOwner.isEmpty,
        _ => false,
      };

      if (matches) result.add(order);
    }

    result.sort((a, b) {
      final contractCompare =
      a.contractNumber.toString().compareTo(b.contractNumber.toString());
      if (contractCompare != 0) return contractCompare;
      final itemCompare =
      a.itemNumber.toString().compareTo(b.itemNumber.toString());
      if (itemCompare != 0) return itemCompare;
      return a.id.compareTo(b.id);
    });

    return result;
  }

  void _showSpecialWorkloadOrders(String special) {
    final orders = _allOrdersForSpecialWorkload(special);
    if (orders.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return Dialog(
              backgroundColor: _cardColor,
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100, maxHeight: 700),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.bar_chart, color: _secondaryTextColor, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$special — All Workload Statuses',
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: _textColor,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Text(
                              '${orders.length} orders',
                              style: GoogleFonts.cairo(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            icon: Icon(Icons.close, color: _secondaryTextColor),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(color: _borderColor),
                      const SizedBox(height: 8),
                      Expanded(
                        child: ListView.builder(
                          itemCount: orders.length,
                          itemBuilder: (context, index) {
                            final order = orders[index];
                            final stage =
                                _currentStageForStatus(order.status) ?? 'Unknown';
                            return _buildWorkloadOrderCard(
                              order,
                              stage,
                              showAssignmentEditors: special == 'Not Assigned Yet',
                              onOrderUpdated: special == 'Not Assigned Yet'
                                  ? (updatedOrder) {
                                orders[index] = updatedOrder;
                                setDialogState(() {});
                              }
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWorkloadCountBadge(
      String title,
      int count,
      Color color,
      ) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: count > 0 ? () => _showSpecialWorkloadOrders(title) : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Text(
            '$title: $count',
            style: GoogleFonts.cairo(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ),
    );
  }

  String _contractKey(SAPMainOrder order) {
    final contract = order.contractNumber.toString().trim();
    // If a row has no contract number, keep it distinct instead of grouping
    // every empty value into one contract.
    return contract.isEmpty
        ? '__order__${order.id.trim()}'
        : _normalize(contract);
  }

  Map<String, int> _contractWorkloadByStage(String employeeName) {
    final stageContracts = <String, Set<String>>{
      'Drawing Submittal': <String>{},
      'Task': <String>{},
      'Modification': <String>{},
      'Manufacturing': <String>{},
      'Review': <String>{},
      'partation  master data': <String>{},
    };

    for (final order in _allOrders) {
      final stage = _currentStageForStatus(order.status);
      if (stage == null) continue;

      final alternative = order.correspondenceEngineer?.trim() ?? '';
      final responsible = order.responsibleEngineer?.trim() ?? '';
      final owner = alternative.isNotEmpty ? alternative : responsible;

      if (!_samePerson(owner, employeeName)) continue;

      stageContracts[stage]!.add(_contractKey(order));
    }

    return {
      for (final entry in stageContracts.entries)
        entry.key: entry.value.length,
    };
  }

  int _contractCountForEmployee(String employeeName) {
    final contracts = <String>{};

    for (final order in _allOrders) {
      if (_currentStageForStatus(order.status) == null) continue;

      final alternative = order.correspondenceEngineer?.trim() ?? '';
      final responsible = order.responsibleEngineer?.trim() ?? '';
      final owner = alternative.isNotEmpty ? alternative : responsible;

      if (_samePerson(owner, employeeName)) {
        contracts.add(_contractKey(order));
      }
    }

    return contracts.length;
  }

  Map<String, int> _displayedWorkloadStages(
      String employeeName,
      Map<String, int> orderStages,
      ) {
    if (!_contractCountEmployees.contains(_normalize(employeeName))) {
      return orderStages;
    }

    return _contractWorkloadByStage(employeeName);
  }

  Widget _buildCurrentWorkloadGraph(bool compact) {

    final workload = _currentWorkloadByEmployee();
    final unassignedCounts = _unassignedWorkloadCounts();
    if (workload.isEmpty && unassignedCounts.values.every((count) => count == 0)) {
      return const SizedBox.shrink();
    }

    final stageOrder = const [
      'Drawing Submittal',
      'Task',
      'Modification',
      'Manufacturing',
      'Review',
      'partation  master data',
    ];

    final stageColors = <String, Color>{
      'Drawing Submittal': Colors.blue,
      'Task': Colors.indigo,
      'Modification': Colors.orange,
      'Manufacturing': Colors.deepPurple,
      'Review': Colors.teal,
      'partation  master data': Colors.brown,
    };

    final employeeEntries = workload.entries.toList()
      ..sort((a, b) {
        final aTotal =
        a.value.values.fold<int>(0, (sum, value) => sum + value);
        final bTotal =
        b.value.values.fold<int>(0, (sum, value) => sum + value);
        final byTotal = bTotal.compareTo(aTotal);
        if (byTotal != 0) return byTotal;
        return a.key.compareTo(b.key);
      });

    final maxTotal = employeeEntries
        .map((entry) {
      final displayed = _displayedWorkloadStages(
        entry.key,
        entry.value,
      );
      return displayed.values.fold<int>(
        0,
            (sum, value) => sum + value,
      );
    })
        .fold<int>(0, (a, b) => a > b ? a : b);

    // Keep the graph compact even when there are many employees.
    final chartHeight =
    (employeeEntries.length * (compact ? 34.0 : 40.0) + 35.0)
        .clamp(180.0, 480.0);

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compactHeader = constraints.maxWidth < 760;

              final specialCountWidgets = <Widget>[
                _buildWorkloadCountBadge(
                  'Header',
                  unassignedCounts['Header'] ?? 0,
                  Colors.deepPurple,
                ),
                _buildWorkloadCountBadge(
                  'No One',
                  unassignedCounts['No One'] ?? 0,
                  Colors.grey,
                ),
                _buildWorkloadCountBadge(
                  'Not Assigned Yet',
                  unassignedCounts['Not Assigned Yet'] ?? 0,
                  Colors.orange,
                ),
              ];

              final title = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.bar_chart, size: 19, color: _textColor),
                  const SizedBox(width: 8),
                  Text(
                    'Current Workload by Employee',
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: compact ? 14 : 16,
                      fontWeight: FontWeight.w700,
                      color: _textColor,
                    ),
                  ),
                ],
              );

              if (compactHeader) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 5,
                        children: specialCountWidgets,
                      ),
                    ),
                  ],
                );
              }

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Align(
                      alignment: Alignment.topRight,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 6,
                        runSpacing: 5,
                        children: specialCountWidgets,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Each bar normally counts order rows. Use the checkbox on top of a bar to count unique contract numbers for that employee. Clicking a bar still opens all matching order rows.',
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: _secondaryTextColor,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: stageOrder.map((stage) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: stageColors[stage],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    stage,
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
          const SizedBox(height: 50),
          SizedBox(
            height: chartHeight,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final plotHeight = math.max(0.0, chartHeight - (compact ? 92.0 : 100.0));
                final plotWidth = math.max(0.0, constraints.maxWidth - 32.0);
                final maxYValue = (maxTotal + 1).toDouble();

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    BarChart(
                      BarChartData(
                        minY: 0,
                        maxY: (maxTotal + 1).toDouble(),
                        alignment: BarChartAlignment.spaceAround,
                        groupsSpace: compact ? 4 : 8,
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 2,
                        ),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(
                          enabled: true,

                          // Hover shows the complete workload breakdown.
                          // Hover never opens the orders dialog.
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipItem: (group, groupIndex, rod, rodIndex) {
                              if (groupIndex < 0 ||
                                  groupIndex >= employeeEntries.length) {
                                return null;
                              }

                              final employee = employeeEntries[groupIndex];
                              final orderStages = employee.value;
                              final stages = _displayedWorkloadStages(
                                employee.key,
                                orderStages,
                              );

                              final drawing = stages['Drawing Submittal'] ?? 0;
                              final task = stages['Task'] ?? 0;
                              final modification = stages['Modification'] ?? 0;
                              final manufacturing = stages['Manufacturing'] ?? 0;
                              final review = stages['Review'] ?? 0;
                              final partationMasterData =
                                  stages['partation  master data'] ?? 0;
                              final displayedTotal =
                                  drawing +
                                      task +
                                      modification +
                                      manufacturing +
                                      review +
                                      partationMasterData;
                              final totalOrders = orderStages.values.fold<int>(
                                0,
                                    (sum, value) => sum + value,
                              );
                              final totalContracts =
                              _contractCountForEmployee(employee.key);
                              final contractMode = _contractCountEmployees.contains(
                                _normalize(employee.key),
                              );

                              return BarTooltipItem(
                                '${employee.key}\n'
                                    'Drawing Submittal: $drawing\n'
                                    'Task: $task\n'
                                    'Modification: $modification\n'
                                    'Manufacturing: $manufacturing\n'
                                    'Review: $review\n'
                                    'partation  master data: $partationMasterData\n'
                                    '${contractMode ? 'Displayed: $displayedTotal contracts\n' : ''}'
                                    'Total Orders: $totalOrders\n'
                                    'Total Contracts: $totalContracts',
                                GoogleFonts.cairo(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1.4,
                                ),
                              );
                            },
                          ),

                          // Only an actual click/tap opens the orders.
                          touchCallback: (event, response) {
                            if (event is! FlTapUpEvent ||
                                response?.spot == null) {
                              return;
                            }

                            final spot = response!.spot!;
                            final groupIndex = spot.touchedBarGroupIndex;
                            final stackIndex = spot.touchedStackItemIndex;

                            if (groupIndex < 0 ||
                                groupIndex >= employeeEntries.length ||
                                stackIndex < 0 ||
                                stackIndex >= stageOrder.length) {
                              return;
                            }

                            final employee = employeeEntries[groupIndex];
                            final stage = stageOrder[stackIndex];
                            final displayedStages = _displayedWorkloadStages(
                              employee.key,
                              employee.value,
                            );
                            final count = displayedStages[stage] ?? 0;

                            if (count <= 0) return;

                            final orders = _allOrdersForEmployeeStage(
                              employee.key,
                              stage,
                            );

                            _showWorkloadStageOrders(
                              employee.key,
                              stage,
                              orders,
                            );
                          },
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
                              reservedSize: 32,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final number = value.toInt();

                                // Show 0, 1, 2, 4, 6, 8... instead of every number.
                                if (number > 2 && number.isOdd) {
                                  return const SizedBox.shrink();
                                }

                                return Text(
                                  number.toString(),
                                  style: GoogleFonts.cairo(
                                    fontSize: 8,
                                    color: _secondaryTextColor,
                                  ),
                                );
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: compact ? 92 : 100,
                              getTitlesWidget: (value, meta) {
                                final index = value.toInt();
                                if (index < 0 || index >= employeeEntries.length) {
                                  return const SizedBox.shrink();
                                }

                                final employeeName = employeeEntries[index].key;
                                final normalizedName = _normalize(employeeName);
                                return SideTitleWidget(
                                  meta: meta,
                                  space: 8,
                                  angle: -math.pi / 7,
                                  child: SizedBox(
                                    width: compact ? 90 : 120,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          employeeName,
                                          textAlign: TextAlign.center,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: GoogleFonts.cairo(
                                            fontSize: compact ? 11 : 12,
                                            fontWeight: FontWeight.w600,
                                            color: _textColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        barGroups: employeeEntries.asMap().entries.map((entry) {
                          final index = entry.key;
                          final employeeName = entry.value.key;
                          final stages = _displayedWorkloadStages(
                            employeeName,
                            entry.value.value,
                          );

                          final drawing = stages['Drawing Submittal'] ?? 0;
                          final task = stages['Task'] ?? 0;
                          final modification = stages['Modification'] ?? 0;
                          final manufacturing = stages['Manufacturing'] ?? 0;
                          final review = stages['Review'] ?? 0;
                          final partationMasterData =
                              stages['partation  master data'] ?? 0;
                          final displayedTotal =
                              drawing +
                                  task +
                                  modification +
                                  manufacturing +
                                  review +
                                  partationMasterData;

                          return BarChartGroupData(
                            x: index,
                            barRods: [
                              BarChartRodData(
                                toY: displayedTotal.toDouble(),
                                width: compact ? 22 : 28,
                                borderRadius: BorderRadius.circular(5),
                                rodStackItems: [
                                  BarChartRodStackItem(
                                    0,
                                    drawing.toDouble(),
                                    stageColors['Drawing Submittal']!,
                                  ),
                                  BarChartRodStackItem(
                                    drawing.toDouble(),
                                    (drawing + task).toDouble(),
                                    stageColors['Task']!,
                                  ),
                                  BarChartRodStackItem(
                                    (drawing + task).toDouble(),
                                    (drawing + task + modification).toDouble(),
                                    stageColors['Modification']!,
                                  ),
                                  BarChartRodStackItem(
                                    (drawing + task + modification).toDouble(),
                                    (drawing + task + modification + manufacturing).toDouble(),
                                    stageColors['Manufacturing']!,
                                  ),
                                  BarChartRodStackItem(
                                    (drawing + task + modification + manufacturing).toDouble(),
                                    (drawing + task + modification + manufacturing + review).toDouble(),
                                    stageColors['Review']!,
                                  ),
                                  BarChartRodStackItem(
                                    (drawing + task + modification + manufacturing + review).toDouble(),
                                    displayedTotal.toDouble(),
                                    stageColors['partation  master data']!,
                                  ),
                                ],
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                    ...employeeEntries.asMap().entries.map((entry) {
                      final index = entry.key;
                      final employeeName = entry.value.key;
                      final normalizedName = _normalize(employeeName);
                      final checked = _contractCountEmployees.contains(normalizedName);
                      final stages = _displayedWorkloadStages(
                        employeeName,
                        entry.value.value,
                      );
                      final total = stages.values.fold<int>(0, (sum, value) => sum + value);

                      final centerX = 32.0 + ((index + 0.5) / employeeEntries.length) * plotWidth;
                      final barTop = plotHeight * (1 - (total / maxYValue));

                      return Positioned(
                        left: (centerX - 15).clamp(0.0, math.max(0.0, constraints.maxWidth - 28.0)),
                        top: (barTop - 25).clamp(0.0, math.max(0.0, plotHeight - 28.0)),
                        child: Material(
                          color: Colors.transparent,
                          child: Transform.scale(
                            scale: compact ? 0.72 : 0.78,
                            child: Checkbox(
                              value: checked,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _contractCountEmployees.add(normalizedName);
                                  } else {
                                    _contractCountEmployees.remove(normalizedName);
                                  }
                                });
                              },
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
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
      appBar: AppBar(
        title: Text(
          'Departments',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Graph is intentionally the first section of the page.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: LayoutBuilder(
                builder: (context, constraints) =>
                    _buildCurrentWorkloadGraph(
                      constraints.maxWidth < 700,
                    ),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  Row(
                    children: [
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
                        const SizedBox(width: 6),
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
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _hasDateRange
                          ? '${_filteredAuditLogs.length} status changes from ${_formatFilterDate(_startDate)} to ${_formatFilterDate(_endDate)}'
                          : '${_filteredAuditLogs.length} status changes • All Time',
                      style: GoogleFonts.cairo(
                        fontSize: 11,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  for (final entry in _departmentsMap.entries)
                    _buildDepartmentCard(
                      entry.key,
                      entry.value,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingEmployeeDropdown({
    required String label,
    required String? currentValue,
    required String field,
    required SAPMainOrder order,
    void Function(SAPMainOrder updatedOrder)? onUpdated,
  }) {
    final hasValue = currentValue != null && currentValue.trim().isNotEmpty;
    final displayValue = hasValue ? currentValue!.trim() : 'Not assigned';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cairo(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: _secondaryTextColor,
          ),
        ),
        const SizedBox(height: 3),
        PopupMenuButton<String>(
          onSelected: (selectedValue) async {
            final valueToSave =
            selectedValue.trim().isEmpty ? null : selectedValue.trim();

            await _updateTrackingAssignment(
              order: order,
              field: field,
              newValue: valueToSave,
              onUpdated: onUpdated,
            );
          },
          offset: const Offset(0, 38),
          position: PopupMenuPosition.under,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
            decoration: BoxDecoration(
              color: hasValue
                  ? const Color(0xFF6366F1).withOpacity(0.05)
                  : _mutedColor,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: hasValue
                    ? const Color(0xFF6366F1).withOpacity(0.2)
                    : _borderColor,
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    displayValue,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: hasValue ? _textColor : _secondaryTextColor,
                    ),
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 15,
                  color: hasValue
                      ? const Color(0xFF6366F1)
                      : _secondaryTextColor,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => [
            const PopupMenuItem<String>(
              value: '',
              child: Text('Clear'),
            ),
            ..._allEmployees.map((employee) {
              final isSelected = _samePerson(currentValue, employee.fullName);

              return PopupMenuItem<String>(
                value: employee.fullName,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.blue.withOpacity(0.15),
                      child: Text(
                        employee.initials,
                        style: GoogleFonts.cairo(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            employee.fullName,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.cairo(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : _textColor,
                            ),
                          ),
                          if (employee.role != null)
                            Text(
                              employee.role!,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.cairo(
                                fontSize: 9,
                                color: _secondaryTextColor,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  Future<void> _updateTrackingAssignment({
    required SAPMainOrder order,
    required String field,
    required String? newValue,
    void Function(SAPMainOrder updatedOrder)? onUpdated,
  }) async {
    final oldValue = field == 'responsible_engineer'
        ? order.responsibleEngineer
        : order.reviewer;

    final oldText = oldValue?.trim() ?? '';
    final newText = newValue?.trim() ?? '';
    if (oldText == newText) return;

    // The login page stores the actual employee name in browser localStorage.
    // Use that name for audit records so the audit shows who is using the
    // browser, instead of the Supabase auth email or a generic page name.
    String? browserEmployeeName;
    try {
      browserEmployeeName =
      html.window.localStorage['remembered_username'];
    } catch (_) {
      browserEmployeeName = null;
    }

    final loggedInEmployee = widget.loggedInEmployee;
    final changedBy =
    browserEmployeeName?.isNotEmpty == true
        ? browserEmployeeName!
        : loggedInEmployee?.fullName.trim().isNotEmpty == true
        ? loggedInEmployee!.fullName.trim()
        : (_supabase.auth.currentUser?.email ?? 'Department Tracking');

    final changedById = loggedInEmployee?.id.trim().isNotEmpty == true
        ? loggedInEmployee!.id.trim()
        : _supabase.auth.currentUser?.id;

    try {
      await _supabase
          .from('sap_main_orders')
          .update({field: newValue})
          .eq('id', order.id);

      await _auditService.logChange(
        orderId: order.id,
        designOrder: order.designOrder,
        fieldName: field,
        oldValue: oldText.isEmpty ? null : oldText,
        newValue: newText.isEmpty ? null : newText,
        changedBy: changedBy,
        changedById: changedById,
      );

      final updatedOrder = SAPMainOrder(
        id: order.id,
        status: order.status,
        customerName: order.customerName,
        itemNumber: order.itemNumber,
        productCode: order.productCode,
        contractNumber: order.contractNumber,
        description: order.description,
        designOrder: order.designOrder,
        quantity: order.quantity,
        unitOfMeasure: order.unitOfMeasure,
        value: order.value,
        salesEngineer: order.salesEngineer,
        orderDate: order.orderDate,
        endDate: order.endDate,
        deliveryDate: order.deliveryDate,
        factory: order.factory,
        designTeam: order.designTeam,
        responsibleEngineer: field == 'responsible_engineer'
            ? newValue
            : order.responsibleEngineer,
        reviewer: field == 'reviewer' ? newValue : order.reviewer,
        correspondenceEngineer: order.correspondenceEngineer,
        createdAt: order.createdAt,
      );

      final index = _allOrders.indexWhere((item) => item.id == order.id);
      if (index != -1) {
        _allOrders[index] = updatedOrder;
      }

      if (mounted) {
        setState(() {});
      }
      onUpdated?.call(updatedOrder);

      if (mounted) {
        _showSnackBar(
          '${field == 'responsible_engineer' ? 'Responsible Engineer' : 'Reviewer'} updated successfully',
        );
      }
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error updating assignment: $e');
    }
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
          color: _cardColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: date != null ? const Color(0xFF6366F1) : _borderColor,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 19,
              color: date != null
                  ? const Color(0xFF6366F1)
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
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    _formatFilterDate(date),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: date != null ? _textColor : _secondaryTextColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: _secondaryTextColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentCard(String department, List<EmployeeAuth> employees) {
    final color = _getDepartmentColor(department);
    final totalWorkload = employees.fold(0, (sum, emp) => sum + _getEmployeeTasks(emp).length);
    final totalCompleted = employees.fold(0, (sum, emp) => sum + _getEmployeeCompleted(emp));

    return Card(
      color: _cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withOpacity(0.3)),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
          child: Icon(_getDepartmentIcon(department), color: color, size: 24),
        ),
        title: Text(department, style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w600, color: _textColor)),
        subtitle: Row(children: [
          _buildBadge('${employees.length} Employees', color),
          const SizedBox(width: 8),
          _buildBadge('$totalWorkload Tasks', Colors.blue),
          const SizedBox(width: 8),
          _buildBadge('$totalCompleted Done', Colors.green),
        ]),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: _borderColor),
          const SizedBox(height: 8),
          ...employees.map((emp) => _buildEmployeeTile(emp, color)),
        ],
      ),
    );
  }

  Widget _buildEmployeeTile(EmployeeAuth employee, Color deptColor) {
    final tasks = _getEmployeeTasks(employee);
    final doneCount = _getEmployeeStatusCount(employee, 'Done');
    final taskDoneCount = _getEmployeeStatusCount(employee, 'Task Done');
    final planningCount = _getEmployeeStatusCount(employee, 'planning');
    final masterDataCount = _getEmployeeStatusCount(employee, 'Master Data');

    final completed = doneCount + taskDoneCount + planningCount;
    final progress = tasks.isNotEmpty ? (completed / tasks.length * 100).round() : 0;

    return GestureDetector(
      onTap: () => _showEmployeeTasks(employee, deptColor),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _isDark ? const Color(0xFF0F172A) : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _borderColor),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: deptColor.withOpacity(0.2),
              child: Text(employee.initials, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: deptColor)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(employee.fullName, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: _textColor)),
                    if (employee.role != null) ...[
                      const SizedBox(width: 8),
                      _buildBadge(employee.role!, Colors.purple),
                    ],
                  ]),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress / 100,
                      backgroundColor: _isDark ? Colors.grey.withOpacity(0.2) : Colors.grey.withOpacity(0.1),
                      valueColor: AlwaysStoppedAnimation<Color>(deptColor),
                      minHeight: 6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${tasks.length} tasks', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: _textColor)),
                Text(
                  'Done: $doneCount',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Colors.green,
                  ),
                ),

                Text(
                  'Task Done: $taskDoneCount',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Colors.blue,
                  ),
                ),

                Text(
                  'Planning: $planningCount',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Colors.orange,
                  ),
                ),
                Text(
                  'Master Data: $masterDataCount',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: Colors.teal,
                  ),
                ),
                Icon(Icons.chevron_right, size: 16, color: _secondaryTextColor),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Show employee tasks as cards
  void _showEmployeeTasks(EmployeeAuth employee, Color deptColor) {
    final allTasks = _getEmployeeTasks(employee);
    final completedTasks = <SAPMainOrder>[];

    for (var task in allTasks) {
      if (task.status != 'Done' &&
          task.status != 'Task Done' &&
          task.status != 'planning') {
        continue;
      }

      if (!_hasDateRange) {
        completedTasks.add(task);
        continue;
      }

      final completionDate = _completedOrderDates[task.id];
      if (completionDate == null) continue;

      final dateOnly = _dateOnly(completionDate);

      if (_startDate != null &&
          dateOnly.isBefore(_dateOnly(_startDate!))) {
        continue;
      }

      if (_endDate != null &&
          dateOnly.isAfter(_dateOnly(_endDate!))) {
        continue;
      }

      completedTasks.add(task);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: _backgroundColor,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: deptColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: deptColor.withOpacity(0.2),
                    child: Text(
                      employee.initials,
                      style: GoogleFonts.cairo(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: deptColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          employee.fullName,
                          style: GoogleFonts.cairo(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: _textColor,
                          ),
                        ),
                        Text(
                          employee.role ?? 'Employee',
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            color: _secondaryTextColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: _secondaryTextColor),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: Colors.green.withOpacity(0.05),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Completed orders ${_getDateFilterLabel()}',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.green,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${completedTasks.length} orders',
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: completedTasks.isEmpty
                  ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.check_circle_outline,
                      size: 60,
                      color: _secondaryTextColor,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No completed orders in this period',
                      style: GoogleFonts.cairo(
                        color: _secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                itemCount: completedTasks.length,
                itemBuilder: (context, index) {
                  final task = completedTasks[index];
                  return _buildCompletedTaskCard(
                    task,
                    deptColor,
                    employee,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper to get date filter label
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

  // Completed task card - opens OrderTrackingPage on tap
  Widget _buildCompletedTaskCard(SAPMainOrder task, Color deptColor, EmployeeAuth employee) {
    return Card(
      color: _cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: Colors.green.withOpacity(0.3)),
      ),
      child: InkWell(
        onTap: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => OrderTrackingPage(order: task),
            ),
          );
        },
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      task.description.isNotEmpty ? task.description : 'No description',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: _textColor),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Done',
                      style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.green),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _buildTaskInfo(Icons.receipt, task.designOrder),
                  const SizedBox(width: 12),
                  _buildTaskInfo(Icons.description, task.contractNumber),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildTaskInfo(Icons.inventory_2, 'QTY: ${task.quantity} ${task.unitOfMeasure}'),
                  const SizedBox(width: 12),
                  _buildTaskInfo(Icons.attach_money, '\$${_formatNumber(task.value)}'),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _buildTaskInfo(Icons.factory, task.factory ?? 'N/A'),
                  const SizedBox(width: 12),
                  _buildTaskInfo(Icons.person, task.customerName),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 16, color: _secondaryTextColor),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTaskInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: _secondaryTextColor),
        const SizedBox(width: 4),
        Text(
          text,
          style: GoogleFonts.cairo(fontSize: 11, color: _secondaryTextColor),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
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

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: GoogleFonts.cairo(fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

