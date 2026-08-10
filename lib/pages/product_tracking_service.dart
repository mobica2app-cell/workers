// lib/services/product_tracking_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/product_tracking_model.dart';

class ProductTrackingService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Get tracking for a specific product
  Future<ProductTracking?> getProductTracking(String productCode) async {
    try {
      final response = await _supabase
          .from('product_tracking')
          .select()
          .eq('product_code', productCode)
          .maybeSingle();

      if (response == null) return null;
      return ProductTracking.fromJson(response);
    } catch (e) {
      print('Error fetching product tracking: $e');
      return null;
    }
  }

  // In lib/services/product_tracking_service.dart - Add this method:

  Future<void> insertProductTracking({
    required String productCode,
    required String section,
    required int sectionIndex,
    required String contractNumber,
    required String designOrder,
  }) async {
    try {
      await _supabase.from('product_tracking').insert({
        'product_code': productCode,
        'section': section,
        'section_index': sectionIndex,
        'contract_number': contractNumber,
        'design_order': designOrder,
      });
    } catch (e) {
      print('Error inserting tracking: $e');
      rethrow;
    }
  }

// Also add this batch insert method for better performance:
  Future<void> batchInsertProductTracking(List<Map<String, dynamic>> records) async {
    try {
      await _supabase.from('product_tracking').insert(records);
    } catch (e) {
      print('Error batch inserting: $e');
      rethrow;
    }
  }

  // In lib/services/product_tracking_service.dart
  Future<List<ProductTracking>> getAllProductTracking() async {
    try {
      // Fetch all records (paginate if needed)
      List<Map<String, dynamic>> allData = [];
      int page = 0;
      const pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final start = page * pageSize;
        final end = start + pageSize - 1;

        final response = await _supabase
            .from('product_tracking')
            .select()
            .range(start, end)
            .order('product_code');

        allData.addAll(response);

        if (response.length < pageSize) {
          hasMore = false;
        } else {
          page++;
        }
      }

      print('📊 Loaded ${allData.length} total tracking records');
      return allData.map((json) => ProductTracking.fromJson(json)).toList();
    } catch (e) {
      print('Error loading all tracking: $e');
      return [];
    }
  }

  // Get all products in a design order
  Future<List<ProductTracking>> getDesignOrderProducts(String designOrder) async {
    try {
      final response = await _supabase
          .from('product_tracking')
          .select()
          .eq('design_order', designOrder)
          .order('section_index');

      return response
          .map<ProductTracking>((json) => ProductTracking.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching design order products: $e');
      return [];
    }
  }

  // Get products by contract
  Future<List<ProductTracking>> getContractProducts(String contractNumber) async {
    try {
      final response = await _supabase
          .from('product_tracking')
          .select()
          .eq('contract_number', contractNumber)
          .order('section_index');

      return response
          .map<ProductTracking>((json) => ProductTracking.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching contract products: $e');
      return [];
    }
  }

  // Get products by section
  Future<List<ProductTracking>> getSectionProducts(String section) async {
    try {
      final response = await _supabase
          .from('product_tracking')
          .select()
          .eq('section', section)
          .order('product_code');

      return response
          .map<ProductTracking>((json) => ProductTracking.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching section products: $e');
      return [];
    }
  }

  // Get all sections
  Future<List<String>> getAllSections() async {
    try {
      final response = await _supabase
          .from('product_tracking')
          .select('section');

      final sections = response
          .map<String>((json) => json['section'] as String)
          .toSet()
          .toList();

      sections.sort();
      return sections;
    } catch (e) {
      print('Error fetching sections: $e');
      return [];
    }
  }

  // Batch get tracking for multiple products
  // In product_tracking_service.dart
  Future<Map<String, ProductTracking>> getBatchProductTracking(List<String> productCodes) async {
    try {
      if (productCodes.isEmpty) return {};

      print('🔍 Searching for product codes: ${productCodes.take(5).toList()}...');

      final response = await _supabase
          .from('product_tracking')
          .select()
          .inFilter('product_code', productCodes);

      print('📋 Found ${response.length} matches');

      final Map<String, ProductTracking> result = {};
      for (var json in response) {
        final tracking = ProductTracking.fromJson(json);
        result[tracking.productCode] = tracking;
      }

      // Check which codes weren't found
      final missing = productCodes.where((c) => !result.containsKey(c)).toList();
      print('❌ Missing ${missing.length} product codes:');
      missing.take(10).forEach((c) => print('   $c'));

      return result;
    } catch (e) {
      print('Error fetching batch tracking: $e');
      return {};
    }
  }
}