// lib/services/csv_export_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:mobitem/services/sap_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import '../models/sap_models.dart';

class CSVExportService {

  // Add these imports at the top if not already there

// Add these methods inside the CSVExportService class:

// ==================== SAPMainOrder Methods ====================

  static Future<String> exportOrdersToCSVMain(List<SAPMainOrder> orders) async {
    StringBuffer csvContent = StringBuffer();
    csvContent.write('\u{FEFF}');

    // Headers - All 18 columns
    List<String> headers = [
      'Name', 'Status', 'Item', 'Product Code', 'Contract Num',
      'Description', 'Design Order', 'QTY', 'Unit of Measure', 'Value',
      'Sales Engineer', 'O-Date', 'Delivery Date', 'Factory',
      'Design Team', 'Responsible Engineer', 'Reviewer', 'Correspondence Engineer'
    ];
    csvContent.writeln(headers.join(','));

    // Data rows
    for (var order in orders) {
      List<String> row = [
        _escapeCSV(order.customerName),
        _escapeCSV(order.status),
        _escapeCSV(order.itemNumber),
        _escapeCSV(order.productCode),
        _escapeCSV(order.contractNumber),
        _escapeCSV(order.description),
        _escapeCSV(order.designOrder),
        '${order.quantity}',
        _escapeCSV(order.unitOfMeasure),
        _escapeCSV(_formatNumber(order.value)),
        _escapeCSV(order.salesEngineer),
        _escapeCSV(order.orderDate ?? ''),
        _escapeCSV(order.deliveryDate ?? ''),
        _escapeCSV(order.factory ?? ''),
        _escapeCSV(order.designTeam ?? ''),
        _escapeCSV(order.responsibleEngineer ?? ''),
        _escapeCSV(order.reviewer ?? ''),
        _escapeCSV(order.correspondenceEngineer ?? ''),
      ];
      csvContent.writeln(row.join(','));
    }

    final csvString = csvContent.toString();
    final fileName = 'orders_export_${DateTime.now().millisecondsSinceEpoch}.csv';

    if (kIsWeb) {
      final bytes = utf8.encode(csvString);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = fileName;
      html.document.body!.children.add(anchor);
      anchor.click();
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
      return fileName;
    } else {
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvString, encoding: utf8);
      return filePath;
    }
  }

  static Future<String> _generateCSVStringMain(List<SAPMainOrder> orders) async {
    StringBuffer csvContent = StringBuffer();
    csvContent.write('\u{FEFF}');

    List<String> headers = [
      'Name', 'Status', 'Item', 'Product Code', 'Contract Num',
      'Description', 'Design Order', 'QTY', 'Unit of Measure', 'Value',
      'Sales Engineer', 'O-Date', 'Delivery Date', 'Factory',
      'Design Team', 'Responsible Engineer', 'Reviewer', 'Correspondence Engineer'
    ];
    csvContent.writeln(headers.join(','));

    for (var order in orders) {
      List<String> row = [
        _escapeCSV(order.customerName),
        _escapeCSV(order.status),
        _escapeCSV(order.itemNumber),
        _escapeCSV(order.productCode),
        _escapeCSV(order.contractNumber),
        _escapeCSV(order.description),
        _escapeCSV(order.designOrder),
        '${order.quantity}',
        _escapeCSV(order.unitOfMeasure),
        _escapeCSV(_formatNumber(order.value)),
        _escapeCSV(order.salesEngineer),
        _escapeCSV(order.orderDate ?? ''),
        _escapeCSV(order.deliveryDate ?? ''),
        _escapeCSV(order.factory ?? ''),
        _escapeCSV(order.designTeam ?? ''),
        _escapeCSV(order.responsibleEngineer ?? ''),
        _escapeCSV(order.reviewer ?? ''),
        _escapeCSV(order.correspondenceEngineer ?? ''),
      ];
      csvContent.writeln(row.join(','));
    }
    return csvContent.toString();
  }

  static Future<String> saveCSVFileMain(List<SAPMainOrder> orders, String fileName) async {
    try {
      final csvString = await _generateCSVStringMain(orders);

      if (kIsWeb) {
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes], 'text/csv');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = '$fileName.csv';
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        return '$fileName.csv (downloaded)';
      } else {
        String tempPath = await exportOrdersToCSVMain(orders);
        final tempFile = File(tempPath);

        Directory saveDirectory;
        try {
          String? userProfile = Platform.environment['USERPROFILE'];
          if (userProfile != null) {
            saveDirectory = Directory('$userProfile\\Downloads');
          } else {
            saveDirectory = await getApplicationDocumentsDirectory();
          }
          if (!await saveDirectory.exists()) {
            await saveDirectory.create(recursive: true);
          }
        } catch (e) {
          saveDirectory = await getApplicationDocumentsDirectory();
        }

        final finalPath = '${saveDirectory.path}\\$fileName.csv';
        final savedFile = File(finalPath);
        await savedFile.writeAsBytes(await tempFile.readAsBytes());

        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        return finalPath;
      }
    } catch (e) {
      throw Exception('Error saving CSV file: $e');
    }
  }

  // Format number with commas
  static String _formatNumber(double number) {
    if (number == 0) return '0.00';

    final isNegative = number < 0;
    final absNumber = number.abs();
    final parts = absNumber.toStringAsFixed(2).split('.');
    final wholePart = parts[0];
    final decimalPart = parts[1];

    final buffer = StringBuffer();
    for (int i = 0; i < wholePart.length; i++) {
      if (i > 0 && (wholePart.length - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(wholePart[i]);
    }

    return '${isNegative ? '-' : ''}${buffer.toString()}.$decimalPart';
  }

  static Future<String> exportOrdersToCSV(List<SAPOrderHeader> orders) async {
    // Create CSV content
    StringBuffer csvContent = StringBuffer();

    // Add BOM for UTF-8 encoding
    csvContent.write('\u{FEFF}');

    // Headers
    List<String> headers = [
      'Name',
      'Contract Num',
      'Design Order',
      'Item',
      'Product Code',
      'Description',
      'QTY',
      'Unit',
      'Value'
    ];
    csvContent.writeln(headers.join(','));

    // Data rows
    for (var order in orders) {
      var firstItem = order.items.isNotEmpty ? order.items.first : null;

      List<String> row = [
        _escapeCSV(order.kunnrName ?? ''),
        _escapeCSV(order.vbelnContract ?? ''),
        _escapeCSV(order.vbeln ?? ''),
        _escapeCSV(firstItem?.posnr?.toString() ?? '-'),
        _escapeCSV(firstItem?.matnr ?? '-'),
        _escapeCSV(firstItem?.arktx ?? '-'),
        firstItem?.kwmeng?.toString() ?? '0',
        _escapeCSV(firstItem?.vrkme ?? 'EA'),
        _escapeCSV(_formatNumber(firstItem?.netwr ?? 0)), // Formatted with commas
      ];
      csvContent.writeln(row.join(','));
    }

    final csvString = csvContent.toString();
    final fileName = 'orders_export_${DateTime.now().millisecondsSinceEpoch}.csv';

    if (kIsWeb) {
      // For web: use Blob download
      final bytes = utf8.encode(csvString);
      final blob = html.Blob([bytes], 'text/csv');
      final url = html.Url.createObjectUrlFromBlob(blob);
      final anchor = html.document.createElement('a') as html.AnchorElement
        ..href = url
        ..style.display = 'none'
        ..download = fileName;
      html.document.body!.children.add(anchor);
      anchor.click();
      html.document.body!.children.remove(anchor);
      html.Url.revokeObjectUrl(url);
      return fileName;
    } else {
      // For mobile/desktop: use path_provider
      final directory = await getTemporaryDirectory();
      final filePath = '${directory.path}/$fileName';
      final file = File(filePath);
      await file.writeAsString(csvString, encoding: utf8);
      print('✅ CSV file created with ${orders.length} rows at: $filePath');
      return filePath;
    }
  }

  static String _escapeCSV(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  static Future<void> shareCSVFile(List<SAPOrderHeader> orders, {String? text}) async {
    try {
      final csvString = await _generateCSVString(orders);
      final fileName = 'exported_report_${DateTime.now().millisecondsSinceEpoch}.csv';

      if (kIsWeb) {
        // On web: download directly
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes], 'text/csv');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = fileName;
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
      } else {
        // On mobile/desktop: use share_plus
        String filePath = await exportOrdersToCSV(orders);
      }
    } catch (e) {
      throw Exception('Error exporting to CSV: $e');
    }
  }

  static Future<String> _generateCSVString(List<SAPOrderHeader> orders) async {
    StringBuffer csvContent = StringBuffer();
    csvContent.write('\u{FEFF}');

    List<String> headers = [
      'Name', 'Contract Num', 'Design Order', 'Item',
      'Product Code', 'Description', 'QTY', 'Unit', 'Value'
    ];
    csvContent.writeln(headers.join(','));

    for (var order in orders) {
      var firstItem = order.items.isNotEmpty ? order.items.first : null;
      List<String> row = [
        _escapeCSV(order.kunnrName ?? ''),
        _escapeCSV(order.vbelnContract ?? ''),
        _escapeCSV(order.vbeln ?? ''),
        _escapeCSV(firstItem?.posnr?.toString() ?? '-'),
        _escapeCSV(firstItem?.matnr ?? '-'),
        _escapeCSV(firstItem?.arktx ?? '-'),
        firstItem?.kwmeng?.toString() ?? '0',
        _escapeCSV(firstItem?.vrkme ?? 'EA'),
        _escapeCSV(_formatNumber(firstItem?.netwr ?? 0)), // Formatted with commas
      ];
      csvContent.writeln(row.join(','));
    }
    return csvContent.toString();
  }

  static Future<String> saveCSVFile(List<SAPOrderHeader> orders, String fileName) async {
    try {
      final csvString = await _generateCSVString(orders);

      if (kIsWeb) {
        // On web: trigger download
        final bytes = utf8.encode(csvString);
        final blob = html.Blob([bytes], 'text/csv');
        final url = html.Url.createObjectUrlFromBlob(blob);
        final anchor = html.document.createElement('a') as html.AnchorElement
          ..href = url
          ..style.display = 'none'
          ..download = '$fileName.csv';
        html.document.body!.children.add(anchor);
        anchor.click();
        html.document.body!.children.remove(anchor);
        html.Url.revokeObjectUrl(url);
        return '$fileName.csv (downloaded)';
      } else {
        // On desktop: save to Downloads folder
        String tempPath = await exportOrdersToCSV(orders);
        final tempFile = File(tempPath);

        Directory saveDirectory;
        try {
          String? userProfile = Platform.environment['USERPROFILE'];
          if (userProfile != null) {
            saveDirectory = Directory('$userProfile\\Downloads');
          } else {
            saveDirectory = await getApplicationDocumentsDirectory();
          }
          if (!await saveDirectory.exists()) {
            await saveDirectory.create(recursive: true);
          }
        } catch (e) {
          saveDirectory = await getApplicationDocumentsDirectory();
        }

        final finalPath = '${saveDirectory.path}\\$fileName.csv';
        final savedFile = File(finalPath);
        await savedFile.writeAsBytes(await tempFile.readAsBytes());

        if (await tempFile.exists()) {
          await tempFile.delete();
        }

        print('✅ CSV saved to: $finalPath');
        return finalPath;
      }
    } catch (e) {
      throw Exception('Error saving CSV file: $e');
    }
  }
}