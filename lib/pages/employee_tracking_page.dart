// lib/pages/employee_tracking_page.dart

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/sap_service.dart';
import '../services/audit_service.dart';
import 'track_order.dart';

class EmployeeTrackingPage extends StatefulWidget {
  final EmployeeAuth loggedInEmployee;

  const EmployeeTrackingPage({
    Key? key,
    required this.loggedInEmployee,
  }) : super(key: key);

  @override
  State<EmployeeTrackingPage> createState() => _EmployeeTrackingPageState();
}

class _EmployeeTrackingPageState extends State<EmployeeTrackingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final EmployeeAuthService _authService =
  EmployeeAuthService(Supabase.instance.client);
  final SAPMainService _sapService =
  SAPMainService(Supabase.instance.client);

  final AuditService _auditService =
  AuditService(Supabase.instance.client);

  bool _isLoading = true;
  String? _error;

  List<EmployeeAuth> _employees = [];
  List<SAPMainOrder> _orders = [];
  List<Map<String, dynamic>> _auditLogs = [];

  // Fast lookup for audit-log order IDs. This avoids scanning every order for
  // every movement and keeps the tracking page responsive with large history.
  final Map<String, SAPMainOrder> _ordersById = {};

  // Cached employee movements. Invalidated whenever data or filters change.
  final Map<String, List<Map<String, dynamic>>> _changesCache = {};
  final Set<String> _expandedEmployees = <String>{};
  // Employees whose workload bar is displayed as UNIQUE CONTRACT counts
  // instead of order/item-row counts.
  final Set<String> _contractCountEmployees = <String>{};

  DateTime? _startDate;
  DateTime? _endDate;

  String? _selectedEmployeeId;
  String _selectedRole = 'All';

  final List<String> _roles = const [
    'All',
    'Responsible Engineer',
    'Reviewer',
    'Alternative Engineer',
    'Other',
  ];

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color get _backgroundColor =>
      _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

  Color get _cardColor =>
      _isDark ? const Color(0xFF1E293B) : Colors.white;

  Color get _textColor =>
      _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);

  Color get _secondaryTextColor =>
      _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  Color get _borderColor =>
      _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  Color get _mutedColor =>
      _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final employees = await _authService.getAllEmployees();
      final orders = await _sapService.getAllOrders();

      // Load ALL audit changes. Employee tracking is based on every
      // change made by the employee, not only Done/final status changes.
      // Supabase/PostgREST commonly caps a single response at 1,000 rows.
      // Load the complete audit history in pages so Employee Tracking does
      // not silently lose older employee movements.
      const pageSize = 1000;
      final allAuditRows = <Map<String, dynamic>>[];
      var pageStart = 0;

      while (true) {
        final pageRows = await _supabase
            .from('order_audit_log')
            .select(
          'id, order_id, field_name, old_value, new_value, '
              'changed_at, changed_by, changed_by_id',
        )
            .order('changed_at', ascending: true)
            .order('id', ascending: true)
            .range(pageStart, pageStart + pageSize - 1);

        final page = (pageRows as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        allAuditRows.addAll(page);

        debugPrint(
          '[AUDIT DEBUG] Loaded audit page: '
              'range=$pageStart-${pageStart + pageSize - 1}, '
              'rows=${page.length}, total=${allAuditRows.length}',
        );

        if (page.length < pageSize) {
          break;
        }

        pageStart += pageSize;
      }


      if (!mounted) return;

      final ordersById = <String, SAPMainOrder>{
        for (final order in orders) order.id.trim(): order,
      };

      setState(() {
        _employees = employees;
        _orders = orders;
        _ordersById
          ..clear()
          ..addAll(ordersById);
        _auditLogs = allAuditRows;
        _changesCache.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();

    final text = value.toString().trim();
    if (text.isEmpty) return null;

    return DateTime.tryParse(text)?.toLocal();
  }

  DateTime _dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  bool _inDateRange(DateTime? date) {
    if (_startDate == null && _endDate == null) return true;
    if (date == null) return false;

    final d = _dateOnly(date);

    if (_startDate != null && d.isBefore(_dateOnly(_startDate!))) {
      return false;
    }

    if (_endDate != null && d.isAfter(_dateOnly(_endDate!))) {
      return false;
    }

    return true;
  }

  bool get _hasDateRange => _startDate != null || _endDate != null;

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy').format(date);
  }

  String _formatDateTime(DateTime? date) {
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy  HH:mm').format(date);
  }

  String _employeeName(EmployeeAuth employee) => employee.fullName.trim();

  String? _selectedEmployeeName() {
    if (_selectedEmployeeId == null) return null;

    for (final employee in _employees) {
      if (employee.id == _selectedEmployeeId) {
        return _employeeName(employee);
      }
    }

    return null;
  }

  String _normalize(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  // Employee tracking uses the COMPLETE audit log.
  // Every audit change made by the selected employee is included:
  // status, design team, engineer assignment, reviewer, factory, etc.
  // There is no restriction to specific source statuses.

  bool _matchesSelectedRole(Map<String, dynamic> log, SAPMainOrder order) {
    if (_selectedRole == 'All') return true;

    final employeeId = log['changed_by_id']?.toString().trim() ?? '';
    final employeeName = log['changed_by']?.toString().trim() ?? '';

    final responsible = order.responsibleEngineer?.trim() ?? '';
    final reviewer = order.reviewer?.trim() ?? '';
    final alternative = order.correspondenceEngineer?.trim() ?? '';

    bool matches(String? name) {
      return employeeName.isNotEmpty &&
          name != null &&
          name.trim().isNotEmpty &&
          _samePerson(employeeName, name);
    }

    switch (_selectedRole) {
      case 'Responsible Engineer':
        return matches(responsible);
      case 'Reviewer':
        return matches(reviewer);
      case 'Alternative Engineer':
        return matches(alternative);
      case 'Other':
        return !matches(responsible) &&
            !matches(reviewer) &&
            !matches(alternative);
      default:
        return true;
    }
  }

  bool _isTrackedStatusTransition(Map<String, dynamic> log) {
    final field = _normalize(log['field_name']?.toString() ?? '');
    final oldValue = _normalize(log['old_value']?.toString() ?? '');
    final newValue = _normalize(log['new_value']?.toString() ?? '');

    return field == 'status' &&
        oldValue.isNotEmpty &&
        newValue.isNotEmpty &&
        oldValue != newValue;
  }

  String _transitionLabel(Map<String, dynamic> log) {
    final from = _displayAuditValue(log['old_value']);
    final to = _displayAuditValue(log['new_value']);
    return '$from → $to';
  }

  Map<String, int> _stageCounts(
      List<Map<String, dynamic>> changes) {
    final counts = <String, int>{
      'Drawing Submittal': 0,
      'Task': 0,
      'Modification': 0,
      'Manufacturing': 0,
    };

    for (final change in changes) {
      final log = Map<String, dynamic>.from(change['log'] as Map);
      if (!_isTrackedStatusTransition(log)) continue;

      final from = _normalize(log['old_value']?.toString() ?? '');
      if (from == 'drawing submittal' ||
          from == 'drawing submission' ||
          from == 'drawing submitted') {
        counts['Drawing Submittal'] = counts['Drawing Submittal']! + 1;
      } else if (from == 'task' ||
          from == 'tasks' ||
          from == 'task done') {
        counts['Task'] = counts['Task']! + 1;
      } else if (from == 'modification' ||
          from == 'modifications' ||
          from == 'modification submitted' ||
          from == 'modifications submitted') {
        counts['Modification'] = counts['Modification']! + 1;
      } else if (from == 'manufacturing drawing' ||
          from == 'manufacturing' ||
          from == 'manifactury') {
        counts['Manufacturing'] = counts['Manufacturing']! + 1;
      }
    }

    return counts;
  }

  Map<String, int> _transitionCounts(
      List<Map<String, dynamic>> changes) {
    final counts = <String, int>{};

    for (final change in changes) {
      final log = Map<String, dynamic>.from(change['log'] as Map);
      if (!_isTrackedStatusTransition(log)) continue;

      final label = _transitionLabel(log);
      counts[label] = (counts[label] ?? 0) + 1;
    }

    return counts;
  }

  bool _samePerson(String? a, String? b) {
    if (a == null || b == null) return false;

    final first = _normalize(a);
    final second = _normalize(b);

    return first.isNotEmpty && first == second;
  }

  // Workload ownership rule:
  // Correspondence Engineer has priority. Responsible Engineer is used only
  // when Correspondence Engineer is empty.
  String _roleForOrder(SAPMainOrder order, String employeeName) {
    final correspondence = order.correspondenceEngineer?.trim() ?? '';
    if (correspondence.isNotEmpty) {
      return _samePerson(correspondence, employeeName)
          ? 'Alternative Engineer'
          : '';
    }

    final responsible = order.responsibleEngineer?.trim() ?? '';
    if (responsible.isNotEmpty &&
        _samePerson(responsible, employeeName)) {
      return 'Responsible Engineer';
    }

    return '';
  }



  SAPMainOrder? _findOrder(String orderId) {
    return _ordersById[orderId.trim()];
  }

  // Status transitions come from the audit log, but workload ownership
  // comes from the order assignment:
  // 1) Responsible Engineer has priority.
  // 2) If Responsible Engineer is empty, use Correspondence Engineer.
  // changed_by is NOT used to decide who receives the workload credit.
  // Changes flow:
  // 1) Determine the employee's orders from the CURRENT assignment.
  // 2) Correspondence Engineer has priority. If it is empty, use
  //    Responsible Engineer.
  // 3) Once the employee's order IDs are known, search the audit log by
  //    order_id and show ALL changes for those orders.
  // 4) changed_by is NOT used to decide which employee owns the order.
  List<Map<String, dynamic>> _changesForEmployee(
      EmployeeAuth employee,
      ) {
    final cacheKey =
        '${employee.id}|assigned-order-changes|$_selectedRole|'
        '${_startDate?.millisecondsSinceEpoch ?? ''}|'
        '${_endDate?.millisecondsSinceEpoch ?? ''}';

    final cached = _changesCache[cacheKey];
    if (cached != null) return cached;

    final assignedOrders = _ordersForEmployee(employee);
    final assignedOrderIds = assignedOrders
        .map((order) => order.id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();

    final result = <Map<String, dynamic>>[];

    if (assignedOrderIds.isEmpty) {
      _changesCache[cacheKey] = result;
      return result;
    }

    // Search the complete audit log by the assigned order IDs.
    // Do not use changed_by / changed_by_id for ownership.
    for (final log in _auditLogs) {
      final orderId = log['order_id']?.toString().trim() ?? '';
      if (orderId.isEmpty || !assignedOrderIds.contains(orderId)) {
        continue;
      }

      final changedAt = _parseDate(log['changed_at']);
      if (!_inDateRange(changedAt)) continue;

      final order = _findOrder(orderId);
      if (order == null) continue;

      result.add({
        'log': log,
        'order': order,
        'role': _roleForOrder(order, employee.fullName),
        'changedAt': changedAt,
      });
    }

    result.sort((a, b) {
      final ad = a['changedAt'] as DateTime?;
      final bd = b['changedAt'] as DateTime?;

      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });

    _changesCache[cacheKey] = result;
    return result;
  }

  List<SAPMainOrder> _ordersForEmployee(EmployeeAuth employee) {
    final result = <SAPMainOrder>[];
    final employeeName = employee.fullName.trim();

    for (final order in _orders) {
      final correspondence = order.correspondenceEngineer?.trim() ?? '';

      // Correspondence Engineer is the primary owner.
      // Responsible Engineer is used only when Correspondence Engineer
      // is empty.
      final owner = correspondence.isNotEmpty
          ? correspondence
          : (order.responsibleEngineer?.trim() ?? '');

      if (owner.isEmpty) continue;

      if (_samePerson(owner, employeeName)) {
        result.add(order);
      }
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

  String _fieldLabel(dynamic field) {
    final value = field?.toString().trim() ?? '';
    if (value.isEmpty) return 'Order';

    return value
        .replaceAll('_', ' ')
        .replaceAll('-', ' ')
        .split(RegExp(r'\s+'))
        .map(
          (word) => word.isEmpty
          ? word
          : '${word[0].toUpperCase()}${word.substring(1)}',
    )
        .join(' ');
  }

  String _displayAuditValue(dynamic value) {
    final result = value?.toString().trim() ?? '';
    return result.isEmpty ? 'Empty' : result;
  }

  String _changeDescription(Map<String, dynamic> log) {
    final field = _fieldLabel(log['field_name']);
    final oldValue = _displayAuditValue(log['old_value']);
    final newValue = _displayAuditValue(log['new_value']);

    return '$field: $oldValue → $newValue';
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

  Widget _buildChangeRow(Map<String, dynamic> change) {
    final log = Map<String, dynamic>.from(change['log'] as Map);
    final order = change['order'] as SAPMainOrder;
    final role = change['role']?.toString() ?? '';
    final changedAt = change['changedAt'] as DateTime?;

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
              final roleColor = _roleColor(role);

              final orderInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order.designOrder.isNotEmpty
                              ? order.designOrder
                              : order.id,
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
                    '${order.contractNumber} • ${order.customerName}',
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
                ],
              );

              final changeInfo = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _changeDescription(log),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: _textColor,
                    ),
                  ),
                  if (changedAt != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      _formatDateTime(changedAt),
                      style: GoogleFonts.cairo(
                        fontSize: 9,
                        color: _secondaryTextColor,
                      ),
                    ),
                  ],
                ],
              );

              final roleBadge = Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  role.isEmpty ? 'Other' : role,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 9,
                    fontWeight: FontWeight.w600,
                    color: roleColor,
                  ),
                ),
              );

              if (narrow) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: orderInfo),
                        const SizedBox(width: 8),
                        roleBadge,
                      ],
                    ),
                    const SizedBox(height: 9),
                    changeInfo,
                    const SizedBox(height: 7),
                    _buildStatusBadge(order.status),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(flex: 3, child: orderInfo),
                  const SizedBox(width: 14),
                  Expanded(flex: 3, child: changeInfo),
                  const SizedBox(width: 14),
                  roleBadge,
                  const SizedBox(width: 12),
                  _buildStatusBadge(order.status),
                ],
              );
            },
          ),
        ),
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
                          order.designOrder.isNotEmpty
                              ? order.designOrder
                              : order.id,
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
                    '${order.contractNumber} • ${order.customerName}',
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

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'SELECT START DATE',
    );

    if (picked == null) return;

    setState(() {
      _startDate = DateTime(picked.year, picked.month, picked.day);

      if (_endDate != null && _endDate!.isBefore(_startDate!)) {
        _endDate = _startDate;
      }
    });
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
    });
  }

  void _clearDates() {
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  Color _roleColor(String role) {
    switch (role) {
      case 'Responsible Engineer':
        return Colors.orange;
      case 'Reviewer':
        return Colors.purple;
      case 'Alternative Engineer':
        return Colors.teal;
      default:
        return Colors.blue;
    }
  }

  IconData _roleIcon(String role) {
    switch (role) {
      case 'Responsible Engineer':
        return Icons.engineering;
      case 'Reviewer':
        return Icons.rate_review;
      case 'Alternative Engineer':
        return Icons.alt_route;
      default:
        return Icons.work_outline;
    }
  }

  Color _statusColor(String status) {
    switch (_normalize(status)) {
      case 'done':
      case 'task done':
      case 'planning':
        return Colors.green;
      case 'approval':
        return Colors.blue;
      case 'modifications submitted':
      case 'modification submitted':
      case 'modification':
        return Colors.orange;
      case 'manufacturing drawing':
        return Colors.deepPurple;
      case 'master data':
        return Colors.teal;
      default:
        return Colors.grey;
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
            color: date != null
                ? const Color(0xFF6366F1)
                : _borderColor,
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
                    _formatDate(date),
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      fontSize: 12,
                      color: date != null
                          ? _textColor
                          : _secondaryTextColor,
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

  Widget _buildFilterBar(bool compact) {
    return Container(
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 700;

          final dateFields = Row(
            children: [
              Expanded(
                child: _buildDateField(
                  label: 'Start Date',
                  date: _startDate,
                  icon: Icons.calendar_month,
                  onTap: _pickStartDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDateField(
                  label: 'End Date',
                  date: _endDate,
                  icon: Icons.event,
                  onTap: _pickEndDate,
                ),
              ),
              if (_hasDateRange)
                IconButton(
                  tooltip: 'Clear dates',
                  onPressed: _clearDates,
                  icon: Icon(
                    Icons.clear,
                    color: _secondaryTextColor,
                  ),
                ),
            ],
          );

          final roleField = DropdownButtonFormField<String>(
            value: _roles.contains(_selectedRole)
                ? _selectedRole
                : 'All',
            decoration: InputDecoration(
              labelText: 'From Status',
              labelStyle: GoogleFonts.cairo(
                color: _secondaryTextColor,
              ),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: GoogleFonts.cairo(
              color: _textColor,
              fontSize: 12,
            ),
            items: _roles
                .map(
                  (role) => DropdownMenuItem<String>(
                value: role,
                child: Text(
                  role,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    color: _textColor,
                    fontSize: 12,
                  ),
                ),
              ),
            )
                .toList(),
            onChanged: (value) {
              setState(() {
                _selectedRole = value ?? 'All';
                _changesCache.clear();
              });
            },
          );

          final employeeField =
          DropdownButtonFormField<String?>(
            value: _selectedEmployeeId,
            decoration: InputDecoration(
              labelText: 'Employee',
              labelStyle: GoogleFonts.cairo(
                color: _secondaryTextColor,
              ),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            style: GoogleFonts.cairo(
              color: _textColor,
              fontSize: 12,
            ),
            items: [
              DropdownMenuItem<String?>(
                value: null,
                child: Text(
                  'All Employees',
                  style: GoogleFonts.cairo(
                    color: _textColor,
                    fontSize: 12,
                  ),
                ),
              ),
              ..._employees.map(
                    (employee) => DropdownMenuItem<String?>(
                  value: employee.id,
                  child: Text(
                    employee.fullName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.cairo(
                      color: _textColor,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
            onChanged: (value) {
              setState(() {
                _selectedEmployeeId = value;
                _changesCache.clear();
              });
            },
          );

          if (narrow) {
            return Column(
              children: [
                dateFields,
                const SizedBox(height: 10),
                roleField,
                const SizedBox(height: 10),
                employeeField,
              ],
            );
          }

          return Row(
            children: [
              Expanded(flex: 2, child: dateFields),
              const SizedBox(width: 12),
              Expanded(child: roleField),
              const SizedBox(width: 12),
              Expanded(child: employeeField),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: _secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
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
  }

  /// Returns the current progress percentage for an order based on its
  /// current workflow status.
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

  /// Average of the current progress of the supplied orders.
  /// This is based on the order's CURRENT status, not on the audit change
  /// being displayed.
  int _averageProgress(List<SAPMainOrder> orders) {
    if (orders.isEmpty) return 0;

    final total = orders.fold<int>(
      0,
          (sum, order) => sum + _progressForOrder(order),
    );

    return (total / orders.length).round();
  }

  Widget _buildTransitionBreakdown(
      List<Map<String, dynamic>> changes,
      bool compact,
      ) {
    final counts = _transitionCounts(changes);

    if (counts.isEmpty) {
      return const SizedBox.shrink();
    }

    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: _mutedColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ...entries.map(
                (entry) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.key,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        color: _textColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  // ONLY THE NUMBER is tappable.
                  // Tapping it opens the popup with the actual changes.
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => _showTransitionChanges(
                        entry.key,
                        changes,
                        compact,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 28),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${entry.value}',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.cairo(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.blue,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTransitionChanges(
      String transition,
      List<Map<String, dynamic>> changes,
      bool compact,
      ) {
    final transitionChanges = changes.where((change) {
      final log = Map<String, dynamic>.from(change['log'] as Map);
      return _isTrackedStatusTransition(log) &&
          _transitionLabel(log) == transition;
    }).toList();

    if (transitionChanges.isEmpty) return;

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
              padding: EdgeInsets.all(compact ? 12 : 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.swap_horiz,
                        color: _secondaryTextColor,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          transition,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: compact ? 14 : 16,
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
                          '${transitionChanges.length} changes',
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
                    child: ListView.builder(
                      itemCount: transitionChanges.length,
                      itemBuilder: (context, index) {
                        return _buildChangeRow(transitionChanges[index]);
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

  Widget _buildEmployeeCard(
      EmployeeAuth employee,
      List<SAPMainOrder> orders,
      List<Map<String, dynamic>> changes,
      bool compact,
      ) {
    final average = _averageProgress(orders);

    final roles = <String>{};
    for (final change in changes) {
      final role = change['role']?.toString() ?? '';
      if (role.isNotEmpty) roles.add(role);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(compact ? 12 : 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: compact ? 20 : 23,
                backgroundColor:
                const Color(0xFF6366F1).withOpacity(0.12),
                child: Text(
                  employee.initials,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF6366F1),
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
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.cairo(
                        fontSize: compact ? 13 : 15,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: roles
                          .map(
                            (role) => _buildRoleBadge(role),
                      )
                          .toList(),
                    ),
                  ],
                ),
              ),

            ],
          ),
          const SizedBox(height: 12),
          const SizedBox(height: 10),
          Material(
            color: _mutedColor,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              onTap: () {
                setState(() {
                  // This is the ONLY inline expansion:
                  // All Changes -> show transition names + numbers.
                  final id = employee.id.trim();
                  if (_expandedEmployees.contains(id)) {
                    _expandedEmployees.remove(id);
                  } else {
                    _expandedEmployees.add(id);
                  }
                });
              },
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.history,
                      size: 16,
                      color: _secondaryTextColor,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        'All Changes (${changes.length})',
                        style: GoogleFonts.cairo(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _textColor,
                        ),
                      ),
                    ),
                    Icon(
                      _expandedEmployees.contains(employee.id.trim())
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: _secondaryTextColor,
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_expandedEmployees.contains(employee.id.trim())) ...[
            const SizedBox(height: 10),
            _buildTransitionBreakdown(changes, compact),
          ],
        ],
      ),
    );
  }

  Widget _buildRoleBadge(String role) {
    final color = _roleColor(role);

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
        role,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.cairo(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildMiniStat(
      String title,
      String value,
      IconData icon,
      Color color,
      ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            '$title: ',
            style: GoogleFonts.cairo(
              fontSize: 9,
              color: _secondaryTextColor,
            ),
          ),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
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

  void _showEmployeeChanges(
      EmployeeAuth employee,
      List<Map<String, dynamic>> changes,
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
                      CircleAvatar(
                        radius: 19,
                        backgroundColor:
                        const Color(0xFF6366F1).withOpacity(0.12),
                        child: Text(
                          employee.initials,
                          style: GoogleFonts.cairo(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF6366F1),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${employee.fullName} — All Changes',
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.cairo(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _textColor,
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
                  const SizedBox(height: 10),
                  Divider(color: _borderColor),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: changes.length,
                      itemBuilder: (context, index) {
                        return _buildChangeRow(changes[index]);
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

  Widget _buildSelectedEmployeeView(
      EmployeeAuth employee,
      List<SAPMainOrder> orders,
      List<Map<String, dynamic>> changes,
      bool compact,
      ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildEmployeeCard(
          employee,
          orders,
          changes,
          compact,
        ),
        const SizedBox(height: 4),
        if (changes.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.history_toggle_off,
                  size: 42,
                  color: _secondaryTextColor,
                ),
                const SizedBox(height: 10),
                Text(
                  'No changes found for the selected filters',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: _secondaryTextColor,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildAllEmployeesView(bool compact) {
    final visibleEmployees = _employees.where((employee) {
      return _changesForEmployee(employee).isNotEmpty;
    }).toList();

    if (visibleEmployees.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(35),
        decoration: BoxDecoration(
          color: _cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _borderColor),
        ),
        child: Column(
          children: [
            Icon(
              Icons.people_outline,
              size: 45,
              color: _secondaryTextColor,
            ),
            const SizedBox(height: 10),
            Text(
              'No employees have changes matching the selected filters',
              textAlign: TextAlign.center,
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: _secondaryTextColor,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: visibleEmployees.map((employee) {
        final changes = _changesForEmployee(employee);
        final orders = _ordersForEmployee(employee);

        return _buildEmployeeCard(
          employee,
          orders,
          changes,
          compact,
        );
      }).toList(),
    );
  }

  // Current workload graph:
  // Every order is assigned to Alternative Engineer when that field is filled.
  // Otherwise it is assigned to Responsible Engineer. The graph counts the
  // orders currently sitting in the four tracked workflow stages.
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
    return null;
  }

  Map<String, int> _unassignedWorkloadCounts() {
    var header = 0;
    var noOne = 0;
    var notAssigned = 0;

    for (final order in _orders) {
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
        },
      );
    }

    for (final order in _orders) {
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

  List<SAPMainOrder> _ordersForEmployeeStage(
      String employeeName,
      String stage,
      ) {
    // Build the popup from the exact same full _orders collection used by the
    // workload graph. Do NOT deduplicate by order id here: every row in
    // sap_main_orders is an order/item row and must be displayed.
    final result = <SAPMainOrder>[];

    for (final order in _orders) {
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

  List<SAPMainOrder> _ordersForSpecialWorkload(String special) {
    final result = <SAPMainOrder>[];

    for (final order in _orders) {
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
            ..._employees.map((employee) {
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

    // IMPORTANT:
    // Employee Tracking now receives the same EmployeeAuth instance as OrdersPage.
    // Do NOT use Supabase auth UID here because this project uses employees_auth.
    final EmployeeAuth auditEmployee = widget.loggedInEmployee;

    final changedBy = auditEmployee.fullName.trim();
    final changedById = auditEmployee.id.trim();

    try {
      // Resolve the audit actor BEFORE changing the database. This prevents
      // an order from being changed without a corresponding audit record.
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

      final index = _orders.indexWhere((item) => item.id == order.id);
      if (index != -1) {
        _orders[index] = updatedOrder;
      }

      _changesCache.clear();

      if (mounted) {
        setState(() {});
      }
      onUpdated?.call(updatedOrder);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_fieldLabel(field)} updated successfully',
              style: GoogleFonts.cairo(fontSize: 12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error updating ${_fieldLabel(field)}: $e',
            style: GoogleFonts.cairo(fontSize: 12),
          ),
        ),
      );
    }
  }

  void _showSpecialWorkloadOrders(String special) {
    final orders = _ordersForSpecialWorkload(special);
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
    };

    for (final order in _orders) {
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

    for (final order in _orders) {
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
    ];

    final stageColors = <String, Color>{
      'Drawing Submittal': Colors.blue,
      'Task': Colors.indigo,
      'Modification': Colors.orange,
      'Manufacturing': Colors.deepPurple,
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
          const SizedBox(height: 4),
          Text(
            'Each bar normally counts order rows. Use the checkbox under a bar to count unique contract numbers for that employee. Clicking a bar still opens all matching order rows.',
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: _secondaryTextColor,
            ),
          ),
          const SizedBox(height: 12),
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
                  const SizedBox(width: 5),
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
          const SizedBox(height: 12),
          SizedBox(
            height: chartHeight,
            child: BarChart(
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
                      final displayedTotal =
                          drawing + task + modification + manufacturing;
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

                    final orders = _ordersForEmployeeStage(
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
                        final checked =
                        _contractCountEmployees.contains(normalizedName);

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
                                const SizedBox(height: 1),
                                Transform.scale(
                                  scale: compact ? 0.70 : 0.78,
                                  child: Checkbox(
                                    value: checked,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (value) {
                                      setState(() {
                                        if (value == true) {
                                          _contractCountEmployees
                                              .add(normalizedName);
                                        } else {
                                          _contractCountEmployees
                                              .remove(normalizedName);
                                        }
                                      });
                                    },
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
                  final displayedTotal =
                      drawing + task + modification + manufacturing;

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
                            displayedTotal.toDouble(),
                            stageColors['Manufacturing']!,
                          ),
                        ],
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(List<EmployeeAuth> visibleEmployees) {
    int totalChanges = 0;
    final touchedOrders = <String>{};

    for (final employee in visibleEmployees) {
      final changes = _changesForEmployee(employee);
      totalChanges += changes.length;

      for (final change in changes) {
        final order = change['order'] as SAPMainOrder;
        touchedOrders.add(order.id.trim());
      }
    }

    final employeeAverages = visibleEmployees
        .map((employee) => _averageProgress(_ordersForEmployee(employee)))
        .toList();

    final average = employeeAverages.isEmpty
        ? 0
        : (employeeAverages.reduce((a, b) => a + b) /
        employeeAverages.length)
        .round();

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 650;

        final cards = [
          _buildSummaryCard(
            title: 'Employees',
            value: '${visibleEmployees.length}',
            subtitle: 'With matching changes',
            icon: Icons.people_alt_outlined,
            color: Colors.blue,
          ),
        ];

        if (narrow) {
          return Column(
            children: cards
                .map(
                  (card) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: card,
              ),
            )
                .toList(),
          );
        }

        return Row(
          children: cards
              .map(
                (card) => Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: card,
              ),
            ),
          )
              .toList(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          'Departments Tracking',
          style: GoogleFonts.cairo(
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? Center(
        child: CircularProgressIndicator(
          color: Theme.of(context).colorScheme.primary,
        ),
      )
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 42,
                color: Colors.red,
              ),
              const SizedBox(height: 12),
              Text(
                'Failed to load employee tracking',
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w700,
                  color: _textColor,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.cairo(
                  fontSize: 11,
                  color: _secondaryTextColor,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                label: Text(
                  'Retry',
                  style: GoogleFonts.cairo(),
                ),
              ),
            ],
          ),
        ),
      )
          : LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 700;

          final selectedName = _selectedEmployeeName();

          final selectedEmployee = selectedName == null
              ? null
              : _employees.firstWhere(
                (e) => e.id == _selectedEmployeeId,
          );

          final visibleEmployees = _employees.where((e) {
            return _changesForEmployee(e).isNotEmpty;
          }).toList();

          return SingleChildScrollView(
            padding: EdgeInsets.all(
              compact ? 12 : 24,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Track employee workload and progress',
                  style: GoogleFonts.cairo(
                    fontSize: compact ? 18 : 24,
                    fontWeight: FontWeight.bold,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 16),
                _buildCurrentWorkloadGraph(compact),
                const SizedBox(height: 16),
                _buildFilterBar(compact),
                const SizedBox(height: 16),
                _buildSummary(visibleEmployees),
                const SizedBox(height: 18),
                if (selectedEmployee != null)
                  _buildSelectedEmployeeView(
                    selectedEmployee,
                    _ordersForEmployee(selectedEmployee),
                    _changesForEmployee(selectedEmployee),
                    compact,
                  )
                else
                  _buildAllEmployeesView(compact),
              ],
            ),
          );
        },
      ),
    );
  }
}
