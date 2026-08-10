// lib/pages/import_excel_dialog.dart
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

  // Per-row Section & Pickup Date
  final Map<int, String> _rowSections = {};
  final Map<int, DateTime?> _rowPickupDates = {};
  String? _bulkSection;
  DateTime? _bulkDate;

  bool _isLoading = false;
  bool _fileLoaded = false;
  String? _fileName;
  int _totalRows = 0;
  int _newRows = 0;
  int _duplicateRows = 0;
  int _selectedTab = 0;

  static const List<String> _sections = [
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
    'partation master data',
    'Done',
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
    _rowSections.clear();
    _rowPickupDates.clear();

    for (var i = 1; i < lines.length; i++) {
      if (lines[i].trim().isEmpty) continue;
      final values = _parseCSVLine(lines[i]);
      final record = <String, dynamic>{};
      columnMap.forEach((key, col) {
        record[key] = col < values.length ? values[col].trim() : '';
      });
      if (record['design_order']?.isNotEmpty ?? false) {
        _allExcelData.add(record);
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
    _rowSections.clear();
    _rowPickupDates.clear();

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
      }
    }
    _totalRows = _allExcelData.length;
  }

  Map<String, int> _buildColumnMap(List<String> headers) {
    final columnMap = <String, int>{};
    for (var i = 0; i < headers.length; i++) {
      final h = headers[i].trim().toLowerCase();

      if (h == 'name' || h.contains('customer') || (h.contains('name') && !h.contains('group'))) {
        columnMap['customer_name'] = i;
      } else if (h.contains('design') || h.contains('order')) {
        columnMap['design_order'] = i;
      } else if (h.contains('value') || h.contains('قيمة')) {
        columnMap['value'] = i;
      } else if (h.contains('contract')) {
        columnMap['contract_number'] = i;
      } else if (h.contains('item') || h.contains('بند')) {
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

  void _applyBulkSection() {
    if (_bulkSection != null) {
      setState(() {
        for (var record in _newRecords) {
          final index = _allExcelData.indexOf(record);
          _rowSections[index] = _bulkSection!;
        }
      });
    }
  }

  void _applyBulkDate() {
    if (_bulkDate != null) {
      setState(() {
        for (var record in _newRecords) {
          final index = _allExcelData.indexOf(record);
          _rowPickupDates[index] = _bulkDate;
        }
      });
    }
  }

  Future<void> _pickDateForRow(int index) async {
    final date = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (date != null) setState(() => _rowPickupDates[index] = date);
  }

  Future<void> _importNewRecords() async {
    if (_newRecords.isEmpty) {
      _showMessage('No new records to import');
      return;
    }

    setState(() => _isLoading = true);
    final supabase = Supabase.instance.client;
    int imported = 0, failed = 0;

    // Today's date for O-Date (order date)
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final enrichedRecords = _newRecords.map((record) {
      final index = _allExcelData.indexOf(record);

      // Parse value - remove commas
      double? parsedValue;
      final rawValue = record['value']?.toString().replaceAll(',', '') ?? '0';
      parsedValue = double.tryParse(rawValue) ?? 0;

      // Parse delivery date - handle DD.MM.YYYY format
      String? deliveryDate;
      final rawDeliveryDate = record['delivery_date']?.toString().trim();
      if (rawDeliveryDate != null && rawDeliveryDate.isNotEmpty) {
        try {
          final parts = rawDeliveryDate.split('.');
          if (parts.length == 3) {
            final day = parts[0].padLeft(2, '0');
            final month = parts[1].padLeft(2, '0');
            final year = parts[2].length == 2 ? '20${parts[2]}' : parts[2];
            deliveryDate = '$year-$month-$day';
          } else {
            deliveryDate = rawDeliveryDate;
          }
        } catch (e) {
          deliveryDate = rawDeliveryDate;
        }
      }

      return {
        'status': _rowSections[index] ?? 'Unknown',
        'customer_name': record['customer_name'] ?? '',
        'item_number': record['item_number'] ?? '',
        'product_code': record['product_code'] ?? '',
        'contract_number': record['contract_number'] ?? '',
        'description': record['description'] ?? '',
        'design_order': record['design_order'] ?? '',
        'quantity': double.tryParse(record['quantity']?.toString() ?? '0') ?? 0,
        'unit_of_measure': record['unit_of_measure'] ?? 'EA',
        'value': parsedValue,
        'sales_engineer': record['sales_engineer'] ?? '',
        'order_date': today, // O-Date = today (import date)
        'delivery_date': deliveryDate,
        'factory': record['factory'] ?? null,
        'design_team': record['design_team'] ?? null,
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
        print('✅ Batch ${i ~/ 500 + 1}: ${batch.length} records');
      } catch (e) {
        print('❌ Batch failed: $e');
        for (var record in batch) {
          try {
            await supabase.from('sap_main_orders').insert(record);
            imported++;
          } catch (innerE) {
            failed++;
            print('  Failed: ${record['design_order']} - $innerE');
          }
        }
      }
    }

    setState(() => _isLoading = false);

    if (mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Import Complete',
            style: GoogleFonts.cairo(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildResultRow('Imported:', '$imported', greenColor),
              const SizedBox(height: 4),
              _buildResultRow(
                'Failed:',
                '$failed',
                failed > 0 ? redColor : Colors.grey,
              ),
              const SizedBox(height: 4),
              _buildResultRow(
                'Duplicates skipped:',
                '$_duplicateRows',
                orangeColor,
              ),
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
              child: Text(
                'Done',
                style: GoogleFonts.cairo(color: Colors.white),
              ),
            ),
          ],
        ),
      );
    }
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
            if (_fileLoaded) _buildBulkAssignBar(),
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
                  style: GoogleFonts.cairo(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: primaryColor,
                  ),
                ),
                if (_fileLoaded)
                  Text(
                    '$_fileName • $_totalRows rows',
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      color: const Color(0xFF64748B),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Widget _buildBulkAssignBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFEFCE8),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_fix_high, color: orangeColor, size: 16),
          const SizedBox(width: 8),
          Text(
            'Bulk assign:',
            style: GoogleFonts.cairo(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primaryColor,
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              value: _bulkSection,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Section (all)',
                labelStyle: GoogleFonts.cairo(fontSize: 11),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                filled: true,
                fillColor: Colors.white,
                isDense: true,
              ),
              items: _sections
                  .map(
                    (s) => DropdownMenuItem(
                      value: s,
                      child: Text(
                        s,
                        style: GoogleFonts.cairo(fontSize: 11),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (v) {
                setState(() => _bulkSection = v);
                _applyBulkSection();
              },
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 160,
            child: InkWell(
              onTap: () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (date != null) {
                  setState(() => _bulkDate = date);
                  _applyBulkDate();
                }
              },
              child: InputDecorator(
                decoration: InputDecoration(
                  labelText: 'Date (all)',
                  labelStyle: GoogleFonts.cairo(fontSize: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  isDense: true,
                ),
                child: Text(
                  _bulkDate != null
                      ? DateFormat('yyyy-MM-dd').format(_bulkDate!)
                      : 'Select',
                  style: GoogleFonts.cairo(fontSize: 11),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          if (_bulkSection != null || _bulkDate != null)
            TextButton(
              onPressed: () {
                setState(() {
                  _bulkSection = null;
                  _bulkDate = null;
                });
              },
              child: Text(
                'Clear',
                style: GoogleFonts.cairo(fontSize: 11, color: Colors.red),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading)
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: primaryColor),
            SizedBox(height: 16),
            Text('Processing file...'),
          ],
        ),
      );
    if (!_fileLoaded) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(40),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 2),
              ),
              child: const Icon(
                Icons.cloud_upload_outlined,
                size: 80,
                color: Color(0xFF94A3B8),
              ),
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
            const SizedBox(height: 8),
            Text(
              'Supported: .xlsx, .xls, .csv',
              style: GoogleFonts.cairo(
                fontSize: 14,
                color: const Color(0xFF64748B),
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
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              _buildSummaryCard(
                'New Records',
                '$_newRows',
                greenColor,
                Icons.add_circle_outline,
              ),
              const SizedBox(width: 12),
              _buildSummaryCard(
                'Duplicates',
                '$_duplicateRows',
                orangeColor,
                Icons.content_copy,
              ),
              const SizedBox(width: 12),
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
          margin: const EdgeInsets.symmetric(horizontal: 16),
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
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.cairo(
                    fontSize: 12,
                    color: const Color(0xFF64748B),
                  ),
                ),
                Text(
                  count,
                  style: GoogleFonts.cairo(
                    fontSize: 20,
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
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.cairo(
              fontSize: 13,
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

    if (displayData.isEmpty)
      return Center(
        child: Text(
          'No data to display',
          style: GoogleFonts.cairo(color: const Color(0xFF64748B)),
        ),
      );

    return ListView.builder(
      itemCount: displayData.length > 100 ? 100 : displayData.length,
      itemBuilder: (context, rowIndex) {
        final record = displayData[rowIndex];
        final globalIndex = _allExcelData.indexOf(record);
        final section = _rowSections[globalIndex];
        final date = _rowPickupDates[globalIndex];

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            color: _selectedTab == 1 ? Colors.orange.shade50 : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${rowIndex + 1}',
                  style: GoogleFonts.cairo(fontSize: 10, color: Colors.grey),
                ),
              ),
              // Customer Name
              SizedBox(
                width: 130,
                child: Text(
                  record['customer_name']?.toString() ?? '',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Design Order
              SizedBox(
                width: 80,
                child: Text(
                  record['design_order']?.toString() ?? '',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    color: blueColor,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Value
              SizedBox(
                width: 80,
                child: Text(
                  record['value']?.toString() ?? '',
                  style: GoogleFonts.cairo(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: greenColor,
                  ),
                  textAlign: TextAlign.right,
                ),
              ),
              // Contract Num
              SizedBox(
                width: 90,
                child: Text(
                  record['contract_number']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Item
              SizedBox(
                width: 50,
                child: Text(
                  record['item_number']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 11),
                ),
              ),
              // Product Code
              SizedBox(
                width: 120,
                child: Text(
                  record['product_code']?.toString() ?? '',
                  style: GoogleFonts.cairo(
                    fontSize: 10,
                    color: const Color(0xFF475569),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Description
              Expanded(
                child: Text(
                  record['description']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 11),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ),
              // QTY
              SizedBox(
                width: 40,
                child: Text(
                  record['quantity']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              // Unit
              SizedBox(
                width: 35,
                child: Text(
                  record['unit_of_measure']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              // Sales Engineer
              SizedBox(
                width: 100,
                child: Text(
                  record['sales_engineer']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 10),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Factory
              SizedBox(
                width: 50,
                child: Text(
                  record['factory']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
              // Delivery Date
              SizedBox(
                width: 80,
                child: Text(
                  record['delivery_date']?.toString() ?? '',
                  style: GoogleFonts.cairo(fontSize: 10),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),
              // Section Dropdown
              SizedBox(
                width: 140,
                child: DropdownButtonFormField<String>(
                  value: section,
                  isExpanded: true,
                  decoration: InputDecoration(
                    hintText: 'Status',
                    hintStyle: GoogleFonts.cairo(
                      fontSize: 9,
                      color: Colors.grey,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    isDense: true,
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  style: GoogleFonts.cairo(fontSize: 10),
                  items: _sections
                      .map(
                        (s) => DropdownMenuItem(
                          value: s,
                          child: Text(
                            s,
                            style: GoogleFonts.cairo(fontSize: 9),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _rowSections[globalIndex] = v!),
                ),
              ),
            ],
          ),
        );
      },
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
                ? 'Ready to import $_newRows new records'
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
            onPressed: (_fileLoaded && _newRows > 0) ? _importNewRecords : null,
            icon: const Icon(Icons.upload, size: 18),
            label: Text(
              'Import $_newRows Records',
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
