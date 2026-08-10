// lib/repositories/sap_repository.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sap_models.dart';

abstract class ISAPRepository {
  Future<List<Map<String, dynamic>>> getOrders(SAPOrderFilter filter);
  Future<int> getOrdersCount(SAPOrderFilter filter);
  Future<List<Map<String, dynamic>>> getOrderByNumber(String orderNumber);
  Future<List<Map<String, dynamic>>> searchOrders(String searchTerm);
}

class SupabaseSAPRepository implements ISAPRepository {
  final SupabaseClient _client;

  SupabaseSAPRepository(this._client);

  @override
  Future<int> getOrdersCount(SAPOrderFilter filter) async {
    try {
      int totalCount = 0;
      int page = 0;
      const int batchSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final start = page * batchSize;
        final end = start + batchSize - 1;

        List<dynamic> response;

        if (filter.searchTerm != null && filter.searchTerm!.isNotEmpty) {
          response = await _client
              .from('sap_orders_view')
              .select('order_number')
              .or(
            'description.ilike.%${filter.searchTerm}%,'
                'customer_name.ilike.%${filter.searchTerm}%,'
                'product_code.ilike.%${filter.searchTerm}%,'
                'order_number.ilike.%${filter.searchTerm}%',
          )
              .range(start, end);
        } else {
          var query = _client.from('sap_orders_view').select('order_number');

          if (filter.customerName != null && filter.customerName!.isNotEmpty) {
            query = query.ilike('customer_name', '%${filter.customerName}%');
          }
          if (filter.orderNumber != null && filter.orderNumber!.isNotEmpty) {
            query = query.eq('order_number', filter.orderNumber!);
          }

          response = await query.range(start, end);
        }

        totalCount += response.length;

        // If we got less than batchSize, we've reached the end
        if (response.length < batchSize) {
          hasMore = false;
        } else {
          page++;
        }
      }

      return totalCount;
    } catch (e) {
      print('Error getting orders count: $e');
      return 0;
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getOrders(SAPOrderFilter filter) async {
    try {
      final start = filter.page * filter.pageSize;
      final end = start + filter.pageSize - 1;

      List<dynamic> response;

      if (filter.searchTerm != null && filter.searchTerm!.isNotEmpty) {
        response = await _client
            .from('sap_orders_view')
            .select('*')
            .or(
          'description.ilike.%${filter.searchTerm}%,'
              'customer_name.ilike.%${filter.searchTerm}%,'
              'product_code.ilike.%${filter.searchTerm}%,'
              'order_number.ilike.%${filter.searchTerm}%',
        )
            .order(filter.sortBy, ascending: filter.ascending)
            .range(start, end);
      } else {
        var query = _client.from('sap_orders_view').select('*');

        if (filter.customerName != null && filter.customerName!.isNotEmpty) {
          query = query.ilike('customer_name', '%${filter.customerName}%');
        }
        if (filter.orderNumber != null && filter.orderNumber!.isNotEmpty) {
          query = query.eq('order_number', filter.orderNumber!);
        }

        response = await query
            .order(filter.sortBy, ascending: filter.ascending)
            .range(start, end);
      }

      return response.cast<Map<String, dynamic>>();
    } catch (e) {
      throw Exception('Failed to fetch orders: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getOrderByNumber(String orderNumber) async {
    try {
      final response = await _client
          .from('sap_orders_view')
          .select('*')
          .eq('order_number', orderNumber);

      return response.cast<Map<String, dynamic>>();
    } catch (e) {
      throw Exception('Failed to fetch order: $e');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchOrders(String searchTerm) async {
    return getOrders(SAPOrderFilter(searchTerm: searchTerm));
  }
}

class RealSAPRepository implements ISAPRepository {
  final String sapBaseUrl;
  final String sapApiKey;

  RealSAPRepository({required this.sapBaseUrl, required this.sapApiKey});

  @override
  Future<int> getOrdersCount(SAPOrderFilter filter) async {
    throw UnimplementedError('Real SAP API not yet implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> getOrders(SAPOrderFilter filter) async {
    throw UnimplementedError('Real SAP API not yet implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> getOrderByNumber(String orderNumber) async {
    throw UnimplementedError('Real SAP API not yet implemented');
  }

  @override
  Future<List<Map<String, dynamic>>> searchOrders(String searchTerm) async {
    throw UnimplementedError('Real SAP API not yet implemented');
  }
}