// lib/pages/order_detail_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/employee_model.dart';
import '../services/employee_service.dart';
import '../services/sap_service.dart';
import 'employee_profile_page.dart';

class OrderDetailPage extends StatefulWidget {
  final SAPMainOrder order;
  final SAPMainService sapService;

  const OrderDetailPage({
    Key? key,
    required this.order,
    required this.sapService,
  }) : super(key: key);

  @override
  State<OrderDetailPage> createState() => _OrderDetailPageState();
}

class _OrderDetailPageState extends State<OrderDetailPage> {
  final EmployeeService _employeeService = EmployeeService();

  List<JobAssignment> _itemJobs = [];
  bool _isLoadingJobs = false;
  Map<String, Employee?> _employeeCache = {};

  // All orders with the same CONTRACT number
  List<SAPMainOrder> _relatedOrders = [];
  bool _isLoadingRelatedOrders = false;

  double get _totalValue {
    return _relatedOrders.fold(0, (sum, order) => sum + order.value);
  }

  double get _totalQuantity {
    return _relatedOrders.fold(0, (sum, order) => sum + order.quantity);
  }

  int get _totalItems => _relatedOrders.length;

  @override
  void initState() {
    super.initState();
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    await _loadRelatedOrders();
    await _loadItemJobs();
  }

  Future<void> _loadRelatedOrders() async {
    setState(() => _isLoadingRelatedOrders = true);
    try {
      final contractNumber = widget.order.contractNumber.trim();
      print('🔍 Searching for contract: $contractNumber');

      final allOrders = await widget.sapService.getAllOrders();

      _relatedOrders = allOrders.where((order) {
        return order.contractNumber.trim() == contractNumber;
      }).toList();

      if (_relatedOrders.isEmpty) {
        _relatedOrders = [widget.order];
      }

      print('🔗 Related orders found: ${_relatedOrders.length}');

      setState(() => _isLoadingRelatedOrders = false);
    } catch (e) {
      print('❌ Error: $e');
      setState(() {
        _isLoadingRelatedOrders = false;
        _relatedOrders = [widget.order];
      });
    }
  }

  Future<void> _loadItemJobs() async {
    setState(() => _isLoadingJobs = true);
    try {
      final allJobs = await _employeeService.getAllJobs();

      final allProductCodes = _relatedOrders
          .map((order) => order.productCode)
          .where((code) => code.isNotEmpty)
          .toSet();

      final relevantJobs = allJobs.where((job) =>
          allProductCodes.contains(job.productCode)
      ).toList();

      for (var job in relevantJobs) {
        if (!_employeeCache.containsKey(job.employeeId)) {
          final employee = await _employeeService.getEmployeeById(job.employeeId);
          _employeeCache[job.employeeId] = employee;
        }
      }

      setState(() {
        _itemJobs = relevantJobs;
        _isLoadingJobs = false;
      });
    } catch (e) {
      print('Error loading jobs: $e');
      setState(() => _isLoadingJobs = false);
    }
  }

  JobAssignment? _getJobForItem(String productCode) {
    try {
      return _itemJobs.firstWhere((job) => job.productCode == productCode);
    } catch (e) {
      return null;
    }
  }

  String _getItemStatus(String productCode) {
    final job = _getJobForItem(productCode);
    if (job != null) return job.status;
    return 'not_assigned';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'in_progress': return Colors.blue;
      case 'completed': return Colors.green;
      case 'on_hold': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'pending': return 'Pending';
      case 'in_progress': return 'In Progress';
      case 'completed': return 'Completed';
      case 'on_hold': return 'On Hold';
      case 'not_assigned': return 'Not Assigned';
      default: return status;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status) {
      case 'pending': return Icons.schedule;
      case 'in_progress': return Icons.play_circle;
      case 'completed': return Icons.check_circle;
      case 'on_hold': return Icons.pause_circle;
      default: return Icons.help_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Contract ${widget.order.contractNumber}', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: _loadAllData, tooltip: 'Refresh'),
        ],
      ),
      body: _isLoadingRelatedOrders
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0)), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 2))]),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _buildInfoRow('Customer', widget.order.customerName),
                  const SizedBox(height: 8),
                  _buildInfoRow('Contract', widget.order.contractNumber),
                  const SizedBox(height: 8),
                  _buildInfoRow('Design Order', widget.order.designOrder),
                  if (_totalItems > 1) ...[
                    const SizedBox(height: 4),
                    Text('($_totalItems items in this contract)', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF6366F1), fontWeight: FontWeight.w600)),
                  ],
                ])),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Total Value', style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text('\$${_formatNumber(_totalValue)}', style: GoogleFonts.cairo(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))),
                ]),
              ]),
              const SizedBox(height: 16),
              _buildProgressSummary(),
            ]),
          ),
          const SizedBox(height: 24),
          // Stats Cards
          Row(children: [
            _buildStatCard('Total Items', '$_totalItems', Icons.inventory_2, Colors.blue),
            const SizedBox(width: 16),
            _buildStatCard('Total QTY', _totalQuantity.toStringAsFixed(0), Icons.numbers, Colors.orange),
            const SizedBox(width: 16),
            _buildStatCard('Avg Value', '\$${_formatNumber(_totalItems > 0 ? _totalValue / _totalItems : 0)}', Icons.attach_money, Colors.green),
          ]),
          const SizedBox(height: 24),
          // Items List
          Text('Contract Items', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A))),
          const SizedBox(height: 12),
          ..._relatedOrders.map((order) => _buildOrderCard(order)),
          // Summary Footer
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF0F172A), Color(0xFF1E293B)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Contract Summary', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white70)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: _buildSummaryItem('Items', '$_totalItems', Icons.inventory_2)),
                Expanded(child: _buildSummaryItem('Total QTY', _totalQuantity.toStringAsFixed(0), Icons.numbers)),
                Expanded(child: _buildSummaryItem('Total Value', '\$${_formatNumber(_totalValue)}', Icons.attach_money)),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildProgressSummary() {
    final completedJobs = _itemJobs.where((j) => j.status == 'completed').length;
    final inProgressJobs = _itemJobs.where((j) => j.status == 'in_progress').length;
    final pendingJobs = _itemJobs.where((j) => j.status == 'pending').length;
    final totalJobs = _itemJobs.length;
    final progress = totalJobs > 0 ? (completedJobs / totalJobs * 100).round() : 0;

    if (_itemJobs.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.withOpacity(0.2))),
        child: Row(children: [
          Icon(Icons.info_outline, size: 20, color: Colors.grey[600]), const SizedBox(width: 12),
          Text('No work assigned yet', style: GoogleFonts.cairo(fontSize: 14, color: Colors.grey[600])),
        ]),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('Work Progress', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))),
          const Spacer(),
          Text('$progress%', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.bold, color: const Color(0xFF6366F1))),
        ]),
        const SizedBox(height: 8),
        ClipRRect(borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator(value: progress / 100, backgroundColor: Colors.grey.withOpacity(0.2), valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF6366F1)), minHeight: 8)),
        const SizedBox(height: 12),
        Row(children: [
          _buildProgressBadge('Completed', completedJobs, Colors.green),
          const SizedBox(width: 12),
          _buildProgressBadge('In Progress', inProgressJobs, Colors.blue),
          const SizedBox(width: 12),
          _buildProgressBadge('Pending', pendingJobs, Colors.orange),
        ]),
      ]),
    );
  }

  Widget _buildProgressBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)), const SizedBox(width: 4),
        Text('$count $label', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ]),
    );
  }

  Widget _buildOrderCard(SAPMainOrder order) {
    final job = _getJobForItem(order.productCode);
    final status = _getItemStatus(order.productCode);
    final employee = job != null ? _employeeCache[job.employeeId] : null;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: const Color(0xFFE2E8F0))),
      child: InkWell(
        onTap: job != null && employee != null ? () => Navigator.push(context, MaterialPageRoute(builder: (context) => EmployeeProfilePage(employee: employee))) : null,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: const Color(0xFF0F172A).withOpacity(0.05), borderRadius: BorderRadius.circular(4)), child: Text('#${order.itemNumber}', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A)))),
              const SizedBox(width: 10),
              Expanded(child: Text(order.description, style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF0F172A)), maxLines: 2, overflow: TextOverflow.ellipsis)),
              Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: _getStatusColor(status).withOpacity(0.1), borderRadius: BorderRadius.circular(20), border: Border.all(color: _getStatusColor(status).withOpacity(0.3))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(_getStatusIcon(status), size: 14, color: _getStatusColor(status)), const SizedBox(width: 4), Text(_getStatusLabel(status), style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: _getStatusColor(status)))])),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              _buildItemDetailChip(Icons.qr_code, order.productCode),
              const SizedBox(width: 8),
              _buildItemDetailChip(Icons.inventory, '${order.quantity} ${order.unitOfMeasure}'),
              const SizedBox(width: 8),
              _buildItemDetailChip(Icons.attach_money, '\$${_formatNumber(order.value)}'),
              const SizedBox(width: 8),
              _buildItemDetailChip(Icons.factory, order.factory ?? 'N/A'),
            ]),
            // Employee info
            Row(children: [
              _buildItemDetailChip(Icons.person, order.salesEngineer),
              const SizedBox(width: 8),
              if (order.responsibleEngineer != null && order.responsibleEngineer!.isNotEmpty)
                _buildItemDetailChip(Icons.engineering, order.responsibleEngineer!),
              const SizedBox(width: 8),
              if (order.reviewer != null && order.reviewer!.isNotEmpty)
                _buildItemDetailChip(Icons.rate_review, order.reviewer!),
            ]),
            if (job != null) ...[
              const Divider(height: 20),
              Row(children: [
                CircleAvatar(radius: 14, backgroundColor: _getStatusColor(job.status), child: Text(job.employeeName.isNotEmpty ? job.employeeName[0].toUpperCase() : '?', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                const SizedBox(width: 8),
                Expanded(child: Text(job.employeeName, style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600))),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: const Color(0xFF0F172A).withOpacity(0.05), borderRadius: BorderRadius.circular(4)), child: Text(job.stageName, style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600))),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _buildItemDetailChip(IconData icon, String text) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: Colors.grey.withOpacity(0.05), borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.withOpacity(0.1))), child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 12, color: Colors.grey[600]), const SizedBox(width: 3), Text(text, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w500, color: const Color(0xFF475569)))]));
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(children: [SizedBox(width: 100, child: Text(label, style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF64748B), fontWeight: FontWeight.w600))), Expanded(child: Text(value, style: GoogleFonts.cairo(fontSize: 14, color: const Color(0xFF0F172A), fontWeight: FontWeight.w500)))]);
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Expanded(child: Container(padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE2E8F0))), child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [Icon(icon, size: 18, color: color), const SizedBox(height: 8), Text(value, style: GoogleFonts.cairo(fontSize: 22, fontWeight: FontWeight.bold, color: const Color(0xFF0F172A))), Text(label, style: GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF64748B), fontWeight: FontWeight.w500))])));
  }

  Widget _buildSummaryItem(String label, String value, IconData icon) {
    return Column(children: [Icon(icon, size: 20, color: Colors.white54), const SizedBox(height: 4), Text(value, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)), Text(label, style: GoogleFonts.cairo(fontSize: 11, color: Colors.white54))]);
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