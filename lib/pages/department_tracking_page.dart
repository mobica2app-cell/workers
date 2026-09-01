// lib/pages/department_tracking_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/track_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/audit_service.dart';
import '../services/sap_service.dart';

class DepartmentTrackingPage extends StatefulWidget {
  const DepartmentTrackingPage({Key? key}) : super(key: key);

  @override
  State<DepartmentTrackingPage> createState() => _DepartmentTrackingPageState();
}

class _DepartmentTrackingPageState extends State<DepartmentTrackingPage> {
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

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F9FA);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : Colors.grey.shade200;
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text('Departments', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      )
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(child: _buildDateField(
                      label: 'Start Date',
                      date: _startDate,
                      icon: Icons.calendar_month,
                      onTap: _pickStartDate,
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: _buildDateField(
                      label: 'End Date',
                      date: _endDate,
                      icon: Icons.event,
                      onTap: _pickEndDate,
                    )),
                    if (_hasDateRange) ...[
                      const SizedBox(width: 6),
                      IconButton(
                        tooltip: 'Clear dates',
                        onPressed: _clearDateRange,
                        icon: Icon(Icons.clear, color: _secondaryTextColor),
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
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _departmentsMap.length,
              itemBuilder: (context, index) {
                final dept = _departmentsMap.keys.elementAt(index);
                final employees = _departmentsMap[dept] ?? [];

                return _buildDepartmentCard(dept, employees);
              },
            ),
          ),
        ],
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

