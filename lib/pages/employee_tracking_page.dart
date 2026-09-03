// lib/pages/employee_tracking_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../services/sap_service.dart';

class EmployeeTrackingPage extends StatefulWidget {
  const EmployeeTrackingPage({Key? key}) : super(key: key);

  @override
  State<EmployeeTrackingPage> createState() => _EmployeeTrackingPageState();
}

class _EmployeeTrackingPageState extends State<EmployeeTrackingPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final EmployeeAuthService _authService =
  EmployeeAuthService(Supabase.instance.client);
  final SAPMainService _sapService =
  SAPMainService(Supabase.instance.client);

  bool _isLoading = true;
  String? _error;

  List<EmployeeAuth> _employees = [];
  List<SAPMainOrder> _orders = [];
  List<Map<String, dynamic>> _auditLogs = [];

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
      final auditRows = await _supabase
          .from('order_audit_log')
          .select(
        'id, order_id, field_name, old_value, new_value, '
            'changed_at, changed_by, changed_by_id',
      )
          .order('changed_at', ascending: true)
          .limit(100000);

      if (!mounted) return;

      setState(() {
        _employees = employees;
        _orders = orders;
        _auditLogs = (auditRows as List)
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
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

  bool _samePerson(String? a, String? b) {
    if (a == null || b == null) return false;

    final first = _normalize(a);
    final second = _normalize(b);

    return first.isNotEmpty && first == second;
  }

  // Alternative Engineer is the project's correspondence_engineer field.
  // If an alternative/correspondence engineer exists, the responsible
  // engineer is not treated as the owner of that order in this report.
  String _roleForOrder(SAPMainOrder order, String employeeName) {
    // Alternative Engineer (correspondence_engineer) has priority.
    if (_samePerson(order.correspondenceEngineer, employeeName)) {
      return 'Alternative Engineer';
    }

    if (_samePerson(order.reviewer, employeeName)) {
      return 'Reviewer';
    }

    // If an Alternative Engineer exists, the Responsible Engineer is not
    // considered the owner for the role-specific tracking view.
    if (_samePerson(order.responsibleEngineer, employeeName)) {
      final alternative = order.correspondenceEngineer?.trim() ?? '';
      if (alternative.isNotEmpty) {
        return '';
      }

      return 'Responsible Engineer';
    }

    return '';
  }

  bool _matchesRole(SAPMainOrder order, String employeeName) {
    // IMPORTANT:
    // The audit actor is the source of truth for employee activity.
    // An employee can edit an order even when they are not currently
    // assigned to it. Therefore "All" must never discard a real audit
    // change based on the order's current assignment.
    if (_selectedRole == 'All') return true;

    final role = _roleForOrder(order, employeeName);

    if (_selectedRole == 'Other') {
      return role.isEmpty;
    }

    if (role.isEmpty) return false;

    return role == _selectedRole;
  }

  bool _auditWasMadeBy(
      Map<String, dynamic> log,
      EmployeeAuth employee,
      ) {
    final changedById = log['changed_by_id']?.toString().trim();
    final changedBy = log['changed_by']?.toString().trim();

    if (changedById != null &&
        changedById.isNotEmpty &&
        changedById == employee.id.trim()) {
      return true;
    }

    return _samePerson(changedBy, employee.fullName);
  }

  SAPMainOrder? _findOrder(String orderId) {
    for (final order in _orders) {
      if (order.id.trim() == orderId.trim()) return order;
    }
    return null;
  }

  // Every audit-log change made by the employee.
  // The date filter is applied to changed_at, because this tracks activity
  // performed by the employee rather than when the order was created.
  List<Map<String, dynamic>> _changesForEmployee(
      EmployeeAuth employee,
      ) {
    final result = <Map<String, dynamic>>[];

    for (final log in _auditLogs) {
      if (!_auditWasMadeBy(log, employee)) continue;

      final changedAt = _parseDate(log['changed_at']);
      if (!_inDateRange(changedAt)) continue;

      final orderId = log['order_id']?.toString().trim() ?? '';
      final order = _findOrder(orderId);
      if (order == null) continue;

      if (!_matchesRole(order, employee.fullName)) continue;

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

    return result;
  }

  List<SAPMainOrder> _ordersForEmployee(EmployeeAuth employee) {
    final seen = <String>{};
    final result = <SAPMainOrder>[];

    for (final change in _changesForEmployee(employee)) {
      final order = change['order'] as SAPMainOrder;

      if (seen.add(order.id.trim())) {
        result.add(order);
      }
    }

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

  Widget _buildChangeRow(Map<String, dynamic> change) {
    final log = Map<String, dynamic>.from(change['log'] as Map);
    final order = change['order'] as SAPMainOrder;
    final role = change['role']?.toString() ?? '';
    final changedAt = change['changedAt'] as DateTime?;

    return Container(
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
              Text(
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
              role,
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
              Expanded(flex: 2, child: orderInfo),
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
              labelText: 'Work Role',
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
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$average%',
                    style: GoogleFonts.cairo(
                      fontSize: compact ? 17 : 20,
                      fontWeight: FontWeight.bold,
                      color: _roleColor(
                        roles.isEmpty ? 'All' : roles.first,
                      ),
                    ),
                  ),
                  Text(
                    'Progress',
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildMiniStat(
                  'Orders Touched',
                  '${orders.length}',
                  Icons.receipt_long,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStat(
                  'Every Change',
                  '${changes.length}',
                  Icons.history,
                  Colors.orange,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMiniStat(
                  'Current Avg.',
                  '$average%',
                  Icons.trending_up,
                  Colors.green,
                ),
              ),
            ],
          ),
          if (orders.isNotEmpty) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _showEmployeeChanges(
                  employee,
                  changes,
                ),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(
                  'View Changes',
                  style: GoogleFonts.cairo(fontSize: 11),
                ),
              ),
            ),
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
          )
        else
          Container(
            padding: EdgeInsets.all(compact ? 12 : 16),
            decoration: BoxDecoration(
              color: _cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _borderColor),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Every Change Made',
                  style: GoogleFonts.cairo(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Showing ${changes.length} audit changes made by ${employee.fullName}.',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: _secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 12),
                ...changes.map(_buildChangeRow),
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
          _buildSummaryCard(
            title: 'Every Change',
            value: '$totalChanges',
            subtitle: 'Audit changes made',
            icon: Icons.history,
            color: Colors.indigo,
          ),
          _buildSummaryCard(
            title: 'Orders Touched',
            value: '${touchedOrders.length}',
            subtitle: 'Unique orders',
            icon: Icons.receipt_long,
            color: Colors.teal,
          ),
          _buildSummaryCard(
            title: 'Current Avg. Progress',
            value: '$average%',
            subtitle: 'Across matching orders',
            icon: Icons.trending_up,
            color: Colors.orange,
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
          'Employee Tracking',
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
                const SizedBox(height: 4),
                Text(
                  "Every audit-log change is credited to the employee who actually made it. Role filters use the employee's current order assignment.",
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: _secondaryTextColor,
                  ),
                ),
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

