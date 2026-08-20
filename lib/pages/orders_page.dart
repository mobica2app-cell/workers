// lib/pages/orders_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:mobitem/pages/employee_managment_page.dart';
import 'package:mobitem/pages/product_tracking_service.dart';
import 'package:mobitem/pages/track_order.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../main.dart';
import '../models/employee_model.dart';
import '../models/product_tracking_model.dart';
import '../services/audit_service.dart';
import '../services/csv_export_service.dart';
import '../services/employee_service.dart';
import '../services/sap_service.dart';
import 'excel_dialog.dart';
import 'order_detail_page.dart';

extension FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

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
  bool _filterMyWork = false;
  bool _editMode = false;
  String _sortBy =
      'date_asc'; // 'default', 'value_asc', 'value_desc', 'date_asc', 'date_desc'

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
  final Set<String> _selectedRowsIds = {};

  bool _isOrderSelected(SAPMainOrder order) =>
      _selectedRowsIds.contains(order.id);

  // Services
  final EmployeeService _employeeService = EmployeeService();
  final ProductTrackingService _trackingService = ProductTrackingService();

  // Caches
  Map<String, ProductTracking> _allTrackingCache = {};
  Map<String, List<JobAssignment>> _jobsCache = {};
  Map<String, Employee?> _employeeCache = {};

  String? _editingField; // Which field is being edited (orderId_field)
  final Map<String, TextEditingController> _editControllers = {};

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
    'Drawing Submittal',
    'Approval',
    'modifications submitted',
    'Manufacturing Drawing',
    'Done',
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
    'Unknown',
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

  // Add this method to check if user is admin
  bool get _isAdmin {
    final role = widget.loggedInEmployee?.role?.toLowerCase() ?? '';
    return role == 'admin' || role == 'software head' || role == 'head';
  }

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

  // Add audit service
  final AuditService _auditService = AuditService(Supabase.instance.client);

  // Helper to get current user info
  String get _currentUserName => widget.loggedInEmployee?.fullName ?? 'Unknown';

  String get _currentUserId => widget.loggedInEmployee?.id ?? '';

  // Get old value before update (from the current order object)
  String? _getCurrentFieldValue(SAPMainOrder order, String field) {
    switch (field) {
      case 'status':
        return order.status;
      case 'design_team':
        return order.designTeam;
      case 'responsible_engineer':
        return order.responsibleEngineer;
      case 'reviewer':
        return order.reviewer;
      case 'correspondence_engineer':
        return order.correspondenceEngineer;
      case 'sales_engineer':
        return order.salesEngineer;
      case 'factory':
        return order.factory;
      default:
        return null;
    }
  }

  // Check if user is from Data Entry department (can edit any row)
  bool get _isDataEntry {
    final department = widget.loggedInEmployee?.department?.toLowerCase() ?? '';
    return department == 'data entry';
  }

  // Update the _isOrderEditable method
  bool _isOrderEditable(SAPMainOrder order) {
    // Data Entry users can edit any row
    if (_isDataEntry) return true;

    // Regular users can only edit "Tasks" orders
    return order.status.toLowerCase() == 'tasks';
  }

  void _applyMyWorkFilter() {
    setState(() {
      if (_filterMyWork) {
        // Already filtered - clear it
        _filterMyWork = false;
        _filterResponsibleEngineer = null;
        _filterReviewer = null;
        _filterCorrespondenceEngineer = null;
      } else {
        // Apply my work filter
        _filterMyWork = true;
        final myName = widget.loggedInEmployee?.fullName ?? '';
        _filterResponsibleEngineer = myName;
        _filterReviewer = myName;
        _filterCorrespondenceEngineer = myName;
      }
      _rebuildGroups();
    });
  }

  // ==================== COPY FUNCTIONALITY ====================

  // Copy a specific field value to clipboard
  void _copyFieldToClipboard(String label, String value) {
    if (value.isEmpty || value == '-') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('⚠️ No data to copy', style: GoogleFonts.cairo()),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 1),
        ),
      );
      return;
    }

    Clipboard.setData(ClipboardData(text: value));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '📋 Copied: $label → "$value"',
          style: GoogleFonts.cairo(),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Copy order data to clipboard (full row)
  void _copyOrderData(SAPMainOrder order) {
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('📋 Order Details:');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Customer: ${order.customerName}');
    buffer.writeln('Design Order: ${order.designOrder}');
    buffer.writeln('Contract Number: ${order.contractNumber}');
    buffer.writeln('Item: ${order.itemNumber}');
    buffer.writeln('Product Code: ${order.productCode}');
    buffer.writeln('Description: ${order.description}');
    buffer.writeln('QTY: ${order.quantity}');
    buffer.writeln('Unit: ${order.unitOfMeasure}');
    buffer.writeln('Value: \$${_formatNumber(order.value)}');
    buffer.writeln('Status: ${order.status}');
    buffer.writeln('Sales Engineer: ${order.salesEngineer}');
    buffer.writeln('Order Date: ${order.orderDate ?? '-'}');
    buffer.writeln('End Date: ${order.endDate ?? '-'}'); // ✅ ADD THIS
    buffer.writeln('Delivery Date: ${order.deliveryDate ?? '-'}');
    buffer.writeln('Factory: ${order.factory ?? '-'}');
    buffer.writeln('Design Team: ${order.designTeam ?? '-'}');
    buffer.writeln('Resp. Engineer: ${order.responsibleEngineer ?? '-'}');
    buffer.writeln('Reviewer: ${order.reviewer ?? '-'}');
    buffer.writeln('Alt. Engineer: ${order.correspondenceEngineer ?? '-'}');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '📋 Full order data copied to clipboard',
          style: GoogleFonts.cairo(),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // Copy selected orders summary
  void _copySelectedOrdersData() {
    if (_selectedRowsIds.isEmpty) {
      _showSnackBar('No orders selected');
      return;
    }

    final selectedOrders = _allOrders
        .where((o) => _selectedRowsIds.contains(o.id))
        .toList();
    final StringBuffer buffer = StringBuffer();
    buffer.writeln('📋 Selected Orders (${selectedOrders.length}):');
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

    for (var order in selectedOrders) {
      buffer.writeln(
        '• ${order.designOrder} | ${order.customerName} | ${order.status} | \$${_formatNumber(order.value)}',
      );
    }
    buffer.writeln('━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    buffer.writeln('Total Orders: ${selectedOrders.length}');
    buffer.writeln(
      'Total Value: \$${_formatNumber(selectedOrders.fold(0.0, (sum, o) => sum + o.value))}',
    );

    Clipboard.setData(ClipboardData(text: buffer.toString()));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '📋 ${selectedOrders.length} orders copied to clipboard',
          style: GoogleFonts.cairo(),
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
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

  void _showBulkEditDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Bulk Edit',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${_selectedRowsIds.length} rows selected',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                _buildBulkEditOption('Status', 'status'),
                _buildBulkEditOption('Design Team', 'design_team'),
                _buildBulkEditOption('Factory', 'factory'),
                _buildBulkEditOption('Sales Engineer', 'sales_engineer'),
                _buildBulkEditOption('Resp. Engineer', 'responsible_engineer'),
                _buildBulkEditOption('Reviewer', 'reviewer'),
                _buildBulkEditOption(
                  'Alt. Engineer',
                  'correspondence_engineer',
                ),
                _buildBulkEditOption('Value', 'value'),
                // Add date picker options for bulk edit
                _buildBulkDateOption('O-Date', 'order_date'),
                _buildBulkDateOption('Delivery Date', 'delivery_date'),
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

  Widget _buildBulkDateOption(String label, String field) {
    return OutlinedButton(
      onPressed: () {
        Navigator.pop(context);
        _pickDateForBulkEdit(field);
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_today, size: 12),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.cairo(fontSize: 11)),
        ],
      ),
    );
  }

  Future<void> _pickDateForBulkEdit(String field) async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null) {
      final formattedDate = DateFormat('yyyy-MM-dd').format(pickedDate);
      await _applyBulkEditToSelected(field, formattedDate);
    }
  }

  Widget _buildBulkEditOption(String label, String field) {
    return OutlinedButton(
      onPressed: () {
        Navigator.pop(context);
        _bulkEditField(field, '');
      },
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      child: Text(label, style: GoogleFonts.cairo(fontSize: 11)),
    );
  }

  // Check if user can import/delete (admin role or specific username)
  bool get _canImportDelete {
    final role = widget.loggedInEmployee?.role?.toLowerCase() ?? '';
    return role == 'admin' ||
        role == 'software head' ||
        role == 'head' ||
        _isDataEntry;
  }

  // Add this method to show manual task creation dialog
  Future<void> _showAddTaskDialog() async {
    final nameController = TextEditingController();
    final contractController = TextEditingController();
    final designOrderController = TextEditingController();
    final itemController = TextEditingController();
    final productCodeController = TextEditingController();
    final descriptionController = TextEditingController();
    final qtyController = TextEditingController();
    final unitController = TextEditingController(text: 'EA');
    final valueController = TextEditingController();
    final factoryController = TextEditingController();
    final deliveryDateController = TextEditingController();

    final newOrder = await showDialog<SAPMainOrder>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Add New Task',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  style: GoogleFonts.cairo(fontSize: 13),
                  decoration: _buildInputDecoration('Customer Name'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: contractController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('Contract Number'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: designOrderController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('Design Order'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: itemController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('Item'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: productCodeController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('Product Code'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descriptionController,
                  style: GoogleFonts.cairo(fontSize: 13),
                  decoration: _buildInputDecoration('Description'),
                  maxLines: 2,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('QTY'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: unitController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('Unit'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: valueController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('Value'),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: factoryController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration('Factory'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: deliveryDateController,
                        style: GoogleFonts.cairo(fontSize: 13),
                        decoration: _buildInputDecoration(
                          'Delivery Date (YYYY-MM-DD)',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.isEmpty ||
                  designOrderController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Customer Name and Design Order are required',
                      style: GoogleFonts.cairo(),
                    ),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              final order = SAPMainOrder(
                id: '',
                status: 'Tasks',
                customerName: nameController.text.trim(),
                itemNumber: itemController.text.trim().isEmpty
                    ? '1'
                    : itemController.text.trim(),
                productCode: productCodeController.text.trim(),
                contractNumber: contractController.text.trim(),
                description: descriptionController.text.trim(),
                designOrder: designOrderController.text.trim(),
                quantity: double.tryParse(qtyController.text.replaceAll(',', '')) ?? 0,
                unitOfMeasure: unitController.text.trim().isEmpty ? 'EA' : unitController.text.trim(),
                value: double.tryParse(valueController.text.replaceAll(',', '').replaceAll('\$', ''),) ?? 0,
                salesEngineer: _currentUserName,
                orderDate: DateFormat('yyyy-MM-dd').format(DateTime.now()),
                deliveryDate: deliveryDateController.text.trim().isEmpty ? null : deliveryDateController.text.trim(),
                factory: factoryController.text.trim().isEmpty ? null : factoryController.text.trim(),
                designTeam: widget.loggedInEmployee?.department,
                responsibleEngineer: null,
                reviewer: null,
                correspondenceEngineer: null,
                createdAt: DateTime.now(),
              );

              Navigator.pop(ctx, order);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
            ),
            child: Text(
              'Add Task',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (newOrder != null) {
      setState(() => _isLoading = true);
      try {
        final supabase = Supabase.instance.client;
        final response = await supabase
            .from('sap_main_orders')
            .insert({
              'status': 'Tasks',
              'customer_name': newOrder.customerName,
              'item_number': newOrder.itemNumber,
              'product_code': newOrder.productCode,
              'contract_number': newOrder.contractNumber,
              'description': newOrder.description,
              'design_order': newOrder.designOrder,
              'quantity': newOrder.quantity,
              'unit_of_measure': newOrder.unitOfMeasure,
              'value': newOrder.value,
              'sales_engineer': newOrder.salesEngineer,
              'order_date': newOrder.orderDate,
              'delivery_date': newOrder.deliveryDate,
              'factory': newOrder.factory,
              'design_team': newOrder.designTeam,
              'responsible_engineer': newOrder.responsibleEngineer,
              'reviewer': newOrder.reviewer,
              'correspondence_engineer': newOrder.correspondenceEngineer,
            }).select().single();

        final createdOrder = SAPMainOrder.fromJson(response);

        // Add to local list
        setState(() {
          _allOrders.add(createdOrder);
          _orderIndexMap[createdOrder] = _allOrders.length - 1;
          _isLoading = false;
        });

        _rebuildGroups();
        _showSnackBar('✅ Task created successfully!');
      } catch (e) {
        setState(() => _isLoading = false);
        _showSnackBar('Error creating task: $e');
      }
    }
  }

  // Helper for input decoration
  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.cairo(fontSize: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  Future<void> _bulkEditField(String field, String currentValue) async {
    final controller = TextEditingController();

    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Bulk Edit ${_formatFieldName(field)}',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Apply to ${_selectedRowsIds.length} selected rows',
              style: GoogleFonts.cairo(
                fontSize: 13,
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              style: GoogleFonts.cairo(fontSize: 14),
              decoration: InputDecoration(
                labelText: _formatFieldName(field),
                hintText: 'Enter new value for all selected',
                border: const OutlineInputBorder(),
              ),
              keyboardType: field == 'quantity' || field == 'value'
                  ? TextInputType.number
                  : TextInputType.text,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
            ),
            child: Text(
              'Apply to ${_selectedRowsIds.length} rows',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (newValue != null && newValue.isNotEmpty) {
      setState(() => _isLoading = true);
      final supabase = Supabase.instance.client;
      int updated = 0;

      dynamic parsedValue = newValue;
      if (field == 'quantity') {
        parsedValue = double.tryParse(newValue.replaceAll(',', '')) ?? 0;
      } else if (field == 'value') {
        parsedValue =
            double.tryParse(
              newValue.replaceAll(',', '').replaceAll('\$', ''),
            ) ??
            0;
      }

      for (var orderId in _selectedRowsIds) {
        final order = _allOrders.where((o) => o.id == orderId).firstOrNull;
        if (order != null) {
          try {-
            await supabase
                .from('sap_main_orders')
                .update({field: parsedValue})
                .eq('id', order.id);

            await _auditService.logChange(
              orderId: order.id,
              designOrder: order.designOrder,
              fieldName: field,
              oldValue: _getCurrentFieldValue(order, field),
              newValue: newValue,
              changedBy: _currentUserName,
              changedById: _currentUserId,
              actionType: 'bulk_update',
            );
            updated++;
          } catch (e) {
            print('Failed to update ${order.id}: $e');
          }
        }
      }

      setState(() => _isLoading = false);
      _showSnackBar('✅ $updated rows updated!');
      _updateMultipleOrdersLocally(field, parsedValue);
    }
  }

  // Add this method for date picking
  Future<void> _pickDateForEdit(
    SAPMainOrder order,
    String field,
    String currentValue,
  ) async {
    final currentDate = DateTime.tryParse(currentValue) ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );

    if (pickedDate != null) {
      final formattedDate = DateFormat('yyyy-MM-dd').format(pickedDate);

      // If multiple rows selected, apply to all
      if (_editMode && _selectedRowsIds.length > 1) {
        await _applyBulkEditToSelected(field, formattedDate);
        return;
      }

      // Single row update
      try {
        final supabase = Supabase.instance.client;
        await supabase
            .from('sap_main_orders')
            .update({field: formattedDate})
            .eq('id', order.id);

        await _auditService.logChange(
          orderId: order.id,
          designOrder: order.designOrder,
          fieldName: field,
          oldValue: currentValue == '-' ? '' : currentValue,
          newValue: formattedDate,
          changedBy: _currentUserName,
          changedById: _currentUserId,
        );

        _showSnackBar('${_formatFieldName(field)} updated!');
        _updateOrderLocally(order.id, field, formattedDate);
      } catch (e) {
        _showSnackBar('Error updating: $e');
      }
    }
  }

  // Add this method to show an edit dialog for any field
  Future<void> _editOrderField(
    SAPMainOrder order,
    String field,
    String currentValue,
  ) async {
    // If multiple rows are selected in edit mode, apply to ALL selected rows
    if (_editMode && _selectedRowsIds.length > 1) {
      // Just call bulk edit directly
      _bulkEditField(field, currentValue);
      return;
    }

    // Single row edit (normal behavior)
    final controller = TextEditingController(text: currentValue);

    final newValue = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Edit ${_formatFieldName(field)}',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        content: TextField(
          controller: controller,
          style: GoogleFonts.cairo(fontSize: 14),
          decoration: InputDecoration(
            labelText: _formatFieldName(field),
            border: const OutlineInputBorder(),
          ),
          maxLines: field == 'description' ? 3 : 1,
          keyboardType: field == 'quantity' || field == 'value'
              ? TextInputType.number
              : TextInputType.text,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF0F172A),
            ),
            child: Text('Save', style: GoogleFonts.cairo(color: Colors.white)),
          ),
        ],
      ),
    );

    if (newValue != null && newValue != currentValue) {
      try {
        final supabase = Supabase.instance.client;
        dynamic parsedValue = newValue;

        if (field == 'quantity') {
          parsedValue = double.tryParse(newValue.replaceAll(',', '')) ?? 0;
        } else if (field == 'value') {
          parsedValue =
              double.tryParse(
                newValue.replaceAll(',', '').replaceAll('\$', ''),
              ) ??
              0;
        }

        await supabase
            .from('sap_main_orders')
            .update({field: parsedValue})
            .eq('id', order.id);

        await _auditService.logChange(
          orderId: order.id,
          designOrder: order.designOrder,
          fieldName: field,
          oldValue: currentValue,
          newValue: newValue,
          changedBy: _currentUserName,
          changedById: _currentUserId,
        );

        _showSnackBar('${_formatFieldName(field)} updated!');
        _updateOrderLocally(
          order.id,
          field,
          parsedValue,
        ); // ✅ Local update instead of reload
      } catch (e) {
        _showSnackBar('Error updating: $e');
      }
    }
  }

  // Helper to format field names nicely
  String _formatFieldName(String field) {
    switch (field) {
      case 'customer_name':
        return 'Customer Name';
      case 'contract_number':
        return 'Contract Number';
      case 'design_order':
        return 'Design Order';
      case 'item_number':
        return 'Item';
      case 'product_code':
        return 'Product Code';
      case 'description':
        return 'Description';
      case 'quantity':
        return 'QTY';
      case 'unit_of_measure':
        return 'Unit';
      case 'value':
        return 'Value';
      case 'sales_engineer':
        return 'Sales Engineer';
      case 'order_date':
        return 'O-Date';
      case 'end_date':
        return 'End Date';
      case 'delivery_date':
        return 'Delivery Date';
      case 'factory':
        return 'Factory';
      case 'design_team':
        return 'Design Team';
      case 'responsible_engineer':
        return 'Resp. Engineer';
      case 'reviewer':
        return 'Reviewer';
      case 'correspondence_engineer':
        return 'Alt. Engineer';
      case 'status':
        return 'Status';
      default:
        return field;
    }
  }

  // Update order locally without full reload
  void _updateOrderLocally(String orderId, String field, dynamic newValue) {
    setState(() {
      final index = _allOrders.indexWhere((o) => o.id == orderId);
      if (index != -1) {
        final oldOrder = _allOrders[index];
        final updatedOrder = SAPMainOrder(
          id: oldOrder.id,
          status: field == 'status' ? newValue.toString() : oldOrder.status,
          customerName: field == 'customer_name'
              ? newValue.toString()
              : oldOrder.customerName,
          itemNumber: field == 'item_number'
              ? newValue.toString()
              : oldOrder.itemNumber,
          productCode: field == 'product_code'
              ? newValue.toString()
              : oldOrder.productCode,
          contractNumber: field == 'contract_number'
              ? newValue.toString()
              : oldOrder.contractNumber,
          description: field == 'description'
              ? newValue.toString()
              : oldOrder.description,
          designOrder: field == 'design_order'
              ? newValue.toString()
              : oldOrder.designOrder,
          quantity: field == 'quantity'
              ? (newValue as double)
              : oldOrder.quantity,
          unitOfMeasure: field == 'unit_of_measure'
              ? newValue.toString()
              : oldOrder.unitOfMeasure,
          value: field == 'value' ? (newValue as double) : oldOrder.value,
          salesEngineer: field == 'sales_engineer'
              ? newValue.toString()
              : oldOrder.salesEngineer,
          orderDate: field == 'order_date'
              ? newValue.toString()
              : oldOrder.orderDate,
          deliveryDate: field == 'delivery_date'
              ? newValue.toString()
              : oldOrder.deliveryDate,
          endDate: field == 'end_date' ? newValue.toString() : oldOrder.endDate,
          // ✅ ADD THIS
          factory: field == 'factory' ? newValue.toString() : oldOrder.factory,
          designTeam: field == 'design_team'
              ? newValue.toString()
              : oldOrder.designTeam,
          responsibleEngineer: field == 'responsible_engineer'
              ? newValue.toString()
              : oldOrder.responsibleEngineer,
          reviewer: field == 'reviewer'
              ? newValue.toString()
              : oldOrder.reviewer,
          correspondenceEngineer: field == 'correspondence_engineer'
              ? newValue.toString()
              : oldOrder.correspondenceEngineer,
          createdAt: oldOrder.createdAt,
        );
        _allOrders[index] = updatedOrder;
        _orderIndexMap.remove(oldOrder);
        _orderIndexMap[updatedOrder] = index;
      }
    });
    _rebuildGroups();
  }

  Future<void> _updateOrderDesignTeam(
    SAPMainOrder order,
    String newValue,
  ) async {
    final oldValue = order.designTeam;

    // Auto-map status based on design team
    String getAutoStatus(String team) {
      switch (team) {
        case 'partition division':
        case 'product division':
        case 'Chair & Sofa Division':
        case 'cladding division':
          return 'Drawing Submittal';
        case 'Master Data division':
          return 'Master Data';
        case 'الادارة الهندسة':
          return 'الادارة الهندسه';
        case 'تصميم المنتجات':
          return 'ادارة تصميم المنتجات';
        case 'design studio':
          return 'design studio';
        case 'planning':
          return 'planning';
        default:
          return order.status; // Keep current status for unknown teams
      }
    }

    final autoStatus = getAutoStatus(newValue);

    // If multiple rows selected, apply to all
    if (_selectedRowsIds.length > 1) {
      setState(() => _isLoading = true);
      final supabase = Supabase.instance.client;
      int updated = 0;

      for (var orderId in _selectedRowsIds) {
        final selectedOrder = _allOrders
            .where((o) => o.id == orderId)
            .firstOrNull;
        if (selectedOrder != null) {
          try {
            final selectedAutoStatus = getAutoStatus(newValue);

            await supabase
                .from('sap_main_orders')
                .update({'design_team': newValue, 'status': selectedAutoStatus})
                .eq('id', selectedOrder.id);

            await _auditService.logChange(
              orderId: selectedOrder.id,
              designOrder: selectedOrder.designOrder,
              fieldName: 'design_team',
              oldValue: selectedOrder.designTeam,
              newValue: newValue,
              changedBy: _currentUserName,
              changedById: _currentUserId,
              actionType: 'bulk_update',
            );

            await _auditService.logChange(
              orderId: selectedOrder.id,
              designOrder: selectedOrder.designOrder,
              fieldName: 'status',
              oldValue: selectedOrder.status,
              newValue: selectedAutoStatus,
              changedBy: _currentUserName,
              changedById: _currentUserId,
              actionType: 'bulk_update',
            );

            updated++;
          } catch (e) {
            print('Failed: $e');
          }
        }
      }

      setState(() => _isLoading = false);
      _showSnackBar('✅ Design Team & Status updated for $updated rows!');
      _updateMultipleOrdersLocally('design_team', newValue);
      _updateMultipleOrdersLocally('status', autoStatus);
      return;
    }

    // Single row update
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('sap_main_orders')
          .update({'design_team': newValue, 'status': autoStatus})
          .eq('id', order.id);

      await _auditService.logChange(
        orderId: order.id,
        designOrder: order.designOrder,
        fieldName: 'design_team',
        oldValue: oldValue,
        newValue: newValue,
        changedBy: _currentUserName,
        changedById: _currentUserId,
      );

      await _auditService.logChange(
        orderId: order.id,
        designOrder: order.designOrder,
        fieldName: 'status',
        oldValue: order.status,
        newValue: autoStatus,
        changedBy: _currentUserName,
        changedById: _currentUserId,
      );

      _showSnackBar('Design Team → $newValue, Status → $autoStatus');
      _updateOrderLocally(order.id, 'design_team', newValue);
      _updateOrderLocally(order.id, 'status', autoStatus);
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

  // Replace the bulk update reload:
  void _updateMultipleOrdersLocally(String field, dynamic newValue) {
    setState(() {
      for (var orderId in _selectedRowsIds) {
        final index = _allOrders.indexWhere((o) => o.id == orderId);
        if (index != -1) {
          final oldOrder = _allOrders[index];
          final updatedOrder = SAPMainOrder(
            id: oldOrder.id,
            status: field == 'status' ? newValue.toString() : oldOrder.status,
            customerName: field == 'customer_name'
                ? newValue.toString()
                : oldOrder.customerName,
            itemNumber: field == 'item_number'
                ? newValue.toString()
                : oldOrder.itemNumber,
            productCode: field == 'product_code'
                ? newValue.toString()
                : oldOrder.productCode,
            contractNumber: field == 'contract_number'
                ? newValue.toString()
                : oldOrder.contractNumber,
            description: field == 'description'
                ? newValue.toString()
                : oldOrder.description,
            designOrder: field == 'design_order'
                ? newValue.toString()
                : oldOrder.designOrder,
            quantity: field == 'quantity'
                ? (newValue as double)
                : oldOrder.quantity,
            unitOfMeasure: field == 'unit_of_measure'
                ? newValue.toString()
                : oldOrder.unitOfMeasure,
            value: field == 'value' ? (newValue as double) : oldOrder.value,
            salesEngineer: field == 'sales_engineer'
                ? newValue.toString()
                : oldOrder.salesEngineer,
            orderDate: field == 'order_date'
                ? newValue.toString()
                : oldOrder.orderDate,
            endDate: field == 'end_date'
                ? newValue.toString()
                : oldOrder.endDate,
            // ✅ ADD THIS
            deliveryDate: field == 'delivery_date'
                ? newValue.toString()
                : oldOrder.deliveryDate,
            factory: field == 'factory'
                ? newValue.toString()
                : oldOrder.factory,
            designTeam: field == 'design_team'
                ? newValue.toString()
                : oldOrder.designTeam,
            responsibleEngineer: field == 'responsible_engineer'
                ? newValue.toString()
                : oldOrder.responsibleEngineer,
            reviewer: field == 'reviewer'
                ? newValue.toString()
                : oldOrder.reviewer,
            correspondenceEngineer: field == 'correspondence_engineer'
                ? newValue.toString()
                : oldOrder.correspondenceEngineer,
            createdAt: oldOrder.createdAt,
          );
          _allOrders[index] = updatedOrder;
          _orderIndexMap.remove(oldOrder);
          _orderIndexMap[updatedOrder] = index;
        }
      }
    });
    _rebuildGroups();
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
    final oldValue = _getCurrentFieldValue(order, field);

    // If multiple rows selected, apply to all
    if (_selectedRowsIds.length > 1) {
      setState(() => _isLoading = true);
      final supabase = Supabase.instance.client;
      int updated = 0;

      for (var orderId in _selectedRowsIds) {
        final selectedOrder = _allOrders
            .where((o) => o.id == orderId)
            .firstOrNull;
        if (selectedOrder != null) {
          try {
            await supabase
                .from('sap_main_orders')
                .update({field: newValue})
                .eq('id', selectedOrder.id);

            await _auditService.logChange(
              orderId: selectedOrder.id,
              designOrder: selectedOrder.designOrder,
              fieldName: field,
              oldValue: _getCurrentFieldValue(selectedOrder, field),
              newValue: newValue,
              changedBy: _currentUserName,
              changedById: _currentUserId,
              actionType: 'bulk_update',
            );
            updated++;
          } catch (e) {
            print('Failed: $e');
          }
        }
      }

      setState(() => _isLoading = false);
      _showSnackBar('✅ ${_formatFieldName(field)} updated for $updated rows!');
      _updateMultipleOrdersLocally(field, newValue);
      return;
    }

    // Single row update
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('sap_main_orders')
          .update({field: newValue})
          .eq('id', order.id);

      await _auditService.logChange(
        orderId: order.id,
        designOrder: order.designOrder,
        fieldName: field,
        oldValue: oldValue,
        newValue: newValue,
        changedBy: _currentUserName,
        changedById: _currentUserId,
      );

      _showSnackBar('Updated successfully!');
      _updateOrderLocally(order.id, field, newValue);
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

    // Sort sections based on _allStatuses order instead of count
    _sortedStatuses = _groupedOrders.keys.toList()
      ..sort((a, b) {
        final indexA = _allStatuses.indexOf(a);
        final indexB = _allStatuses.indexOf(b);
        // If not found in list, put at end
        if (indexA == -1 && indexB == -1) return a.compareTo(b);
        if (indexA == -1) return 1;
        if (indexB == -1) return -1;
        return indexA.compareTo(indexB);
      });

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
    if (_selectedRowsIds.isEmpty) {
      _showSnackBar('No orders selected');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete Orders',
          style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Are you sure you want to delete ${_selectedRowsIds.length} selected orders?\n\nThis action cannot be undone.',
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
            child: Text(
              'Delete ${_selectedRowsIds.length} orders',
              style: GoogleFonts.cairo(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    final supabase = Supabase.instance.client;
    int deleted = 0;
    int failed = 0;
    final deletedOrders = <Map<String, String>>[];
    final deletedIds = <String>[];

    for (var orderId in _selectedRowsIds.toList()) {
      SAPMainOrder? order;
      for (var o in _allOrders) {
        if (o.id == orderId) {
          order = o;
          break;
        }
      }

      if (order != null) {
        try {
          // Log the deletion before actually deleting
          await _auditService.logChange(
            orderId: order.id,
            designOrder: order.designOrder,
            fieldName: 'order_deleted',
            oldValue:
                '${order.designOrder} | ${order.customerName} | ${order.description}',
            newValue: null,
            changedBy: _currentUserName,
            changedById: _currentUserId,
            actionType: 'delete',
            notes: 'Order permanently deleted',
          );

          // Delete the order
          await supabase.from('sap_main_orders').delete().eq('id', order.id);
          deleted++;
          deletedIds.add(order.id);
          deletedOrders.add({
            'designOrder': order.designOrder,
            'customerName': order.customerName,
          });
        } catch (e) {
          failed++;
          print('Failed to delete ${order.id}: $e');
        }
      }
    }

    // Remove deleted orders from local list (no full reload needed)
    setState(() {
      _allOrders.removeWhere((o) => deletedIds.contains(o.id));
      _orderIndexMap.removeWhere((key, value) => deletedIds.contains(key.id));
      _selectedRowsIds.clear();
      _lastSelectedIndex = null;
      _isLoading = false;
    });

    // Rebuild groups with updated list
    _rebuildGroups();

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

    // Log summary if multiple orders were deleted
    if (deleted > 1) {
      await _auditService.logChange(
        orderId: 'bulk_delete',
        fieldName: 'bulk_delete',
        oldValue: null,
        newValue: '$deleted orders deleted',
        changedBy: _currentUserName,
        changedById: _currentUserId,
        actionType: 'delete',
        notes:
            'Bulk deleted $deleted orders: ${deletedOrders.map((o) => o['designOrder']).join(', ')}',
      );
    }
  }

  // Update order status with audit
  Future<void> _updateOrderStatus(SAPMainOrder order, String newStatus) async {
    final oldStatus = order.status;

    // If multiple rows selected, apply to all
    if (_selectedRowsIds.length > 1) {
      setState(() => _isLoading = true);
      final supabase = Supabase.instance.client;
      int updated = 0;

      for (var orderId in _selectedRowsIds) {
        final selectedOrder = _allOrders
            .where((o) => o.id == orderId)
            .firstOrNull;
        if (selectedOrder != null) {
          try {
            await supabase
                .from('sap_main_orders')
                .update({'status': newStatus})
                .eq('id', selectedOrder.id);

            await _auditService.logChange(
              orderId: selectedOrder.id,
              designOrder: selectedOrder.designOrder,
              fieldName: 'status',
              oldValue: selectedOrder.status,
              newValue: newStatus,
              changedBy: _currentUserName,
              changedById: _currentUserId,
              actionType: 'bulk_update',
            );
            updated++;
          } catch (e) {
            print('Failed to update ${selectedOrder.id}: $e');
          }
        }
      }

      setState(() => _isLoading = false);
      _showSnackBar('✅ Status updated for $updated rows!');
      _updateMultipleOrdersLocally('status', newStatus);
      return;
    }

    // Single row update (original behavior)
    try {
      final supabase = Supabase.instance.client;
      await supabase
          .from('sap_main_orders')
          .update({'status': newStatus})
          .eq('id', order.id);

      await _auditService.logChange(
        orderId: order.id,
        designOrder: order.designOrder,
        fieldName: 'status',
        oldValue: oldStatus,
        newValue: newStatus,
        changedBy: _currentUserName,
        changedById: _currentUserId,
      );

      _showSnackBar('Status updated!');
      _updateOrderLocally(order.id, 'status', newStatus);
    } catch (e) {
      _showSnackBar('Error updating status: $e');
    }
  }

  // Log import action
  Future<void> _logImportAction(int recordCount) async {
    await _auditService.logChange(
      orderId: 'import_batch',
      fieldName: 'import',
      oldValue: null,
      newValue: '$recordCount records imported',
      changedBy: _currentUserName,
      changedById: _currentUserId,
      actionType: 'import',
      notes: 'Bulk import of $recordCount records',
    );
  }

  // Log delete action
  Future<void> _logDeleteAction(String orderId, String designOrder) async {
    await _auditService.logChange(
      orderId: orderId,
      designOrder: designOrder,
      fieldName: 'delete',
      oldValue: designOrder,
      newValue: null,
      changedBy: _currentUserName,
      changedById: _currentUserId,
      actionType: 'delete',
      notes: 'Order deleted',
    );
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
      result = result
          .where(
            (o) =>
                o.contractNumber.toLowerCase().contains(q) ||
                o.customerName.toLowerCase().contains(q),
          )
          .toList();
    }
    if (_filterStatus != null)
      result = result.where((o) => o.status == _filterStatus).toList();
    if (_filterFactory != null)
      result = result.where((o) => o.factory == _filterFactory).toList();
    if (_filterDesignTeam != null)
      result = result.where((o) => o.designTeam == _filterDesignTeam).toList();
    if (_filterContractNumber != null)
      result = result
          .where(
            (o) => o.contractNumber.toLowerCase().contains(
              _filterContractNumber!.toLowerCase(),
            ),
          )
          .toList();
    if (_filterDesignOrder != null)
      result = result
          .where(
            (o) => o.designOrder.toLowerCase().contains(
              _filterDesignOrder!.toLowerCase(),
            ),
          )
          .toList();
    if (_filterSalesEngineer != null)
      result = result
          .where((o) => o.salesEngineer == _filterSalesEngineer)
          .toList();

    // My Work filter - check if employee is in ANY of these 3 fields
    if (_filterMyWork) {
      final myName = widget.loggedInEmployee?.fullName ?? '';
      result = result.where((o) {
        return o.responsibleEngineer == myName ||
            o.reviewer == myName ||
            o.correspondenceEngineer == myName;
      }).toList();
    } else {
      // Normal individual filters
      if (_filterResponsibleEngineer != null)
        result = result
            .where((o) => o.responsibleEngineer == _filterResponsibleEngineer)
            .toList();
      if (_filterReviewer != null)
        result = result.where((o) => o.reviewer == _filterReviewer).toList();
      if (_filterCorrespondenceEngineer != null)
        result = result
            .where(
              (o) => o.correspondenceEngineer == _filterCorrespondenceEngineer,
            )
            .toList();
    }

    _applySorting(result);
    return result;
  }

  bool get _hasActiveFilters =>
      _filterStatus != null ||
      _filterFactory != null ||
      _filterDesignTeam != null ||
      _filterContractNumber != null ||
      _filterDesignOrder != null ||
      _filterSalesEngineer != null ||
      _filterResponsibleEngineer != null ||
      _filterReviewer != null ||
      _filterCorrespondenceEngineer != null;

  Future<void> _showImportDialog() async {
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) =>
          ImportExcelDialog(onImportComplete: () => _loadAllDataOnce()),
    );
  }

  void _toggleRowSelection(SAPMainOrder order) {
    setState(() {
      if (_selectedRowsIds.contains(order.id)) {
        _selectedRowsIds.remove(order.id);
      } else {
        _selectedRowsIds.add(order.id);
      }
    });
  }

  void _selectAllInSection(String status) {
    setState(() {
      final sectionOrders = _groupedOrders[status] ?? [];
      if (sectionOrders.isEmpty) return;
      final allSelected = sectionOrders.every(
        (o) => _selectedRowsIds.contains(o.id),
      );
      if (allSelected) {
        for (var o in sectionOrders) {
          _selectedRowsIds.remove(o.id);
        }
      } else {
        for (var o in sectionOrders) {
          _selectedRowsIds.add(o.id);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedRowsIds.clear();
      _lastSelectedIndex = null;
    });
  }

  List<SAPMainOrder> _getSelectedOrders() =>
      _allOrders.where((o) => _selectedRowsIds.contains(o.id)).toList();

  Future<void> _exportSelectedOrders() async {
    if (_selectedRowsIds.isEmpty) {
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
      final path = await ExcelExportService.exportOrdersToExcel(orders);
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

  // Navigate to OrderTrackingPage (admin only)
  void _navigateToOrderTracking(SAPMainOrder order) {
    if (_isAdmin) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrderTrackingPage(order: order)),
      );
    }
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
      if (order.factory != null && order.factory!.isNotEmpty)
        factories.add(order.factory!);
      if (order.designTeam != null && order.designTeam!.isNotEmpty)
        designTeams.add(order.designTeam!);
      if (order.salesEngineer.isNotEmpty)
        salesEngineers.add(order.salesEngineer);
      if (order.responsibleEngineer != null &&
          order.responsibleEngineer!.isNotEmpty)
        responsibleEngineers.add(order.responsibleEngineer!);
      if (order.reviewer != null && order.reviewer!.isNotEmpty)
        reviewers.add(order.reviewer!);
      if (order.correspondenceEngineer != null &&
          order.correspondenceEngineer!.isNotEmpty)
        correspondenceEngineers.add(order.correspondenceEngineer!);
    }

    final contractCtrl = TextEditingController(text: _filterContractNumber);
    final designOrderCtrl = TextEditingController(text: _filterDesignOrder);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Row(
            children: [
              const Icon(Icons.filter_list, color: Color(0xFF0F172A), size: 22),
              const SizedBox(width: 8),
              Text(
                'Filter Orders',
                style: GoogleFonts.cairo(
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                ),
              ),
              const Spacer(),
              if (tempStatus != null ||
                  tempFactory != null ||
                  tempDesignTeam != null ||
                  tempContractNumber != null ||
                  tempSalesEngineer != null ||
                  tempResponsibleEngineer != null ||
                  tempReviewer != null ||
                  tempCorrespondenceEngineer != null)
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
                    'Active',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF6366F1),
                    ),
                  ),
                ),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ===== ORDER INFO =====
                  _buildFilterSection(
                    '📋 Order Information',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: contractCtrl,
                              style: GoogleFonts.cairo(fontSize: 13),
                              decoration: InputDecoration(
                                labelText: 'Contract Number',
                                labelStyle: GoogleFonts.cairo(fontSize: 12),
                                hintText: 'e.g. 9100035288',
                                hintStyle: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                prefixIcon: const Icon(
                                  Icons.description,
                                  size: 18,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (v) =>
                                  tempContractNumber = v.isEmpty ? null : v,
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
                                hintStyle: GoogleFonts.cairo(
                                  fontSize: 11,
                                  color: Colors.grey,
                                ),
                                prefixIcon: const Icon(Icons.receipt, size: 18),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              onChanged: (v) =>
                                  tempDesignOrder = v.isEmpty ? null : v,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ===== STATUS & DEPARTMENT =====
                  _buildFilterSection(
                    '📊 Status & Department',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterDropdown(
                              'Status',
                              tempStatus,
                              ['All', ..._allStatuses],
                              (v) => setDlg(() => tempStatus = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFilterDropdown(
                              'Factory (${factories.length})',
                              tempFactory,
                              ['All', ...factories.toList()..sort()],
                              (v) => setDlg(() => tempFactory = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _buildFilterDropdown(
                        'Design Team (${designTeams.length})',
                        tempDesignTeam,
                        ['All', ...designTeams.toList()..sort()],
                        (v) => setDlg(() => tempDesignTeam = v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // ===== ENGINEERS =====
                  _buildFilterSection(
                    '👨‍💼 Employee',
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterDropdown(
                              'Sales Eng. (${salesEngineers.length})',
                              tempSalesEngineer,
                              ['All', ...salesEngineers.toList()..sort()],
                              (v) => setDlg(() => tempSalesEngineer = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFilterDropdown(
                              'Resp. Eng. (${responsibleEngineers.length})',
                              tempResponsibleEngineer,
                              ['All', ...responsibleEngineers.toList()..sort()],
                              (v) => setDlg(() => tempResponsibleEngineer = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildFilterDropdown(
                              'Reviewer (${reviewers.length})',
                              tempReviewer,
                              ['All', ...reviewers.toList()..sort()],
                              (v) => setDlg(() => tempReviewer = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildFilterDropdown(
                              'Alt. Eng. (${correspondenceEngineers.length})',
                              tempCorrespondenceEngineer,
                              [
                                'All',
                                ...correspondenceEngineers.toList()..sort(),
                              ],
                              (v) =>
                                  setDlg(() => tempCorrespondenceEngineer = v),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            Row(
              children: [
                TextButton(
                  onPressed: () {
                    setDlg(() {
                      tempStatus = null;
                      tempFactory = null;
                      tempDesignTeam = null;
                      tempContractNumber = null;
                      tempDesignOrder = null;
                      tempSalesEngineer = null;
                      tempResponsibleEngineer = null;
                      tempReviewer = null;
                      tempCorrespondenceEngineer = null;
                      contractCtrl.clear();
                      designOrderCtrl.clear();
                    });
                  },
                  child: Row(
                    children: [
                      const Icon(Icons.clear_all, size: 16, color: Colors.red),
                      const SizedBox(width: 4),
                      Text(
                        'Clear All',
                        style: GoogleFonts.cairo(
                          color: Colors.red,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('Cancel', style: GoogleFonts.cairo(fontSize: 13)),
                ),
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
                      _filterCorrespondenceEngineer =
                          tempCorrespondenceEngineer;
                    });
                    _rebuildGroups();
                    Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.check, size: 18),
                  label: Text(
                    'Apply Filters',
                    style: GoogleFonts.cairo(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  // Helper widget for filter dropdowns
  Widget _buildFilterDropdown(
    String label,
    String? value,
    List<String> items,
    Function(String?) onChanged,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.cairo(fontSize: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
      ),
      style: GoogleFonts.cairo(fontSize: 13),
      items: items
          .map(
            (s) => DropdownMenuItem(
              value: s == 'All' ? null : s,
              child: Text(
                s == 'All' ? 'All' : s,
                style: GoogleFonts.cairo(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
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
                    if (_selectedRowsIds.isNotEmpty) _buildSelectionToolbar(),
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
          if (_selectedRowsIds.isNotEmpty) ...[
            const SizedBox(width: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF6366F1).withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_selectedRowsIds.length} selected',
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
          // My Work button
          _buildMyWorkButton(),
          const SizedBox(width: 8),
          // Edit Mode checkbox - beside My Work button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _editMode,
                  onChanged: (v) => setState(() => _editMode = v ?? false),
                  activeColor: Colors.orange,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => setState(() => _editMode = !_editMode),
                child: Text(
                  'Edit Mode',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _editMode ? Colors.orange : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(width: 8),

          OutlinedButton.icon(
            onPressed: _showAddTaskDialog,
            icon: const Icon(Icons.add_task, size: 16),
            label: Text(
              'Add Task',
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF059669),
              side: const BorderSide(color: Color(0xFF059669)),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              backgroundColor: Colors.white,
            ),
          ),

          const SizedBox(width: 8),

          // Only show people icon for admin/head users
          if (isAdmin)
            _buildIconBtn(Icons.people_outline, _navigateToEmployeeManagement),
        ],
      ),
    );
  }

  Widget _employeeDropdownCell(
    String? currentValue,
    SAPMainOrder order,
    String field,
  ) {
    final canEdit = _isOrderEditable(order);
    final displayName = currentValue ?? 'Select...';
    final hasValue = currentValue != null && currentValue.isNotEmpty;

    // Editable dropdown
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
          return Row(
            children: [
              Expanded(child: _buildHeaderInfo()),
              _buildSearchField(),
              const SizedBox(width: 8),
              _buildSortButton(),
              const SizedBox(width: 12),
              _buildActionBtn(Icons.filter_list, 'Filters', _showFilterDialog),
              const SizedBox(width: 8),
              _buildActionBtn(Icons.download, 'Export', () async {
                if (_allOrders.isNotEmpty)
                  await _saveOrders(_allOrders, 'Orders');
              }),
              // Only show Import for admin or abd.elmoen
              if (_canImportDelete) ...[
                const SizedBox(width: 8),
                _buildImportButton(),
              ],
              const SizedBox(width: 8),
              _buildRefreshButton(),
            ],
          );
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderInfo(),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildSearchField(),
                  _buildSortButton(),
                  _buildActionBtn(
                    Icons.filter_list,
                    'Filters',
                    _showFilterDialog,
                  ),
                  _buildActionBtn(Icons.download, 'Export', () async {
                    if (_allOrders.isNotEmpty)
                      await _saveOrders(_allOrders, 'Orders');
                  }),
                  // Only show Import for admin or abd.elmoen
                  if (_canImportDelete) _buildImportButton(),
                  _buildRefreshButton(),
                ],
              ),
            ],
          );
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
          style: GoogleFonts.cairo(
            fontSize: 13,
            color: const Color(0xFF45464D),
          ),
        ),
        if (_searchQuery.isNotEmpty)
          Text(
            'Filtered: "$_searchQuery"',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.cairo(
              fontSize: 10,
              color: const Color(0xFF6366F1),
            ),
          ),
        if (_hasActiveFilters)
          GestureDetector(
            onTap: () {
              setState(() {
                _filterStatus = null;
                _filterFactory = null;
                _filterDesignTeam = null;
                _filterContractNumber = null;
                _filterDesignOrder = null;
                _filterSalesEngineer = null;
                _filterResponsibleEngineer = null;
                _filterReviewer = null;
                _filterCorrespondenceEngineer = null;
              });
              _rebuildGroups();
            },
            child: Text(
              'Clear filters',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.cairo(
                fontSize: 11,
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
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
        onChanged: (v) {
          _searchQuery = v;
          _rebuildGroups();
        },
        style: GoogleFonts.cairo(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search...',
          hintStyle: GoogleFonts.cairo(
            color: Colors.grey.shade400,
            fontSize: 14,
          ),
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _searchQuery = '';
                    _rebuildGroups();
                  },
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF6366F1)),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  // Sort button
  Widget _buildSortButton() {
    return PopupMenuButton<String>(
      onSelected: (value) {
        setState(() => _sortBy = value);
        _rebuildGroups();
      },
      tooltip: 'Sort by',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFCBD5E1)),
          borderRadius: BorderRadius.circular(6),
          color: _sortBy != 'default'
              ? const Color(0xFF6366F1).withOpacity(0.05)
              : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sort,
              size: 16,
              color: _sortBy != 'default'
                  ? const Color(0xFF6366F1)
                  : const Color(0xFF334155),
            ),
            const SizedBox(width: 4),
            Text(
              _getSortLabel(),
              style: GoogleFonts.cairo(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _sortBy != 'default'
                    ? const Color(0xFF6366F1)
                    : const Color(0xFF334155),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'default',
          child: Row(
            children: [
              Icon(
                Icons.sort,
                size: 16,
                color: _sortBy == 'default'
                    ? const Color(0xFF6366F1)
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'Default',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: _sortBy == 'default'
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
              if (_sortBy == 'default') const Spacer(),
              if (_sortBy == 'default')
                const Icon(Icons.check, size: 16, color: Color(0xFF6366F1)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'value_desc',
          child: Row(
            children: [
              Icon(
                Icons.arrow_downward,
                size: 14,
                color: _sortBy == 'value_desc'
                    ? const Color(0xFF6366F1)
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'Value ↓',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: _sortBy == 'value_desc'
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
              if (_sortBy == 'value_desc') const Spacer(),
              if (_sortBy == 'value_desc') const Icon(Icons.check, size: 16),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'value_asc',
          child: Row(
            children: [
              Icon(
                Icons.arrow_upward,
                size: 14,
                color: _sortBy == 'value_asc'
                    ? const Color(0xFF6366F1)
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'Value ↑',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: _sortBy == 'value_asc'
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
              if (_sortBy == 'value_asc') const Spacer(),
              if (_sortBy == 'value_asc') const Icon(Icons.check, size: 16),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'date_desc',
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 14,
                color: _sortBy == 'date_desc'
                    ? const Color(0xFF6366F1)
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'Date ↓',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: _sortBy == 'date_desc'
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
              if (_sortBy == 'date_desc') const Spacer(),
              if (_sortBy == 'date_desc') const Icon(Icons.check, size: 16),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'date_asc',
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 14,
                color: _sortBy == 'date_asc'
                    ? const Color(0xFF6366F1)
                    : Colors.grey,
              ),
              const SizedBox(width: 8),
              Text(
                'Date ↑',
                style: GoogleFonts.cairo(
                  fontSize: 12,
                  fontWeight: _sortBy == 'date_asc'
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
              if (_sortBy == 'date_asc') const Spacer(),
              if (_sortBy == 'date_asc') const Icon(Icons.check, size: 16),
            ],
          ),
        ),
      ],
    );
  }

  // Refresh button
  Widget _buildRefreshButton() {
    return ElevatedButton.icon(
      onPressed: _loadAllDataOnce,
      icon: const Icon(Icons.refresh, size: 18),
      label: Text(
        'Refresh',
        style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _designTeamDropdownCell(String? currentValue, SAPMainOrder order) {
    final canEdit = _isOrderEditable(order);
    final displayName = currentValue ?? 'Select...';
    final hasValue = currentValue != null && currentValue.isNotEmpty;

    // Editable dropdown
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
            '${_selectedRowsIds.length} selected',
            style: GoogleFonts.cairo(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF6366F1),
            ),
          ),
          const Spacer(),
          // Copy selected button
          _buildSmallBtn(Icons.copy, 'Copy', _copySelectedOrdersData),
          const SizedBox(width: 8),
          // Bulk edit button (only in edit mode with selections)
          if (_editMode && _selectedRowsIds.isNotEmpty) ...[
            _buildSmallBtn(
              Icons.edit,
              'Bulk Edit',
              () => _showBulkEditDialog(),
            ),
            const SizedBox(width: 8),
          ],
          _buildSmallBtn(
            Icons.download,
            'Export Selected',
            _exportSelectedOrders,
          ),
          const SizedBox(width: 8),
          if (_canImportDelete) ...[
            _buildSmallBtn(
              Icons.delete_outline,
              'Delete',
              _deleteSelectedOrders,
            ),
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
    final allSelected = orders.every((o) => _selectedRowsIds.contains(o.id));
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

  Widget _buildMyWorkButton() {
    final hasMyWork = _filterMyWork;
    final myName = widget.loggedInEmployee?.fullName ?? '';

    // Count my work items
    final myWorkCount = _allOrders.where((o) {
      return o.responsibleEngineer == myName ||
          o.reviewer == myName ||
          o.correspondenceEngineer == myName;
    }).length;

    return OutlinedButton.icon(
      onPressed: _applyMyWorkFilter,
      icon: Icon(
        hasMyWork ? Icons.work : Icons.work_outline,
        size: 16,
        color: hasMyWork ? Colors.white : const Color(0xFF6366F1),
      ),
      label: Text(
        hasMyWork ? 'My Work ($myWorkCount)' : 'My Work',
        style: GoogleFonts.cairo(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: hasMyWork ? Colors.white : const Color(0xFF6366F1),
        ),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF6366F1),
        side: BorderSide(
          color: hasMyWork ? const Color(0xFF6366F1) : const Color(0xFF6366F1),
        ),
        backgroundColor: hasMyWork ? const Color(0xFF6366F1) : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
        child: Row(children: [const Spacer()]),
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
        // Add tracking icon in header
        if (_isAdmin)
          SizedBox(
            width: 36,
            child: Icon(
              Icons.track_changes,
              size: 16,
              color: Colors.grey.shade500,
            ),
          ),
      ],
    ),
  );

  Widget _buildNameCell(SAPMainOrder order, int index) {
    final isSelected = _selectedRowsIds.contains(order.id);
    return GestureDetector(
      onTap: () => _toggleRowSelection(order),
      onLongPress: () {
        // Copy only the customer name
        _copyFieldToClipboard('Customer Name', order.customerName);
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF001761).withOpacity(0.15)
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
                onChanged: (v) => _toggleRowSelection(order),
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
            // Add tracking icon for admin users
            if (_isAdmin)
              SizedBox(
                width: 36,
                child: IconButton(
                  icon: const Icon(
                    Icons.track_changes,
                    size: 16,
                    color: Color(0xFF6366F1),
                  ),
                  onPressed: () => _navigateToOrderTracking(order),
                  tooltip: 'Track Order',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  splashRadius: 16,
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
        _hdr('Status', 140),
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
        _hdr('E-Date', 100),
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
    final isSelected = _selectedRowsIds.contains(order.id);
    return GestureDetector(
      onTap: () => _showOrderDetails(order),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF001761).withOpacity(0.15)
              : Colors.white,
          border: Border(bottom: BorderSide(color: Colors.grey.shade50)),
        ),
        child: Row(
          children: [
            _statusCell(order.status, order),
            _editableCell(order.itemNumber, 60, order, 'item_number', 'Item'),
            _editableCell(
              order.productCode,
              120,
              order,
              'product_code',
              'Product Code',
              style: GoogleFonts.cairo(fontSize: 11),
            ),
            _editableCell(
              order.contractNumber,
              110,
              order,
              'contract_number',
              'Contract Number',
            ),
            _editableCell(
              order.description,
              200,
              order,
              'description',
              'Description',
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
            _editableCell(
              order.designOrder,
              110,
              order,
              'design_order',
              'Design Order',
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF6366F1),
              ),
            ),
            _editableCell(
              '${order.quantity}',
              70,
              order,
              'quantity',
              'QTY',
              align: TextAlign.right,
            ),
            _editableCell(
              order.unitOfMeasure,
              50,
              order,
              'unit_of_measure',
              'Unit',
            ),
            _editableCell(
              _formatNumber(order.value),
              110,
              order,
              'value',
              'Value',
              align: TextAlign.right,
              style: GoogleFonts.cairo(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF059669),
              ),
            ),
            _editableCell(
              order.salesEngineer,
              150,
              order,
              'sales_engineer',
              'Sales Engineer',
            ),
            _editableCell(
              order.orderDate ?? '-',
              100,
              order,
              'order_date',
              'Order Date',
            ),
            _editableCell(
              order.endDate ?? '-',
              100,
              order,
              'end_date',
              'End Date',
            ),
            _editableCell(
              order.deliveryDate ?? '-',
              100,
              order,
              'delivery_date',
              'Delivery Date',
            ),
            _editableCell(
              order.factory ?? '-',
              70,
              order,
              'factory',
              'Factory',
            ),
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

  Widget _editableCell(
    String text,
    double w,
    SAPMainOrder order,
    String field,
    String fieldLabel, {
    TextAlign align = TextAlign.left,
    TextStyle? style,
    TextOverflow overflow = TextOverflow.ellipsis,
    int maxLines = 1,
  }) {
    final canEdit = _isOrderEditable(order);
    final isDateField =
        field == 'order_date' ||
        field == 'delivery_date' ||
        field == 'end_date';

    // Only make editable when Edit Mode is ON AND user can edit this order
    if (_editMode && canEdit) {
      if (isDateField) {
        return SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () => _pickDateForEdit(order, field, text),
              onLongPress: () {
                final copyValue = text == '-' ? '' : text;
                _copyFieldToClipboard(fieldLabel, copyValue);
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.orange.withOpacity(0.05),
                ),
                child: Align(
                  alignment: align == TextAlign.right
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 10,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 2),
                      Flexible(
                        child: Text(
                          text,
                          style:
                              (style ??
                              GoogleFonts.cairo(
                                fontSize: 12,
                                color: const Color(0xFF334155),
                              )),
                          overflow: overflow,
                          maxLines: maxLines,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      } else {
        return SizedBox(
          width: w,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: InkWell(
              onTap: () =>
                  _editOrderField(order, field, text == '-' ? '' : text),
              onLongPress: () {
                final copyValue = text == '-' ? '' : text;
                _copyFieldToClipboard(fieldLabel, copyValue);
              },
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.orange.withOpacity(0.5)),
                  borderRadius: BorderRadius.circular(4),
                  color: Colors.orange.withOpacity(0.05),
                ),
                child: Align(
                  alignment: align == TextAlign.right
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Text(
                    text,
                    style:
                        (style ??
                        GoogleFonts.cairo(
                          fontSize: 12,
                          color: const Color(0xFF334155),
                        )),
                    overflow: overflow,
                    maxLines: maxLines,
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }

    // Normal cell with long press to copy
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: GestureDetector(
          onLongPress: () {
            final copyValue = text == '-' ? '' : text;
            _copyFieldToClipboard(fieldLabel, copyValue);
          },
          child: Align(
            alignment: align == TextAlign.right
                ? Alignment.centerRight
                : Alignment.centerLeft,
            child: Text(
              text,
              style:
                  style ??
                  GoogleFonts.cairo(
                    fontSize: 12,
                    color: const Color(0xFF334155),
                  ),
              overflow: overflow,
              maxLines: maxLines,
            ),
          ),
        ),
      ),
    );
  }

  // Save inline edit
  Future<void> _saveInlineEdit(
    SAPMainOrder order,
    String field,
    String newValue,
    String editKey,
    String oldValue,
  ) async {
    // Clean up controller
    _editControllers.remove(editKey);

    setState(() {
      _editingField = null;
    });

    if (newValue.isEmpty ||
        newValue == oldValue ||
        newValue == (oldValue == '-' ? '' : oldValue))
      return;

    // If multiple rows selected, apply to all
    if (_editMode && _selectedRowsIds.length > 1) {
      await _applyBulkEditToSelected(field, newValue);
      return;
    }

    // Single row update
    try {
      final supabase = Supabase.instance.client;
      dynamic parsedValue = newValue;

      if (field == 'quantity') {
        parsedValue = double.tryParse(newValue.replaceAll(',', '')) ?? 0;
      } else if (field == 'value') {
        parsedValue =
            double.tryParse(
              newValue.replaceAll(',', '').replaceAll('\$', ''),
            ) ??
            0;
      }

      await supabase
          .from('sap_main_orders')
          .update({field: parsedValue})
          .eq('id', order.id);

      await _auditService.logChange(
        orderId: order.id,
        designOrder: order.designOrder,
        fieldName: field,
        oldValue: oldValue == '-' ? '' : oldValue,
        newValue: newValue,
        changedBy: _currentUserName,
        changedById: _currentUserId,
      );

      _showSnackBar('${_formatFieldName(field)} updated!');
      _updateOrderLocally(order.id, field, parsedValue);
    } catch (e) {
      _showSnackBar('Error updating: $e');
    }
  }

  // Apply bulk edit to all selected rows (inline)
  Future<void> _applyBulkEditToSelected(String field, String newValue) async {
    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    int updated = 0;

    dynamic parsedValue = newValue;
    if (field == 'quantity') {
      parsedValue = double.tryParse(newValue.replaceAll(',', '')) ?? 0;
    } else if (field == 'value') {
      parsedValue =
          double.tryParse(newValue.replaceAll(',', '').replaceAll('\$', '')) ??
          0;
    }

    for (var orderId in _selectedRowsIds) {
      final order = _allOrders.where((o) => o.id == orderId).firstOrNull;
      if (order != null) {
        try {
          await supabase
              .from('sap_main_orders')
              .update({field: parsedValue})
              .eq('id', order.id);

          await _auditService.logChange(
            orderId: order.id,
            designOrder: order.designOrder,
            fieldName: field,
            oldValue: _getCurrentFieldValue(order, field),
            newValue: newValue,
            changedBy: _currentUserName,
            changedById: _currentUserId,
            actionType: 'bulk_update',
          );
          updated++;
        } catch (e) {
          print('Failed to update ${order.id}: $e');
        }
      }
    }

    setState(() => _isLoading = false);
    _showSnackBar('✅ $updated rows updated!');
    _updateMultipleOrdersLocally(field, parsedValue);
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

  Widget _statusCell(String status, SAPMainOrder order) {
    // Dropdown only for Tasks orders
    return SizedBox(
      width: 140,
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
              border: Border.all(
                color: _getStatusColor(status).withOpacity(0.3),
              ),
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
                      fontWeight: s == status
                          ? FontWeight.w700
                          : FontWeight.w400,
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
  }

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
