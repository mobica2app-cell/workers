// lib/pages/orders_page.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/employee_managment_page.dart';
import 'package:mobitem/pages/product_tracking_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/employee_model.dart';
import '../models/product_tracking_model.dart';
import '../services/csv_export_service.dart';
import '../services/employee_service.dart';
import '../services/sap_service.dart';
import 'excel_dialog.dart';
import 'order_detail_page.dart';
import 'package:flutter/services.dart';

class OrdersPage extends StatefulWidget {
  final SAPMainService sapService;
  final EmployeeAuth? loggedInEmployee;

  const OrdersPage({
    super.key,
    required this.sapService,
    this.loggedInEmployee,
  });

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  // Data - Using SAPMainOrder instead of SAPOrderHeader
  List<SAPMainOrder> _allOrders = [];
  bool _isLoading = false;
  String _searchQuery = '';
  String? _filterDesignTeam;
  String _sortBy =
      'default'; // 'default', 'value_asc', 'value_desc', 'date_asc', 'date_desc'

  // Fast O(1) Lookups & Pre-computed Lists
  Map<SAPMainOrder, int> _orderIndexMap = {};
  List<dynamic> _flatList = [];

  // Controllers
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _horizontalScrollController = ScrollController();
  final ScrollController _leftVerticalScrollController = ScrollController();
  final ScrollController _rightVerticalScrollController = ScrollController();
  bool _isSyncing = false;

  List<EmployeeAuth> _allEmployees = [];

  // Selection
  final Set<int> _selectedRows = {};

  // Services
  final EmployeeService _employeeService = EmployeeService();
  final ProductTrackingService _trackingService = ProductTrackingService();

  // Caches
  Map<String, ProductTracking> _allTrackingCache = {};
  Map<String, List<JobAssignment>> _jobsCache = {};
  Map<String, Employee?> _employeeCache = {};

  // Filters
  String? _filterStatus;
  String? _filterFactory;
  String? _filterContractNumber;
  String? _filterDesignOrder;
  String? _filterSalesEngineer;
  String? _filterResponsibleEngineer;
  String? _filterReviewer;
  String? _filterCorrespondenceEngineer;
  List<String> _sortedStatuses = [];

  int? _lastSelectedIndex;

  // Expandable sections
  final Set<String> _expandedSections = {};
  Map<String, List<SAPMainOrder>> _groupedOrders = {};

  static const List<String> _allStatuses = [
    'مطلوب اكوادها الاسترشاديه',
    'تحت المراجعة',
    'Drawing Submittal',
    'modifications submitted',
    'Approval',
    'Manufacturing Drawing',
    'Review',
    'Master Data',
    'Sales',
    'As Built',
    'Tasks',
    'planning',
    'partation  master data',
    'Done',
    'الادارة الهندسه',
    'design studio',
    'Unknown',
    'pending',
    'in_progress',
    'completed',
    'on_hold',
  ];

  static const List<String> _allTeamStatuses = [
    'تصميم المنتجات',
    'imos team',
    'partition division',
    'product division',
    'الادارة الهندسة',
    'Master Data division',
    'design studio',
    'تفصيل مصنع',
    'Chair & Sofa Division',
    'sometimes',
    'purch',
    'cladding division',
    'Unknown',
  ];

  String _getSortLabel() {
    switch (_sortBy) {
      case 'value_asc':
        return 'Value ↑';
      case 'value_desc':
        return 'Value ↓';
      case 'date_asc':
        return 'Date ↑';
      case 'date_desc':
        return 'Date ↓';
      default:
        return 'Sort';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadAllDataOnce();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _leftVerticalScrollController.dispose();
    _rightVerticalScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Check if user can import/delete (admin role or specific username)
  bool get _canImportDelete {
    final role = widget.loggedInEmployee?.role?.toLowerCase() ?? '';
    final username = widget.loggedInEmployee?.username?.toLowerCase() ?? '';
    return role == 'admin' || role == 'software head' || role == 'head' || username == 'abd.elmoen';
  }

  Future<void> _updateOrderDesignTeam(
    SAPMainOrder order,
    String newValue,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('sap_main_orders')
          .update({'design_team': newValue})
          .eq('id', order.id);

      _showSnackBar('Design team updated!');
      _loadAllDataOnce();
    } catch (e) {
      _showSnackBar('Error updating: $e');
    }
  }

  // ==================== SCROLL SYNC ====================
  bool _onLeftScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification && !_isSyncing) {
      if (_rightVerticalScrollController.hasClients) {
        _isSyncing = true;
        _rightVerticalScrollController.jumpTo(
          _leftVerticalScrollController.offset,
        );
        _isSyncing = false;
      }
    }
    return false;
  }

  bool _onRightScrollNotification(ScrollNotification notification) {
    if (notification is ScrollUpdateNotification && !_isSyncing) {
      if (_leftVerticalScrollController.hasClients) {
        _isSyncing = true;
        _leftVerticalScrollController.jumpTo(
          _rightVerticalScrollController.offset,
        );
        _isSyncing = false;
      }
    }
    return false;
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

  // ==================== DATA LOADING ====================
  Future<void> _loadAllDataOnce() async {
    setState(() => _isLoading = true);
    try {
      final allTrackings = await _trackingService.getAllProductTracking();
      _allTrackingCache = {};
      for (var t in allTrackings) {
        _allTrackingCache[t.productCode.toLowerCase().trim()] = t;
      }

      final allJobs = await _employeeService.getAllJobs();
      _jobsCache = {};
      for (var job in allJobs) {
        _jobsCache.putIfAbsent(job.productCode, () => []).add(job);
        if (!_employeeCache.containsKey(job.employeeId)) {
          _employeeCache[job.employeeId] = await _employeeService
              .getEmployeeById(job.employeeId);
        }
      }

      // Load employees from employees_auth table
      final supabase = Supabase.instance.client;
      final employeeAuthService = EmployeeAuthService(supabase);
      _allEmployees = await employeeAuthService.getAllEmployees();

      final allOrders = await widget.sapService.getAllOrders();
      setState(() {
        _allOrders = allOrders;
        _orderIndexMap = {
          for (int i = 0; i < allOrders.length; i++) allOrders[i]: i,
        };
        _initialLoadDone = true;
        _isLoading = false;
        _rebuildGroups();
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  // Update engineer assignment in database
  Future<void> _updateOrderEngineer(
    SAPMainOrder order,
    String field,
    String? newValue,
  ) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('sap_main_orders')
          .update({field: newValue})
          .eq('id', order.id);

      _showSnackBar('Updated successfully!');
      _loadAllDataOnce(); // Reload all data
    } catch (e) {
      _showSnackBar('Error updating: $e');
    }
  }

  bool _initialLoadDone = false;

  void _rebuildGroups() {
    final filtered = _getFilteredOrders();
    _groupedOrders = {};
    for (var order in filtered) {
      final status = order.status;
      _groupedOrders.putIfAbsent(status, () => []).add(order);
    }
    _sortedStatuses = _groupedOrders.keys.toList()
      ..sort(
        (a, b) =>
            _groupedOrders[b]!.length.compareTo(_groupedOrders[a]!.length),
      );
    _rebuildFlatList();
  }

  void _rebuildFlatList() {
    final list = <dynamic>[];
    for (var status in _sortedStatuses) {
      list.add(status);
      if (_expandedSections.contains(status))
        list.addAll(_groupedOrders[status]!);
    }
    setState(() => _flatList = list);
  }

  void _toggleSection(String status) {
    if (_expandedSections.contains(status)) {
      _expandedSections.remove(status);
    } else {
      _expandedSections.add(status);
    }
    _rebuildFlatList();
  }

  // ==================== HELPERS ====================
  String _getProductStatus(String? productCode) {
    if (productCode == null || productCode.isEmpty) return 'Unknown';
    if (_jobsCache.containsKey(productCode))
      return _jobsCache[productCode]!.first.status;
    final lower = productCode.toLowerCase().trim();
    if (_allTrackingCache.containsKey(lower))
      return _allTrackingCache[lower]!.section;
    return 'Unknown';
  }

  String _getProductEmployee(String? productCode) {
    if (productCode == null || productCode.isEmpty) return '-';
    if (_jobsCache.containsKey(productCode))
      return _jobsCache[productCode]!.first.employeeName;
    return '-';
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'مطلوب اكوادها الاسترشاديه':
        return Colors.blue;
      case 'تحت المراجعة':
        return Colors.orange;
      case 'Drawing Submittal':
        return Colors.purple;
      case 'modifications submitted':
        return Colors.teal;
      case 'Approval':
        return Colors.green;
      case 'Manufacturing Drawing':
        return Colors.indigo;
      case 'Review':
        return Colors.amber;
      case 'Master Data':
        return Colors.cyan;
      case 'Sales':
        return Colors.deepOrange;
      case 'As Built':
        return Colors.brown;
      case 'Tasks':
        return Colors.lime;
      case 'planning':
        return Colors.pink;
      case 'partation  master data':
        return Colors.deepPurple;
      case 'Done':
        return Colors.green;
      case 'الادارة الهندسه':
        return Colors.blueGrey;
      case 'design studio':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'on_hold':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // Add this method to _OrdersPageState class
  Future<void> _deleteSelectedOrders() async {
    if (_selectedRows.isEmpty) {
      _showSnackBar('No orders selected');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete Orders', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
        content: Text(
          'Are you sure you want to delete ${_selectedRows.length} selected orders?\n\nThis action cannot be undone.',
          style: GoogleFonts.cairo(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('Delete ${_selectedRows.length} orders', style: GoogleFonts.cairo(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    final supabase = Supabase.instance.client;
    int deleted = 0;
    int failed = 0;

    for (var index in _selectedRows.toList()) {
      if (index < _allOrders.length) {
        final order = _allOrders[index];
        try {
          await supabase.from('sap_main_orders').delete().eq('id', order.id);
          deleted++;
        } catch (e) {
          failed++;
          print('Failed to delete ${order.id}: $e');
        }
      }
    }

    setState(() => _isLoading = false);
    _clearSelection();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '✅ $deleted deleted, ❌ $failed failed',
            style: GoogleFonts.cairo(),
          ),
          backgroundColor: deleted > 0 ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }

    _loadAllDataOnce();
  }

  // Add this method in the _OrdersPageState class
  // Update order status in database and locally
  Future<void> _updateOrderStatus(SAPMainOrder order, String newStatus) async {
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('sap_main_orders')
          .update({'status': newStatus})
          .eq('id', order.id);

      // Find and update the order in the local list
      final index = _orderIndexMap[order];
      if (index != null && index < _allOrders.length) {
        // Create a new SAPMainOrder with updated status
        final updatedOrder = SAPMainOrder(
          id: order.id,
          status: newStatus,
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
          deliveryDate: order.deliveryDate,
          factory: order.factory,
          designTeam: order.designTeam,
          responsibleEngineer: order.responsibleEngineer,
          reviewer: order.reviewer,
          correspondenceEngineer: order.correspondenceEngineer,
          createdAt: order.createdAt,
        );

        setState(() {
          _allOrders[index] = updatedOrder;
          // Update the index map
          _orderIndexMap.remove(order);
          _orderIndexMap[updatedOrder] = index;
        });
      }

      _rebuildGroups();
    } catch (e) {
      _showSnackBar('Error updating status: $e');
    }
  }

  // Add this method
  void _applySorting(List<SAPMainOrder> orders) {
    switch (_sortBy) {
      case 'value_asc':
        orders.sort((a, b) => a.value.compareTo(b.value));
        break;
      case 'value_desc':
        orders.sort((a, b) => b.value.compareTo(a.value));
        break;
      case 'date_asc':
        orders.sort((a, b) {
          final aDate = a.orderDate ?? '0000-00-00';
          final bDate = b.orderDate ?? '0000-00-00';
          return aDate.compareTo(bDate);
        });
        break;
      case 'date_desc':
        orders.sort((a, b) {
          final aDate = a.orderDate ?? '0000-00-00';
          final bDate = b.orderDate ?? '0000-00-00';
          return bDate.compareTo(aDate);
        });
        break;
      default:
        break; // Keep default order
    }
  }

  String _getStatusLabel(String status) {
    if (status.length > 20) return '${status.substring(0, 18)}...';
    return status;
  }

  List<SAPMainOrder> _getFilteredOrders() {
    var result = _allOrders;
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase().trim();
      result = result.where((o) => o.contractNumber.toLowerCase().contains(q) || o.customerName.toLowerCase().contains(q)).toList();
    }
    if (_filterStatus != null) result = result.where((o) => o.status == _filterStatus).toList();
    if (_filterFactory != null) result = result.where((o) => o.factory == _filterFactory).toList();
    if (_filterDesignTeam != null) result = result.where((o) => o.designTeam == _filterDesignTeam).toList();
    if (_filterContractNumber != null) result = result.where((o) => o.contractNumber.toLowerCase().contains(_filterContractNumber!.toLowerCase())).toList();
    if (_filterDesignOrder != null) result = result.where((o) => o.designOrder.toLowerCase().contains(_filterDesignOrder!.toLowerCase())).toList();
    if (_filterSalesEngineer != null) result = result.where((o) => o.salesEngineer == _filterSalesEngineer).toList();
    if (_filterResponsibleEngineer != null) result = result.where((o) => o.responsibleEngineer == _filterResponsibleEngineer).toList();
    if (_filterReviewer != null) result = result.where((o) => o.reviewer == _filterReviewer).toList();
    if (_filterCorrespondenceEngineer != null) result = result.where((o) => o.correspondenceEngineer == _filterCorrespondenceEngineer).toList();
    _applySorting(result);
    return result;
  }

  bool get _hasActiveFilters =>
      _filterStatus != null || _filterFactory != null || _filterDesignTeam != null ||
          _filterContractNumber != null || _filterDesignOrder != null ||
          _filterSalesEngineer != null || _filterResponsibleEngineer != null ||
          _filterReviewer != null || _filterCorrespondenceEngineer != null;

  Future<void> _showImportDialog() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          ImportExcelDialog(onImportComplete: () => _loadAllDataOnce()),
    );
  }

  void _toggleRowSelection(int index) {
    setState(() {
      // Check if Shift key is pressed (for range selection)
      final isShiftPressed = RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          RawKeyboard.instance.keysPressed.contains(LogicalKeyboardKey.shiftRight);

      if (isShiftPressed && _lastSelectedIndex != null) {
        // Range selection: select all rows between last selected and current
        final start = _lastSelectedIndex! < index ? _lastSelectedIndex! : index;
        final end = _lastSelectedIndex! < index ? index : _lastSelectedIndex!;

        for (int i = start; i <= end; i++) {
          _selectedRows.add(i);
        }
      } else {
        // Normal toggle
        if (_selectedRows.contains(index)) {
          _selectedRows.remove(index);
        } else {
          _selectedRows.add(index);
        }
        _lastSelectedIndex = index;
      }
    });
  }

  void _selectAllInSection(String status) {
    setState(() {
      final sectionOrders = _groupedOrders[status] ?? [];
      if (sectionOrders.isEmpty) return;
      final allSelected = sectionOrders.every(
        (o) => _selectedRows.contains(_orderIndexMap[o] ?? -1),
      );
      if (allSelected) {
        for (var o in sectionOrders) {
          final idx = _orderIndexMap[o];
          if (idx != null) _selectedRows.remove(idx);
        }
      } else {
        for (var o in sectionOrders) {
          final idx = _orderIndexMap[o];
          if (idx != null) _selectedRows.add(idx);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedRows.clear();
      _lastSelectedIndex = null;
    });
  }

  List<SAPMainOrder> _getSelectedOrders() =>
      _selectedRows.map((i) => _allOrders[i]).toList();

  Future<void> _exportSelectedOrders() async {
    if (_selectedRows.isEmpty) {
      _showSnackBar('No orders selected');
      return;
    }
    final selected = _getSelectedOrders();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Export Selected',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${selected.length} orders',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildExportOption(
                    Icons.save_alt,
                    'Save',
                    'Save to device',
                    const Color(0xFF059669),
                    () async {
                      Navigator.pop(ctx);
                      await _saveOrders(selected, 'Selected');
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.cairo()),
          ),
        ],
      ),
    );
  }

  Future<void> _saveOrders(List<SAPMainOrder> orders, String prefix) async {
    try {
      final path = await CSVExportService.saveCSVFileMain(
        orders,
        '${prefix}_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}',
      );
      _showSnackBar('✅ Saved: $path');
    } catch (e) {
      _showSnackBar('Error: $e');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message, style: GoogleFonts.cairo()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: message.contains('Error')
              ? Colors.red
              : Colors.green,
        ),
      );
    }
  }

  void _navigateToEmployeeManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const EmployeeManagementPage()),
    ).then((_) => _loadAllDataOnce());
  }

  void _showOrderDetails(SAPMainOrder order) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OrderDetailPage(order: order, sapService: widget.sapService),
      ),
    );
  }

  void _showFilterDialog() {
    String? tempStatus = _filterStatus;
    String? tempFactory = _filterFactory;
    String? tempDesignTeam = _filterDesignTeam;
    String? tempContractNumber = _filterContractNumber;
    String? tempDesignOrder = _filterDesignOrder;
    String? tempSalesEngineer = _filterSalesEngineer;
    String? tempResponsibleEngineer = _filterResponsibleEngineer;
    String? tempReviewer = _filterReviewer;
    String? tempCorrespondenceEngineer = _filterCorrespondenceEngineer;

    // Get unique values from data
    final factories = <String>{};
    final designTeams = <String>{};
    final salesEngineers = <String>{};
    final responsibleEngineers = <String>{};
    final reviewers = <String>{};
    final correspondenceEngineers = <String>{};

    for (var order in _allOrders) {
      if (order.factory != null && order.factory!.isNotEmpty) factories.add(order.factory!);
      if (order.designTeam != null && order.designTeam!.isNotEmpty) designTeams.add(order.designTeam!);
      if (order.salesEngineer.isNotEmpty) salesEngineers.add(order.salesEngineer);
      if (order.responsibleEngineer != null && order.responsibleEngineer!.isNotEmpty) responsibleEngineers.add(order.responsibleEngineer!);
      if (order.reviewer != null && order.reviewer!.isNotEmpty) reviewers.add(order.reviewer!);
      if (order.correspondenceEngineer != null && order.correspondenceEngineer!.isNotEmpty) correspondenceEngineers.add(order.correspondenceEngineer!);
    }

    final contractCtrl = TextEditingController(text: _filterContractNumber);
    final designOrderCtrl = TextEditingController(text: _filterDesignOrder);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(children: [
            const Icon(Icons.filter_list, color: Color(0xFF0F172A), size: 22),
            const SizedBox(width: 8),
            Text('Filter Orders', style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 18)),
            const Spacer(),
            if (tempStatus != null || tempFactory != null || tempDesignTeam != null ||
                tempContractNumber != null || tempSalesEngineer != null ||
                tempResponsibleEngineer != null || tempReviewer != null ||
                tempCorrespondenceEngineer != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFF6366F1).withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                child: Text('Active', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1))),
              ),
          ]),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // ===== ORDER INFO =====
                _buildFilterSection('📋 Order Information', children: [
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: contractCtrl,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Contract Number',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          hintText: 'e.g. 9100035288',
                          hintStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                          prefixIcon: const Icon(Icons.description, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (v) => tempContractNumber = v.isEmpty ? null : v,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: designOrderCtrl,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Design Order',
                          labelStyle: GoogleFonts.cairo(fontSize: 12),
                          hintText: 'e.g. 20083982',
                          hintStyle: GoogleFonts.cairo(fontSize: 11, color: Colors.grey),
                          prefixIcon: const Icon(Icons.receipt, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onChanged: (v) => tempDesignOrder = v.isEmpty ? null : v,
                      ),
                    ),
                  ]),
                ]),
                const SizedBox(height: 16),

                // ===== STATUS & DEPARTMENT =====
                _buildFilterSection('📊 Status & Department', children: [
                  Row(children: [
                    Expanded(
                      child: _buildFilterDropdown('Status', tempStatus, ['All', ..._allStatuses], (v) => setDlg(() => tempStatus = v)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFilterDropdown('Factory (${factories.length})', tempFactory, ['All', ...factories.toList()..sort()], (v) => setDlg(() => tempFactory = v)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  _buildFilterDropdown('Design Team (${designTeams.length})', tempDesignTeam, ['All', ...designTeams.toList()..sort()], (v) => setDlg(() => tempDesignTeam = v)),
                ]),
                const SizedBox(height: 16),

                // ===== ENGINEERS =====
                _buildFilterSection('👨‍💼 Employee', children: [
                  Row(children: [
                    Expanded(
                      child: _buildFilterDropdown('Sales Eng. (${salesEngineers.length})', tempSalesEngineer, ['All', ...salesEngineers.toList()..sort()], (v) => setDlg(() => tempSalesEngineer = v)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFilterDropdown('Resp. Eng. (${responsibleEngineers.length})', tempResponsibleEngineer, ['All', ...responsibleEngineers.toList()..sort()], (v) => setDlg(() => tempResponsibleEngineer = v)),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: _buildFilterDropdown('Reviewer (${reviewers.length})', tempReviewer, ['All', ...reviewers.toList()..sort()], (v) => setDlg(() => tempReviewer = v)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildFilterDropdown('Alt. Eng. (${correspondenceEngineers.length})', tempCorrespondenceEngineer, ['All', ...correspondenceEngineers.toList()..sort()], (v) => setDlg(() => tempCorrespondenceEngineer = v)),
                    ),
                  ]),
                ]),
              ]),
            ),
          ),
          actions: [
            Row(children: [
              TextButton(
                onPressed: () {
                  setDlg(() {
                    tempStatus = null; tempFactory = null; tempDesignTeam = null;
                    tempContractNumber = null; tempDesignOrder = null;
                    tempSalesEngineer = null; tempResponsibleEngineer = null;
                    tempReviewer = null; tempCorrespondenceEngineer = null;
                    contractCtrl.clear(); designOrderCtrl.clear();
                  });
                },
                child: Row(children: [const Icon(Icons.clear_all, size: 16, color: Colors.red), const SizedBox(width: 4), Text('Clear All', style: GoogleFonts.cairo(color: Colors.red, fontSize: 13))]),
              ),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: GoogleFonts.cairo(fontSize: 13))),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _filterStatus = tempStatus;
                    _filterFactory = tempFactory;
                    _filterDesignTeam = tempDesignTeam;
                    _filterContractNumber = tempContractNumber;
                    _filterDesignOrder = tempDesignOrder;
                    _filterSalesEngineer = tempSalesEngineer;
                    _filterResponsibleEngineer = tempResponsibleEngineer;
                    _filterReviewer = tempReviewer;
                    _filterCorrespondenceEngineer = tempCorrespondenceEngineer;
                  });
                  _rebuildGroups();
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.check, size: 18),
                label: Text('Apply Filters', style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 13)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0F172A),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }

// Helper widget for filter sections
  Widget _buildFilterSection(String title, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: const Color(0xFF0F172A))),
        const SizedBox(height: 10),
        ...children,
      ]),
    );
  }

// Helper widget for filter dropdowns
  Widget _buildFilterDropdown(String label, String? value, List<String> items, Function(String?) onChanged) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      style: GoogleFonts.cairo(fontSize: 13),
      items: items.map((s) => DropdownMenuItem(
        value: s == 'All' ? null : s,
        child: Text(s == 'All' ? 'All' : s, style: GoogleFonts.cairo(fontSize: 12), overflow: TextOverflow.ellipsis),
      )).toList(),
      onChanged: (v) => onChanged(v),
    );
  }
  // ==================== BUILD ====================
  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _clearSelection,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderRow(),
                    const SizedBox(height: 16),
                    if (_selectedRows.isNotEmpty) _buildSelectionToolbar(),
                    Expanded(child: _buildTableContainer()),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    // Check if user is admin/head
    final isAdmin =
        widget.loggedInEmployee?.role?.toLowerCase() == 'admin' ||
        widget.loggedInEmployee?.role?.toLowerCase() == 'software head' ||
        widget.loggedInEmployee?.role?.toLowerCase() == 'head';

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Text(
            'Orders',
            style: GoogleFonts.cairo(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF0F172A),
            ),
          ),
          if (_selectedRows.isNotEmpty) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_selectedRows.length} selected',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF6366F1),
                ),
              ),
            ),
            TextButton(
              onPressed: _clearSelection,
              child: Text(
                'Clear',
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  color: const Color(0xFF64748B),
                ),
              ),
            ),
          ],
          const Spacer(),
          // Only show people icon for admin/head users
          if (isAdmin)
            _buildIconBtn(Icons.people_outline, _navigateToEmployeeManagement),
        ],
      ),
    );
  }

  // Employee dropdown cell widget
  Widget _employeeDropdownCell(
    String? currentValue,
    SAPMainOrder order,
    String field,
  ) {
    final displayName = currentValue ?? 'Select...';
    final hasValue = currentValue != null && currentValue.isNotEmpty;

    return SizedBox(
      width: field == 'responsible_engineer' ? 130 : 120,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: PopupMenuButton<String>(
          onSelected: (newValue) {
            final valueToSave = newValue.isEmpty ? null : newValue;
            _updateOrderEngineer(order, field, valueToSave);
          },
          offset: const Offset(0, 40),
          position: PopupMenuPosition.under,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: hasValue
                  ? const Color(0xFF6366F1).withOpacity(0.05)
                  : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hasValue
                    ? const Color(0xFF6366F1).withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    hasValue ? displayName : '-',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: hasValue ? const Color(0xFF0F172A) : Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 12,
                  color: hasValue ? const Color(0xFF6366F1) : Colors.grey,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => [
            // Clear option
            PopupMenuItem<String>(
              value: '',
              child: Row(
                children: [
                  const Icon(Icons.clear, size: 14, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'Clear',
                    style: GoogleFonts.cairo(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            // Employee list
            ..._allEmployees.map((emp) {
              final isSelected = currentValue == emp.fullName;
              return PopupMenuItem<String>(
                value: emp.fullName,
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 12,
                      backgroundColor: Colors.blue.withOpacity(0.2),
                      child: Text(
                        emp.initials,
                        style: GoogleFonts.cairo(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            emp.fullName,
                            style: GoogleFonts.cairo(
                              fontSize: 12,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: isSelected
                                  ? const Color(0xFF6366F1)
                                  : const Color(0xFF334155),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (emp.role != null)
                            Text(
                              emp.role!,
                              style: GoogleFonts.cairo(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (isSelected)
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: Color(0xFF6366F1),
                      ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Use Wrap for screens narrower than 1200px
        final isWide = constraints.maxWidth > 1100;

        if (isWide) {
          return Row(children: [
            Expanded(child: _buildHeaderInfo()),
            _buildSearchField(),
            const SizedBox(width: 8),
            _buildSortButton(),
            const SizedBox(width: 12),
            _buildActionBtn(Icons.filter_list, 'Filters', _showFilterDialog),
            const SizedBox(width: 8),
            _buildActionBtn(Icons.download, 'Export', () async {
              if (_allOrders.isNotEmpty) await _saveOrders(_allOrders, 'Orders');
            }),
            // Only show Import for admin or abd.elmoen
            if (_canImportDelete) ...[
              const SizedBox(width: 8),
              _buildImportButton(),
            ],
            const SizedBox(width: 8),
            _buildRefreshButton(),
          ]);
        } else {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeaderInfo(),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _buildSearchField(),
              _buildSortButton(),
              _buildActionBtn(Icons.filter_list, 'Filters', _showFilterDialog),
              _buildActionBtn(Icons.download, 'Export', () async {
                if (_allOrders.isNotEmpty) await _saveOrders(_allOrders, 'Orders');
              }),
              // Only show Import for admin or abd.elmoen
              if (_canImportDelete) _buildImportButton(),
              _buildRefreshButton(),
            ]),
          ]);
        }
      },
    );
  }

// Header info (record count + filters)
  Widget _buildHeaderInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total: ${_allOrders.length} records',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF45464D)),
        ),
        if (_searchQuery.isNotEmpty)
          Text(
            'Filtered: "$_searchQuery"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(fontSize: 10, color: const Color(0xFF6366F1)),
          ),
        if (_hasActiveFilters)
          GestureDetector(
            onTap: () {
              setState(() {
                _filterStatus = null; _filterFactory = null; _filterDesignTeam = null;
                _filterContractNumber = null; _filterDesignOrder = null;
                _filterSalesEngineer = null; _filterResponsibleEngineer = null;
                _filterReviewer = null; _filterCorrespondenceEngineer = null;
              });
              _rebuildGroups();
            },
            child: Text(
              'Clear filters',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

// Search field
  Widget _buildSearchField() {
    return SizedBox(
      width: 260,
      child: TextField(
        controller: _searchController,
        onChanged: (v) { _searchQuery = v; _rebuildGroups(); },
        style: GoogleFonts.cairo(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search...',
          hintStyle: GoogleFonts.cairo(color: Colors.grey.shade400, fontSize: 14),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () { _searchController.clear(); _searchQuery = ''; _rebuildGroups(); })
              : null,
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF6366F1))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        ),
      ),
    );
  }

// Sort button
  Widget _buildSortButton() {
    return PopupMenuButton<String>(
      onSelected: (value) { setState(() => _sortBy = value); _rebuildGroups(); },
      tooltip: 'Sort by',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(6),
          color: _sortBy != 'default' ? const Color(0xFF6366F1).withOpacity(0.05) : Colors.white,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.sort, size: 16, color: _sortBy != 'default' ? const Color(0xFF6366F1) : const Color(0xFF334155)),
          const SizedBox(width: 4),
          Text(_getSortLabel(), style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: _sortBy != 'default' ? const Color(0xFF6366F1) : const Color(0xFF334155))),
          const Icon(Icons.arrow_drop_down, size: 16),
        ]),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(value: 'default', child: Row(children: [Icon(Icons.sort, size: 16, color: _sortBy == 'default' ? const Color(0xFF6366F1) : Colors.grey), const SizedBox(width: 8), Text('Default', style: GoogleFonts.cairo(fontSize: 12, fontWeight: _sortBy == 'default' ? FontWeight.w700 : FontWeight.w400)), if (_sortBy == 'default') const Spacer(), if (_sortBy == 'default') const Icon(Icons.check, size: 16, color: Color(0xFF6366F1))])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'value_desc', child: Row(children: [Icon(Icons.arrow_downward, size: 14, color: _sortBy == 'value_desc' ? const Color(0xFF6366F1) : Colors.grey), const SizedBox(width: 8), Text('Value ↓', style: GoogleFonts.cairo(fontSize: 12, fontWeight: _sortBy == 'value_desc' ? FontWeight.w700 : FontWeight.w400)), if (_sortBy == 'value_desc') const Spacer(), if (_sortBy == 'value_desc') const Icon(Icons.check, size: 16)])),
        PopupMenuItem(value: 'value_asc', child: Row(children: [Icon(Icons.arrow_upward, size: 14, color: _sortBy == 'value_asc' ? const Color(0xFF6366F1) : Colors.grey), const SizedBox(width: 8), Text('Value ↑', style: GoogleFonts.cairo(fontSize: 12, fontWeight: _sortBy == 'value_asc' ? FontWeight.w700 : FontWeight.w400)), if (_sortBy == 'value_asc') const Spacer(), if (_sortBy == 'value_asc') const Icon(Icons.check, size: 16)])),
        const PopupMenuDivider(),
        PopupMenuItem(value: 'date_desc', child: Row(children: [Icon(Icons.calendar_today, size: 14, color: _sortBy == 'date_desc' ? const Color(0xFF6366F1) : Colors.grey), const SizedBox(width: 8), Text('Date ↓', style: GoogleFonts.cairo(fontSize: 12, fontWeight: _sortBy == 'date_desc' ? FontWeight.w700 : FontWeight.w400)), if (_sortBy == 'date_desc') const Spacer(), if (_sortBy == 'date_desc') const Icon(Icons.check, size: 16)])),
        PopupMenuItem(value: 'date_asc', child: Row(children: [Icon(Icons.calendar_today, size: 14, color: _sortBy == 'date_asc' ? const Color(0xFF6366F1) : Colors.grey), const SizedBox(width: 8), Text('Date ↑', style: GoogleFonts.cairo(fontSize: 12, fontWeight: _sortBy == 'date_asc' ? FontWeight.w700 : FontWeight.w400)), if (_sortBy == 'date_asc') const Spacer(), if (_sortBy == 'date_asc') const Icon(Icons.check, size: 16)])),
      ],
    );
  }

// Refresh button
  Widget _buildRefreshButton() {
    return ElevatedButton.icon(
      onPressed: _loadAllDataOnce,
      icon: const Icon(Icons.refresh, size: 18),
      label: Text('Refresh', style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600)),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _designTeamDropdownCell(String? currentValue, SAPMainOrder order) {
    final displayName = currentValue ?? 'Select...';
    final hasValue = currentValue != null && currentValue.isNotEmpty;

    return SizedBox(
      width: 130,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: PopupMenuButton<String>(
          onSelected: (newValue) {
            _updateOrderDesignTeam(order, newValue);
          },
          offset: const Offset(0, 40),
          position: PopupMenuPosition.under,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
            decoration: BoxDecoration(
              color: hasValue
                  ? const Color(0xFF6366F1).withOpacity(0.05)
                  : Colors.grey.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: hasValue
                    ? const Color(0xFF6366F1).withOpacity(0.2)
                    : Colors.grey.withOpacity(0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    hasValue ? displayName : '-',
                    style: GoogleFonts.cairo(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: hasValue ? const Color(0xFF0F172A) : Colors.grey,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.arrow_drop_down,
                  size: 12,
                  color: hasValue ? const Color(0xFF6366F1) : Colors.grey,
                ),
              ],
            ),
          ),
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: '',
              child: Row(
                children: [
                  const Icon(Icons.clear, size: 14, color: Colors.red),
                  const SizedBox(width: 8),
                  Text(
                    'Clear',
                    style: GoogleFonts.cairo(fontSize: 12, color: Colors.red),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            ..._allTeamStatuses.map((s) {
              final isSelected = currentValue == s;
              return PopupMenuItem<String>(
                value: s,
                child: Row(
                  children: [
                    if (isSelected)
                      const Icon(
                        Icons.check,
                        size: 16,
                        color: Color(0xFF6366F1),
                      )
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(
                      s,
                      style: GoogleFonts.cairo(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: isSelected
                            ? const Color(0xFF6366F1)
                            : const Color(0xFF334155),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildImportButton() => OutlinedButton.icon(
    onPressed: _showImportDialog,
    icon: const Icon(Icons.upload_file, size: 16),
    label: Text(
      'Import Excel',
      style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
    ),
    style: OutlinedButton.styleFrom(
      foregroundColor: const Color(0xFF059669),
      side: const BorderSide(color: Color(0xFF059669)),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      backgroundColor: Colors.white,
    ),
  );

  Widget _buildSelectionToolbar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF6366F1).withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle, size: 18, color: Color(0xFF6366F1)),
          const SizedBox(width: 8),
          Text(
            '${_selectedRows.length} selected',
            style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: const Color(0xFF6366F1)),
          ),
          const Spacer(),
          _buildSmallBtn(Icons.download, 'Export Selected', _exportSelectedOrders),
          const SizedBox(width: 8),
          // Only show Delete for admin or abd.elmoen
          if (_canImportDelete) ...[
            _buildSmallBtn(Icons.delete_outline, 'Delete', _deleteSelectedOrders),
            const SizedBox(width: 8),
          ],
          _buildSmallBtn(Icons.close, 'Clear', _clearSelection),
        ],
      ),
    );
  }

  Widget _buildTableContainer() {
    if (_isLoading && !_initialLoadDone)
      return const Center(child: CircularProgressIndicator());
    if (_allOrders.isEmpty)
      return Center(
        child: Text(
          'No orders',
          style: GoogleFonts.cairo(
            color: const Color(0xFF45464D),
            fontSize: 14,
          ),
        ),
      );
    return _buildExpandableSections();
  }

  Widget _buildExpandableSections() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 260,
            child: Column(
              children: [
                _buildNameHeader(),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: _onLeftScrollNotification,
                    child: ListView.builder(
                      controller: _leftVerticalScrollController,
                      itemCount: _flatList.length,
                      addAutomaticKeepAlives: false,
                      addRepaintBoundaries: true,
                      itemExtentBuilder: (index, details) =>
                          _flatList[index] is String ? 44.0 : 48.0,
                      itemBuilder: (_, i) {
                        final item = _flatList[i];
                        if (item is String)
                          return _buildSectionHeader(
                            item,
                            _groupedOrders[item]!,
                          );
                        final order = item as SAPMainOrder;
                        return _buildNameCell(
                          order,
                          _orderIndexMap[order] ?? 0,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) =>
                  n.metrics.axis == Axis.vertical ? true : false,
              child: Scrollbar(
                controller: _horizontalScrollController,
                thumbVisibility: true,
                trackVisibility: true,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _horizontalScrollController,
                  child: SizedBox(
                    width: 2130,
                    child: Column(
                      children: [
                        _buildColumnHeaders(),
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: _onRightScrollNotification,
                            child: ListView.builder(
                              controller: _rightVerticalScrollController,
                              itemCount: _flatList.length,
                              addAutomaticKeepAlives: false,
                              addRepaintBoundaries: true,
                              itemExtentBuilder: (index, details) =>
                                  _flatList[index] is String ? 44.0 : 48.0,
                              itemBuilder: (_, i) {
                                final item = _flatList[i];
                                if (item is String)
                                  return _buildSectionHeaderPlaceholder(
                                    item,
                                    _groupedOrders[item]!,
                                  );
                                final order = item as SAPMainOrder;
                                return _buildDataRow(
                                  order,
                                  _orderIndexMap[order] ?? 0,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String status, List<SAPMainOrder> orders) {
    final isExpanded = _expandedSections.contains(status);
    final allSelected = orders.every(
      (o) => _selectedRows.contains(_orderIndexMap[o] ?? -1),
    );
    return GestureDetector(
      onTap: () => _toggleSection(status),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _getStatusColor(status).withOpacity(0.08),
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade200),
            right: BorderSide(color: Colors.grey.shade300, width: 2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: _getStatusColor(status),
            ),
            const SizedBox(width: 6),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _getStatusLabel(status),
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _getStatusColor(status),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${orders.length}',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _getStatusColor(status),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: allSelected,
                onChanged: (v) => _selectAllInSection(status),
                activeColor: _getStatusColor(status),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeaderPlaceholder(
    String status,
    List<SAPMainOrder> orders,
  ) {
    final isExpanded = _expandedSections.contains(status);
    return GestureDetector(
      onTap: () => _toggleSection(status),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _getStatusColor(status).withOpacity(0.08),
          border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
        ),
        child: Row(
          children: [
            Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              size: 18,
              color: _getStatusColor(status),
            ),
            const SizedBox(width: 6),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: _getStatusColor(status),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              _getStatusLabel(status),
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: _getStatusColor(status),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: _getStatusColor(status).withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${orders.length}',
                style: GoogleFonts.cairo(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: _getStatusColor(status),
                ),
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }

  Widget _buildNameHeader() => Container(
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      border: Border(
        bottom: BorderSide(color: Colors.grey.shade200),
        right: BorderSide(color: Colors.grey.shade300, width: 2),
      ),
    ),
    child: Row(
      children: [
        const SizedBox(width: 24, height: 24),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Name',
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF1E293B),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildNameCell(SAPMainOrder order, int index) {
    final isSelected = _selectedRows.contains(index);
    return GestureDetector(
      onTap: () => _toggleRowSelection(index),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withOpacity(0.05)
              : Colors.white,
          border: Border(
            bottom: BorderSide(color: Colors.grey.shade50),
            right: BorderSide(color: Colors.grey.shade300, width: 2),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: isSelected,
                onChanged: (v) => _toggleRowSelection(index),
                activeColor: const Color(0xFF6366F1),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                order.customerName,
                style: GoogleFonts.cairo(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF0F172A),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColumnHeaders() => Container(
    height: 48,
    decoration: BoxDecoration(
      color: const Color(0xFFF1F5F9),
      border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
    ),
    child: Row(
      children: [
        _hdr('Status', 140), // Changed from 90 to 140
        _hdr('Item', 60),
        _hdr('Product Code', 120),
        _hdr('Contract Num', 110),
        _hdr('Description', 200),
        _hdr('Design Order', 110),
        _hdr('QTY', 70, TextAlign.right),
        _hdr('Unit', 50),
        _hdr('Value', 110, TextAlign.right),
        _hdr('Sales Engineer', 150),
        _hdr('O-Date', 100),
        _hdr('Del. Date', 100),
        _hdr('Factory', 70),
        _hdr('Design Team', 130),
        _hdr('Resp. Eng.', 130),
        _hdr('Reviewer', 120),
        _hdr('Alternative Eng.', 120),
      ],
    ),
  );

  Widget _buildDataRow(SAPMainOrder order, int index) {
    final isSelected = _selectedRows.contains(index);
    return GestureDetector(
      onTap: () => _showOrderDetails(order),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6366F1).withOpacity(0.05)
              : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade50)),
        ),
        child: Row(
          children: [
            _statusCell(order.status, order), // Changed: pass order too
            _cell(order.itemNumber, 60),
            _cell(
              order.productCode,
              120,
              style: GoogleFonts.cairo(fontSize: 11),
            ),
            _cell(order.contractNumber, 110),
            _cell(
              order.description,
              200,
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            _cell(
              order.designOrder,
              110,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6366F1),
              ),
            ),
            _cell('${order.quantity}', 70, align: TextAlign.right),
            _cell(order.unitOfMeasure, 50),
            _cell(
              _formatNumber(order.value),
              110,
              align: TextAlign.right,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF059669),
              ),
            ),
            _cell(order.salesEngineer, 150),
            _cell(order.orderDate ?? '-', 100),
            _cell(order.deliveryDate ?? '-', 100),
            _cell(order.factory ?? '-', 70),
            _designTeamDropdownCell(order.designTeam, order),
            _employeeDropdownCell(
              order.responsibleEngineer,
              order,
              'responsible_engineer',
            ),
            _employeeDropdownCell(order.reviewer, order, 'reviewer'),
            _employeeDropdownCell(
              order.correspondenceEngineer,
              order,
              'correspondence_engineer',
            ),
          ],
        ),
      ),
    );
  }

  Widget _hdr(String text, double w, [TextAlign a = TextAlign.left]) =>
      SizedBox(
        width: w,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Align(
            alignment: a == TextAlign.right
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Text(
              text,
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1E293B),
              ),
            ),
          ),
        ),
      );

  Widget _statusCell(String status, SAPMainOrder order) => SizedBox(
    width: 140, // Increased width for dropdown
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: PopupMenuButton<String>(
        onSelected: (newStatus) => _updateOrderStatus(order, newStatus),
        offset: const Offset(0, 40),
        position: PopupMenuPosition.under,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: _getStatusColor(status).withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: _getStatusColor(status).withOpacity(0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  _getStatusLabel(status),
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _getStatusColor(status),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.arrow_drop_down,
                size: 14,
                color: _getStatusColor(status),
              ),
            ],
          ),
        ),
        itemBuilder: (context) => _allStatuses.map((s) {
          return PopupMenuItem<String>(
            value: s,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: _getStatusColor(s),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  s,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: s == status
                        ? _getStatusColor(s)
                        : const Color(0xFF334155),
                    fontWeight: s == status ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (s == status) ...[
                  const Spacer(),
                  Icon(Icons.check, size: 16, color: _getStatusColor(s)),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    ),
  );

  Widget _cell(
    String text,
    double w, {
    TextAlign align = TextAlign.left,
    TextStyle? style,
    TextOverflow overflow = TextOverflow.ellipsis,
    int maxLines = 1,
  }) => SizedBox(
    width: w,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Align(
        alignment: align == TextAlign.right
            ? Alignment.centerRight
            : Alignment.centerLeft,
        child: Text(
          text,
          style:
              style ??
              GoogleFonts.cairo(fontSize: 12, color: const Color(0xFF334155)),
          overflow: overflow,
          maxLines: maxLines,
        ),
      ),
    ),
  );

  Widget _buildSmallBtn(IconData icon, String label, VoidCallback onTap) =>
      TextButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 14),
        label: Text(
          label,
          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        style: TextButton.styleFrom(
          foregroundColor: const Color(0xFF6366F1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(4),
            side: BorderSide(color: const Color(0xFF6366F1).withOpacity(0.3)),
          ),
        ),
      );

  Widget _buildIconBtn(IconData icon, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: IconButton(
      onPressed: onTap,
      icon: Icon(icon, color: const Color(0xFF45464D)),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(100)),
      ),
    ),
  );

  Widget _buildActionBtn(IconData icon, String label, VoidCallback onTap) =>
      OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        label: Text(
          label,
          style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF334155),
          side: const BorderSide(color: Color(0xFFCBD5E1)),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          backgroundColor: Colors.white,
        ),
      );

  Widget _buildExportOption(
    IconData icon,
    String label,
    String subtitle,
    Color color,
    VoidCallback onTap,
  ) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 32),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.cairo(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: const Color(0xFF64748B),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}
