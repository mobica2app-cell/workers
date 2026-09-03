// lib/pages/order_tracking_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../services/audit_service.dart';
import '../services/sap_service.dart';

class OrderTrackingPage extends StatefulWidget {
  final SAPMainOrder order;

  const OrderTrackingPage({Key? key, required this.order}) : super(key: key);

  @override
  State<OrderTrackingPage> createState() => _OrderTrackingPageState();
}

class _OrderTrackingPageState extends State<OrderTrackingPage> {
  final AuditService _auditService = AuditService(Supabase.instance.client);
  List<Map<String, dynamic>> _auditLogs = [];
  bool _isLoading = true;
  bool _isRestoring = false;

  // Theme helper getters
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _backgroundColor => _isDark ? const Color(0xFF0F172A) : const Color(0xFFF8F9FA);
  Color get _surfaceColor => _isDark ? const Color(0xFF1E293B) : Colors.white;
  Color get _textColor => _isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A);
  Color get _secondaryTextColor => _isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);
  Color get _tertiaryTextColor => _isDark ? const Color(0xFF64748B) : const Color(0xFF45464D);
  Color get _borderColor => _isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0);
  Color get _cardColor => _isDark ? const Color(0xFF1E293B) : Colors.white;

  // Get current user info
  String get _currentUserName {
    // You can get this from a global state or pass it to the page
    // For now, we'll use a placeholder
    return 'Admin';
  }

  String get _currentUserId => '';

  @override
  void initState() {
    super.initState();
    _loadAuditLogs();
  }

  Future<void> _loadAuditLogs() async {
    setState(() => _isLoading = true);
    try {
      final logs = await _auditService.getOrderAuditLog(widget.order.id);
      setState(() {
        _auditLogs = logs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }



  // Restore a field to its previous value
  Future<void> _restoreField(Map<String, dynamic> log) async {
    final fieldName = log['field_name']?.toString();
    final oldValue = log['old_value'];
    final newValue = log['new_value'];

    if (fieldName == null || oldValue == null) {
      _showSnackBar('Cannot restore this change', isError: true);
      return;
    }

    // Don't restore if it's a delete action
    if (log['action_type'] == 'delete') {
      _showSnackBar('Cannot restore deleted orders', isError: true);
      return;
    }

    setState(() => _isRestoring = true);

    try {
      final supabase = Supabase.instance.client;

      // Update the order field back to old value
      await supabase
          .from('sap_main_orders')
          .update({fieldName: oldValue})
          .eq('id', widget.order.id);

      // Log the restoration in audit
      await _auditService.logChange(
        orderId: widget.order.id,
        designOrder: widget.order.designOrder,
        fieldName: fieldName,
        oldValue: newValue?.toString(),
        newValue: oldValue.toString(),
        changedBy: _currentUserName,
        changedById: _currentUserId,
        actionType: 'restore',
        notes: 'Restored from audit log: ${_formatDateTime(log['changed_at'])}',
      );

      _showSnackBar('✅ Restored ${_formatFieldName(fieldName)} to previous value');

      // Reload audit logs
      await _loadAuditLogs();
    } catch (e) {
      print('Error restoring: $e');
      _showSnackBar('Error restoring: $e', isError: true);
    } finally {
      setState(() => _isRestoring = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: GoogleFonts.cairo()),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // Get only status changes from audit logs (sorted by date - oldest first)
  List<Map<String, dynamic>> get _statusChanges {
    final changes = _auditLogs
        .where((log) => log['field_name'] == 'status' && log['action_type'] != 'restore')
        .toList();
    changes.sort((a, b) {
      final aDate = DateTime.tryParse(a['changed_at'] ?? '') ?? DateTime(2000);
      final bDate = DateTime.tryParse(b['changed_at'] ?? '') ?? DateTime(2000);
      return aDate.compareTo(bDate);
    });
    return changes;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        title: Text(
          'Order Tracking',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAuditLogs,
            tooltip: 'Refresh',
          ),
        ],
      ),
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
            _buildHeader(),
            const SizedBox(height: 24),
            _buildProcessFlow(),
            const SizedBox(height: 24),
            _buildOrderSummary(),
            const SizedBox(height: 24),
            _buildAuditLogSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.receipt_long,
                      color: Color(0xFF6366F1),
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.order.designOrder,
                      style: GoogleFonts.cairo(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: _textColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        widget.order.status,
                        style: GoogleFonts.cairo(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.order.description,
                  style: GoogleFonts.cairo(
                    fontSize: 14,
                    color: _secondaryTextColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.order.customerName,
                  style: GoogleFonts.cairo(
                    fontSize: 13,
                    color: _tertiaryTextColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessFlow() {
    final statusChanges = _statusChanges;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.route, color: Color(0xFF6366F1), size: 20),
          const SizedBox(width: 8),
          Text('Process Flow', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w600, color: _textColor)),
          const Spacer(),
          if (widget.order.deliveryDate != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('Delivery Date', style: GoogleFonts.cairo(fontSize: 11, color: _secondaryTextColor)),
              Text(widget.order.deliveryDate!, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600, color: _textColor)),
            ]),
        ]),
        const SizedBox(height: 24),

        if (statusChanges.isEmpty)
        // No status changes - show only current status
          Center(
            child: _buildStepCircle(
              status: widget.order.status,
              isCompleted: false,
              isCurrent: true,
              auditLog: null,
            ),
          )
        else
        // Show real status changes from audit log
          Scrollbar(
            thumbVisibility: true,
            trackVisibility: true,
            notificationPredicate: (notification) => notification.depth == 0,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(statusChanges.length + 1, (index) {
                  final isLast = index == statusChanges.length;

                  if (isLast) {
                    // Current status (the final destination)
                    return Row(children: [
                      if (statusChanges.isNotEmpty)
                        _buildConnector(isCompleted: true),
                      _buildStepCircle(
                        status: widget.order.status,
                        isCompleted: false,
                        isCurrent: true,
                        auditLog: null,
                      ),
                    ]);
                  } else {
                    // Completed status - show the OLD value (what was completed)
                    final audit = statusChanges[index];
                    final completedStatus = audit['old_value']?.toString() ?? 'Unknown';
                    return Row(children: [
                      _buildStepCircle(
                        status: completedStatus,
                        isCompleted: true,
                        isCurrent: false,
                        auditLog: audit,
                      ),
                      _buildConnector(isCompleted: true),
                    ]);
                  }
                }),
              ),
            ),
          ),
      ]),
    );
  }


  Widget _buildStepCircle({
    required String status,
    required bool isCompleted,
    required bool isCurrent,
    Map<String, dynamic>? auditLog,
  })
  {
    Color circleColor;
    Color textColor;
    IconData icon;
    String? dateStr;
    String? changedBy;

    if (isCompleted) {
      circleColor = const Color(0xFF059669);
      textColor = const Color(0xFF059669);
      icon = Icons.check_circle;
      if (auditLog != null) {
        dateStr = _formatDate(auditLog['changed_at']);
        changedBy = auditLog['changed_by'];
      }
    } else if (isCurrent) {
      circleColor = const Color(0xFFD97706);
      textColor = const Color(0xFFD97706);
      icon = Icons.play_circle;
    } else {
      circleColor = const Color(0xFFD97706);
      textColor = const Color(0xFFD97706);
      icon = Icons.schedule;
    }

    return SizedBox(
      width: 150,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: circleColor.withOpacity(0.1),
              shape: BoxShape.circle,
              border: Border.all(color: circleColor, width: 2.5),
            ),
            child: Icon(icon, color: circleColor, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            status.length > 18 ? '${status.substring(0, 16)}...' : status,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          if (isCompleted && dateStr != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF059669).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFF059669).withOpacity(0.2),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'Completed',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF059669),
                    ),
                  ),
                  Text(
                    dateStr,
                    style: GoogleFonts.cairo(
                      fontSize: 9,
                      color: _secondaryTextColor,
                    ),
                  ),
                  if (changedBy != null)
                    Text(
                      changedBy,
                      style: GoogleFonts.cairo(
                        fontSize: 9,
                        color: _secondaryTextColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ] else if (isCurrent) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD97706).withOpacity(0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: const Color(0xFFD97706).withOpacity(0.2),
                ),
              ),
              child: Text(
                'Current',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFFD97706),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConnector({required bool isCompleted}) {
    return Container(
      width: 50,
      height: 3,
      color: isCompleted ? const Color(0xFF059669) : _borderColor,
      margin: const EdgeInsets.only(bottom: 70),
    );
  }

  Widget _buildOrderSummary() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Summary',
            style: GoogleFonts.cairo(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildSummaryItem('Customer', widget.order.customerName),
              _buildSummaryItem('Contract', widget.order.contractNumber),
              _buildSummaryItem(
                'QTY',
                '${widget.order.quantity} ${widget.order.unitOfMeasure}',
              ),
              _buildSummaryItem(
                'Value',
                '\$${_formatNumber(widget.order.value)}',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildSummaryItem('Sales Engineer', widget.order.salesEngineer),
              _buildSummaryItem('Factory', widget.order.factory ?? 'N/A'),
              _buildSummaryItem(
                'Design Team',
                widget.order.designTeam ?? 'N/A',
              ),
              _buildSummaryItem('Order Date', widget.order.orderDate ?? 'N/A'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAuditLogSection() {
    if (_auditLogs.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: Color(0xFF6366F1), size: 20),
              const SizedBox(width: 8),
              Text(
                'Change History',
                style: GoogleFonts.cairo(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _textColor,
                ),
              ),
              const Spacer(),
              Text(
                '${_auditLogs.length} changes',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  color: _secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ..._auditLogs.map((log) => _buildAuditLogItem(log)),
        ],
      ),
    );
  }

  Widget _buildAuditLogItem(Map<String, dynamic> log) {
    final isDelete = log['action_type'] == 'delete';
    final isRestore = log['action_type'] == 'restore';
    final isStatus = log['field_name'] == 'status';

    IconData icon = isDelete
        ? Icons.delete
        : isRestore
        ? Icons.restore
        : (isStatus ? Icons.swap_horiz : Icons.edit);

    Color color = isDelete
        ? Colors.red
        : isRestore
        ? Colors.purple
        : (isStatus ? const Color(0xFF6366F1) : Colors.blue);

    // Check if this log can be restored (not a delete or restore action)
    final canRestore = !isDelete && !isRestore && log['old_value'] != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(color: _borderColor.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  RichText(
                    text: TextSpan(
                      style: GoogleFonts.cairo(
                        fontSize: 13,
                        color: _textColor,
                      ),
                      children: [
                        TextSpan(
                          text: _formatFieldName(log['field_name']),
                          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
                        ),
                        if (isRestore) ...[
                          TextSpan(
                            text: ' (Restored)',
                            style: GoogleFonts.cairo(
                              color: Colors.purple,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                        const TextSpan(text: ': '),
                        if (log['old_value'] != null)
                          TextSpan(
                            text: '${log['old_value']}',
                            style: GoogleFonts.cairo(
                              color: _isDark ? Colors.red.shade300 : Colors.red.shade700,
                              decoration: isRestore ? null : TextDecoration.lineThrough,
                            ),
                          ),
                        if (log['old_value'] != null && log['new_value'] != null)
                          const TextSpan(text: ' → '),
                        if (log['new_value'] != null)
                          TextSpan(
                            text: '${log['new_value']}',
                            style: GoogleFonts.cairo(
                              color: const Color(0xFF059669),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'By ${log['changed_by']} • ${_formatDateTime(log['changed_at'])}',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      color: _secondaryTextColor,
                    ),
                  ),
                  if (log['notes'] != null && log['notes'].toString().isNotEmpty)
                    Text(
                      log['notes'].toString(),
                      style: GoogleFonts.cairo(
                        fontSize: 10,
                        color: _secondaryTextColor,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                ],
              ),
            ),
            if (canRestore)
              TextButton.icon(
                onPressed: _isRestoring ? null : () => _restoreField(log),
                icon: const Icon(Icons.restore, size: 16),
                label: Text(
                  'Restore',
                  style: GoogleFonts.cairo(fontSize: 11),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.purple,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: _secondaryTextColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: _textColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _formatFieldName(String? field) {
    switch (field) {
      case 'status':
        return 'Status';
      case 'design_team':
        return 'Design Team';
      case 'responsible_engineer':
        return 'Resp. Engineer';
      case 'reviewer':
        return 'Reviewer';
      case 'correspondence_engineer':
        return 'Alt. Engineer';
      case 'sales_engineer':
        return 'Sales Engineer';
      case 'factory':
        return 'Factory';
      case 'order_deleted':
        return 'Order Deleted';
      default:
        return field ?? 'Unknown';
    }
  }

  String _formatDate(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      return DateFormat('MMM dd, yyyy').format(DateTime.parse(dateTimeStr));
    } catch (e) {
      return '';
    }
  }

  String _formatDateTime(String? dateTimeStr) {
    if (dateTimeStr == null) return '';
    try {
      return DateFormat('MMM dd, HH:mm').format(DateTime.parse(dateTimeStr));
    } catch (e) {
      return dateTimeStr;
    }
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
}

