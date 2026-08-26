import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:excel/excel.dart' hide Border;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:universal_html/html.dart' as html;

class ImportExcelDialog extends StatefulWidget {
  final VoidCallback onImportComplete;

  const ImportExcelDialog({super.key, required this.onImportComplete});

  @override
  State<ImportExcelDialog> createState() => _ImportExcelDialogState();
}

class _ImportExcelDialogState extends State<ImportExcelDialog> {
  List<Map<String, dynamic>> _allExcelData = [];
  List<Map<String, dynamic>> _newRecords = [];
  List<Map<String, dynamic>> _duplicateRecords = [];
  bool _importDuplicates = false; // New flag

  // Per-row dates (3 dates)
  final Map<int, DateTime?> _rowOrderDates = {};
  final Map<int, DateTime?> _rowEndDates = {};
  final Map<int, DateTime?> _rowDeliveryDates = {};

  // Bulk dates
  DateTime? _bulkOrderDate;
  DateTime? _bulkEndDate;
  DateTime? _bulkDeliveryDate;

  // Status
  String _defaultStatus = 'Tasks';
  final Map<int, String> _rowStatuses = {};

  bool _isLoading = false;
  bool _fileLoaded = false;
  String? _fileName;
  int _totalRows = 0;
  int _newRows = 0;
  int _duplicateRows = 0;
  int _selectedTab = 0;

  static const List<String> _sections = [
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
    'Unknown',
  ];

  static const Color primaryColor = Color(0xFF0F172A);
  static const Color greenColor = Color(0xFF059669);
  static const Color redColor = Color(0xFFDC2626);
  static const Color orangeColor = Color(0xFFD97706);
  static const Color blueColor = Color(0xFF6366F1);

  Future<void> _pickFile() async {
    try {
      final uploadInput = html.FileUploadInputElement();
      uploadInput.accept = '.xlsx,.xls,.csv';
      uploadInput.click();
      await uploadInput.onChange.first;

      if (uploadInput.files == null || uploadInput.files!.isEmpty) return;

      final file = uploadInput.files!.first;
      _fileName = file.name;
      setState(() => _isLoading = true);

      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;

      final bytes = reader.result as List<int>;

      if (file.name.endsWith('.csv')) {
        await _parseCSV(bytes);
      } else {
        await _parseExcel(bytes);
      }

      await _checkDuplicates();

      setState(() {
        _isLoading = false;
        _fileLoaded = true;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e', style: GoogleFonts.cairo())),
        );
      }
    }
  }

  Future<void> _parseCSV(List<int> bytes) async {
    final csvString = Utf8Decoder().convert(bytes);
    final lines = csvString.split('\n');
    if (lines.length < 2) return;

    final headers = lines[0]
        .split(',')
        .map((h) => h.trim().replaceAll('"', '').toLowerCase())
        .toList();
    final columnMap = _buildColumnMap(headers);

    _allExcelData = [];
    _rowStatuses.clear();
    _rowOrderDates.clear();
    _rowEndDates.clear();
    _rowDeliveryDates.clear();

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final values = _parseCSVLine(lines[i]);
      final record = <String, dynamic>{};
      columnMap.forEach((key, col) {
        record[key] = col < values.length ? values[col].trim() : '';
      });
      if (record['design_order']?.isNotEmpty ?? false) {
        _allExcelData.add(record);
        _rowStatuses[_allExcelData.length - 1] = _defaultStatus;
      }
    }
    _totalRows = _allExcelData.length;
  }

  Future<void> _parseExcel(List<int> bytes) async {
    var excel = Excel.decodeBytes(bytes);
    var sheet = excel.tables.keys.first;
    var table = excel.tables[sheet];
    if (table == null || table.rows.isEmpty) return;

    final headerRow = table.rows[0];
    final headers = headerRow
        .map((h) => h?.value?.toString().trim().toLowerCase() ?? '')
        .toList();
    final columnMap = _buildColumnMap(headers);

    _allExcelData = [];
    _rowStatuses.clear();
    _rowOrderDates.clear();
    _rowEndDates.clear();
    _rowDeliveryDates.clear();

    for (var i = 1; i < table.rows.length; i++) {
      final record = <String, dynamic>{};
      columnMap.forEach((key, col) {
        if (col < table.rows[i].length) {
          record[key] = table.rows[i][col]?.value?.toString() ?? '';
        } else {
          record[key] = '';
        }
      });
      if (record['design_order']?.isNotEmpty ?? false) {
        _allExcelData.add(record);
        _rowStatuses[_allExcelData.length - 1] = _defaultStatus;
      }
    }
    _totalRows = _allExcelData.length;
  }

  Map<String, int> _buildColumnMap(List<String> headers) {
    final columnMap = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();

      if (h == 'name' || h.contains('customer')) {
        columnMap['customer_name'] = i;
      } else if (h.contains('design') || h.contains('order')) {
        columnMap['design_order'] = i;
      } else if (h.contains('value') || h.contains('قيمة')) {
        columnMap['value'] = i;
      } else if (h.contains('contract')) {
        columnMap['contract_number'] = i;
      } else if (h == 'item' || h.contains('بند')) {
        columnMap['item_number'] = i;
      } else if (h.contains('product') || h.contains('منتج')) {
        columnMap['product_code'] = i;
      } else if (h.contains('description') || h.contains('وصف')) {
        columnMap['description'] = i;
      } else if (h.contains('qty') || h.contains('كمية')) {
        columnMap['quantity'] = i;
      } else if (h.contains('unit') || h.contains('وحدة')) {
        columnMap['unit_of_measure'] = i;
      } else if (h.contains('sales') || h.contains('مبيعات')) {
        columnMap['sales_engineer'] = i;
      } else if (h.contains('factory') || h.contains('مصنع')) {
        columnMap['factory'] = i;
      } else if (h.contains('delivery') || h.contains('تسليم')) {
        columnMap['delivery_date'] = i;
      } else if (h.contains('end')) {
        columnMap['end_date'] = i;
      } else if (h.contains('o-date') || h.contains('order date')) {
        columnMap['order_date'] = i;
      }
    }
    return columnMap;
  }

  List<String> _parseCSVLine(String line) {
    final result = <String>[];
    var current = '';
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (char == ',' && !inQuotes) {
        result.add(current.replaceAll('"', ''));
        current = '';
      } else {
        current += char;
      }
    }
    result.add(current.replaceAll('"', ''));
    return result;
  }

  Future<void> _checkDuplicates() async {
    final supabase = Supabase.instance.client;
    final existingData = await supabase
        .from('sap_main_orders')
        .select('design_order, item_number');

    final existingKeys = <String>{};
    for (var row in existingData) {
      existingKeys.add('${row['design_order']}_${row['item_number']}');
    }

    _newRecords = [];
    _duplicateRecords = [];
    for (var record in _allExcelData) {
      final key = '${record['design_order']}_${record['item_number']}';
      if (existingKeys.contains(key)) {
        _duplicateRecords.add(record);
      } else {
        _newRecords.add(record);
      }
    }
    _newRows = _newRecords.length;
    _duplicateRows = _duplicateRecords.length;
  }

  Future<void> _pickDateForRow(int index, String field) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null) {
      setState(() {
        if (field == 'order_date') {
          _rowOrderDates[index] = date;
        } else if (field == 'end_date') {
          _rowEndDates[index] = date;
        } else if (field == 'delivery_date') {
          _rowDeliveryDates[index] = date;
        }
      });
    }
  }

  Future<void> _importRecords() async {
    // Determine records to import based on _importDuplicates flag
    final recordsToImport = _importDuplicates
        ? _allExcelData
        : _newRecords;

    if (recordsToImport.isEmpty) {
      _showMessage('No records to import');
      return;
    }

    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    int imported = 0, failed = 0;

    final enrichedRecords = recordsToImport.map((record) {
      final globalIndex = _allExcelData.indexOf(record);
      return {
        'status': 'imported',
        'customer_name': record['customer_name'] ?? '',
        'item_number': record['item_number'] ?? '',
        'product_code': record['product_code'] ?? '',
        'contract_number': record['contract_number'] ?? '',
        'description': record['description'] ?? '',
        'design_order': record['design_order'] ?? '',
        'quantity': double.tryParse(record['quantity']?.toString().replaceAll(',', '') ?? '0') ?? 0,
        'unit_of_measure': record['unit_of_measure'] ?? 'EA',
        'value': double.tryParse(record['value']?.toString().replaceAll(',', '').replaceAll('\$', '') ?? '0') ?? 0,
        'sales_engineer': record['sales_engineer'] ?? '',
        'order_date': _rowOrderDates[globalIndex] != null
            ? DateFormat('yyyy-MM-dd').format(_rowOrderDates[globalIndex]!)
            : null,
        'end_date': _rowEndDates[globalIndex] != null
            ? DateFormat('yyyy-MM-dd').format(_rowEndDates[globalIndex]!)
            : null,
        'delivery_date': _rowDeliveryDates[globalIndex] != null
            ? DateFormat('yyyy-MM-dd').format(_rowDeliveryDates[globalIndex]!)
            : null,
        'factory': record['factory'] ?? null,
        'design_team': null,
        'responsible_engineer': null,
        'reviewer': null,
        'correspondence_engineer': null,
      };
    }).toList();

    for (var i = 0; i < enrichedRecords.length; i += 500) {
      final batch = enrichedRecords.sublist(
        i,
        i + 500 > enrichedRecords.length ? enrichedRecords.length : i + 500,
      );
      try {
        await supabase.from('sap_main_orders').insert(batch);
        imported += batch.length;
      } catch (e) {
        for (var record in batch) {
          try {
            await supabase.from('sap_main_orders').insert(record);
            imported++;
          } catch (_) {
            failed++;
          }
        }
      }
    }

    setState(() => _isLoading = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Import Complete', style: GoogleFonts.cairo(fontWeight: FontWeight.w600)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildResultRow('Imported:', '$imported', greenColor),
              const SizedBox(height: 4),
              _buildResultRow('Failed:', '$failed', failed > 0 ? redColor : Colors.grey),
              if (_duplicateRows > 0 && !_importDuplicates) ...[
                const SizedBox(height: 4),
                _buildResultRow('Duplicates skipped:', '$_duplicateRows', orangeColor),
              ],
              const SizedBox(height: 4),
              _buildResultRow('Status:', 'imported', blueColor),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context, true);
                widget.onImportComplete();
              },
              style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
              child: Text('Done', style: GoogleFonts.cairo(color: Colors.white)),
            ),
          ],
        ),
      );
    }
  }

  void _showDuplicateWarning() {
    // If no duplicates, import directly
    if (_duplicateRows == 0) {
      _importRecords();
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber, color: orangeColor, size: 28),
            const SizedBox(width: 8),
            Text(
              'Duplicate Records Detected',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Found $_duplicateRows duplicate record(s) in your file.',
              style: GoogleFonts.cairo(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: orangeColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: orangeColor.withOpacity(0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: orangeColor, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Do you want to import duplicates anyway?',
                      style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w600, color: orangeColor),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Import only new records
              setState(() => _importDuplicates = false);
              _importRecords();
            },
            child: Text('Skip Duplicates', style: GoogleFonts.cairo()),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              // Import everything including duplicates
              setState(() => _importDuplicates = true);
              _importRecords();
            },
            style: ElevatedButton.styleFrom(backgroundColor: orangeColor),
            child: Text('Import All', style: GoogleFonts.cairo(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: GoogleFonts.cairo())),
    );
  }

  Widget _buildResultRow(String label, String value, Color color) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: GoogleFonts.cairo(
              fontSize: 14,
              color: const Color(0xFF64748B),
            ),
          ),
        ),
        Text(
          value,
          style: GoogleFonts.cairo(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.95,
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildContent()),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
        border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.upload_file, color: primaryColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import Excel Data',
                  style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w700, color: primaryColor),
                ),
                if (_fileLoaded)
                  Text(
                    '$_fileName • $_totalRows rows • Status: imported',
                    style: GoogleFonts.cairo(fontSize: 13, color: const Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
          if (_fileLoaded) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock, size: 12, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'imported',
                    style: GoogleFonts.cairo(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (!_fileLoaded) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.cloud_upload_outlined,
              size: 80,
              color: Color(0xFF94A3B8),
            ),
            const SizedBox(height: 24),
            Text(
              'Select Excel or CSV file',
              style: GoogleFonts.cairo(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _pickFile,
              icon: const Icon(Icons.file_open),
              label: Text(
                'Browse Files',
                style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _buildSummaryCard(
                'New Records',
                '$_newRows',
                greenColor,
                Icons.add_circle_outline,
              ),
              const SizedBox(width: 10),
              _buildSummaryCard(
                'Duplicates',
                '$_duplicateRows',
                orangeColor,
                Icons.content_copy,
              ),
              const SizedBox(width: 10),
              _buildSummaryCard(
                'Total Rows',
                '$_totalRows',
                primaryColor,
                Icons.table_rows,
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              _buildTab('New (${_newRows})', 0),
              _buildTab('Duplicates (${_duplicateRows})', 1),
              _buildTab('All (${_totalRows})', 2),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _buildDataPreview()),
      ],
    );
  }

  Widget _buildSummaryCard(
      String title,
      String count,
      Color color,
      IconData icon,
      ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  count,
                  style: GoogleFonts.cairo(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(String label, int index) {
    final isSelected = _selectedTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedTab = index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isSelected ? primaryColor : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDataPreview() {
    List<Map<String, dynamic>> displayData;
    if (_selectedTab == 0) {
      displayData = _newRecords;
    } else if (_selectedTab == 1) {
      displayData = _duplicateRecords;
    } else {
      displayData = _allExcelData;
    }

    if (displayData.isEmpty) {
      return Center(
        child: Text(
          'No data',
          style: GoogleFonts.cairo(color: const Color(0xFF64748B)),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1600,
        child: Column(
          children: [
            Container(
              height: 36,
              decoration: const BoxDecoration(
                color: Color(0xFFF1F5F9),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  _previewHeaderCell('Status', 110),
                  _previewHeaderCell('Name', 140),
                  _previewHeaderCell('Design Order', 100),
                  _previewHeaderCell('Contract', 100),
                  _previewHeaderCell('Item', 60),
                  _previewHeaderCell('Product Code', 120),
                  _previewHeaderCell('Description', 200),
                  _previewHeaderCell('QTY', 50),
                  _previewHeaderCell('Unit', 40),
                  _previewHeaderCell('Value', 90),
                  _previewHeaderCell('Sales Eng.', 130),
                  _previewHeaderCell('Factory', 60),
                  _previewHeaderCell('Order Date', 110),
                  _previewHeaderCell('End Date', 110),
                  _previewHeaderCell('Delivery Date', 110),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: displayData.length > 100 ? 100 : displayData.length,
                itemBuilder: (context, rowIndex) {
                  final record = displayData[rowIndex];
                  final globalIndex = _allExcelData.indexOf(record);
                  final orderDate = _rowOrderDates[globalIndex];
                  final endDate = _rowEndDates[globalIndex];
                  final deliveryDate = _rowDeliveryDates[globalIndex];

                  return Container(
                    height: 40,
                    decoration: BoxDecoration(
                      border: const Border(
                        bottom: BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      color: _selectedTab == 1 ? Colors.orange.shade50 : null,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 110,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.grey.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lock, size: 10, color: Colors.grey),
                                  const SizedBox(width: 4),
                                  Text(
                                    'imported',
                                    style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade700),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _previewDataCell(record['customer_name']?.toString() ?? '', 140),
                        _previewDataCell(record['design_order']?.toString() ?? '', 100),
                        _previewDataCell(record['contract_number']?.toString() ?? '', 100),
                        _previewDataCell(record['item_number']?.toString() ?? '', 60),
                        _previewDataCell(record['product_code']?.toString() ?? '', 120),
                        _previewDataCell(record['description']?.toString() ?? '', 200),
                        _previewDataCell(record['quantity']?.toString() ?? '', 50),
                        _previewDataCell(record['unit_of_measure']?.toString() ?? '', 40),
                        _previewDataCell(record['value']?.toString() ?? '', 90),
                        _previewDataCell(record['sales_engineer']?.toString() ?? '', 130),
                        _previewDataCell(record['factory']?.toString() ?? '', 60),
                        SizedBox(
                          width: 110,
                          child: _buildDateCell('Order', orderDate, () => _pickDateForRow(globalIndex, 'order_date')),
                        ),
                        SizedBox(
                          width: 110,
                          child: _buildDateCell('End', endDate, () => _pickDateForRow(globalIndex, 'end_date')),
                        ),
                        SizedBox(
                          width: 110,
                          child: _buildDateCell('Delivery', deliveryDate, () => _pickDateForRow(globalIndex, 'delivery_date')),
                        ),
                      ],
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

  Widget _previewHeaderCell(String text, double w) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: GoogleFonts.cairo(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF0F172A),
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _previewDataCell(String text, double w) {
    return SizedBox(
      width: w,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          text,
          style: GoogleFonts.cairo(fontSize: 10),
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ),
    );
  }

  Widget _buildDateCell(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        height: 30,
        decoration: BoxDecoration(
          border: Border.all(
            color: date != null ? orangeColor : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(4),
          color: date != null ? orangeColor.withOpacity(0.05) : Colors.white,
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 10,
              color: date != null ? orangeColor : Colors.grey,
            ),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                date != null ? DateFormat('MM/dd').format(date!) : label,
                style: GoogleFonts.cairo(fontSize: 9),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Text(
            _fileLoaded
                ? (_duplicateRows > 0
                ? 'Ready to import $_newRows new records ($_duplicateRows duplicates)'
                : 'Ready to import $_newRows new records')
                : 'Select a file to begin',
            style: GoogleFonts.cairo(
              fontSize: 13,
              color: const Color(0xFF64748B),
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.cairo()),
          ),
          const SizedBox(width: 12),
          ElevatedButton.icon(
            onPressed: (_fileLoaded && _allExcelData.isNotEmpty)
                ? _showDuplicateWarning
                : null,
            icon: const Icon(Icons.upload, size: 18),
            label: Text(
              _duplicateRows > 0
                  ? 'Import $_newRows New Records'
                  : 'Import $_totalRows Records',
              style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: greenColor,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}



