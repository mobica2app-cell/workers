// lib/services/sap_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class SAPMainService {
  final SupabaseClient _client;

  SAPMainService(this._client);

  // Get all orders with pagination
  Future<List<SAPMainOrder>> getOrders({
    int page = 0,
    int pageSize = 1000,
    String? searchTerm,
    String? filterStatus,
    String? filterFactory,
    String? filterDesignOrder,
  }) async {
    try {
      var query = _client.from('sap_main_orders').select('*');

      if (searchTerm != null && searchTerm.isNotEmpty) {
        query = query.or(
          'customer_name.ilike.%$searchTerm%,'
              'contract_number.ilike.%$searchTerm%,'
              'design_order.ilike.%$searchTerm%,'
              'description.ilike.%$searchTerm%,'
              'sales_engineer.ilike.%$searchTerm%',
        );
      }

      if (filterStatus != null && filterStatus.isNotEmpty) {
        query = query.eq('status', filterStatus);
      }

      if (filterFactory != null && filterFactory.isNotEmpty) {
        query = query.eq('factory', filterFactory);
      }

      if (filterDesignOrder != null && filterDesignOrder.isNotEmpty) {
        query = query.eq('design_order', filterDesignOrder);
      }

      final start = page * pageSize;
      final end = start + pageSize - 1;

      final response = await query
          .order('design_order', ascending: false)
          .range(start, end);

      return (response as List)
          .map((json) => SAPMainOrder.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      print('Error fetching orders: $e');
      return [];
    }
  }

  // Get order by design order
  Future<SAPMainOrder?> getOrderByDesignOrder(String designOrder) async {
    try {
      final response = await _client
          .from('sap_main_orders')
          .select('*')
          .eq('design_order', designOrder)
          .maybeSingle();

      if (response == null) return null;
      return SAPMainOrder.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      print('Error fetching order: $e');
      return null;
    }
  }

  // Get ALL orders (no pagination) - Loops through all pages
  Future<List<SAPMainOrder>> getAllOrders() async {
    try {
      List<Map<String, dynamic>> allData = [];
      int page = 0;
      const pageSize = 1000;
      bool hasMore = true;

      while (hasMore) {
        final start = page * pageSize;
        final end = start + pageSize - 1;

        final response = await _client
            .from('sap_main_orders')
            .select('*')
            .order('order_date', ascending: true) // Oldest first
            .range(start, end);

        final batch = List<Map<String, dynamic>>.from(response);

        if (batch.isEmpty || batch.length < pageSize) {
          hasMore = false;
        }

        allData.addAll(batch);
        page++;

        print('📦 Fetched page $page: ${batch.length} records (total: ${allData.length})');
      }

      print('✅ Total orders loaded: ${allData.length}');

      return allData
          .map((json) => SAPMainOrder.fromJson(json))
          .toList();
    } catch (e) {
      print('Error fetching all orders: $e');
      return [];
    }
  }

  // Search orders
  Future<List<SAPMainOrder>> searchOrders(String query) async {
    return getOrders(searchTerm: query, pageSize: 100);
  }

  // Get statistics - also needs to fetch ALL records
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final orders = await getAllOrders();

      double totalValue = 0;
      double totalQty = 0;
      final factories = <String>{};
      final engineers = <String>{};

      for (var order in orders) {
        totalValue += order.value;
        totalQty += order.quantity;
        if (order.factory != null && order.factory!.isNotEmpty) factories.add(order.factory!);
        if (order.salesEngineer.isNotEmpty) engineers.add(order.salesEngineer);
      }

      return {
        'total_orders': orders.length,
        'total_value': totalValue,
        'total_quantity': totalQty,
        'unique_factories': factories.length,
        'unique_engineers': engineers.length,
      };
    } catch (e) {
      print('Error getting statistics: $e');
      return {};
    }
  }
}
// lib/models/sap_main_order.dart

class SAPMainOrder {
  final String id;
  final String status;
  final String customerName;
  final String itemNumber;
  final String productCode;
  final String contractNumber;
  final String description;
  final String designOrder;
  final double quantity;
  final String unitOfMeasure;
  final double value;
  final String salesEngineer;
  final String? orderDate;
  final String? endDate;
  final String? deliveryDate;
  final String? factory;
  final String? designTeam;
  final String? responsibleEngineer;
  final String? reviewer;
  final String? correspondenceEngineer;
  final DateTime? createdAt;

  SAPMainOrder({
    required this.id,
    required this.status,
    required this.customerName,
    required this.itemNumber,
    required this.productCode,
    required this.contractNumber,
    required this.description,
    required this.designOrder,
    required this.quantity,
    required this.unitOfMeasure,
    required this.value,
    required this.salesEngineer,
    this.orderDate,
    this.endDate,
    this.deliveryDate,
    this.factory,
    this.designTeam,
    this.responsibleEngineer,
    this.reviewer,
    this.correspondenceEngineer,
    this.createdAt,
  });

  factory SAPMainOrder.fromJson(Map<String, dynamic> json) {
    return SAPMainOrder(
      id: json['id']?.toString() ?? '',
      status: json['status']?.toString() ?? 'Unknown',
      customerName: json['customer_name']?.toString() ?? '',
      itemNumber: json['item_number']?.toString() ?? '',
      productCode: json['product_code']?.toString() ?? '',
      contractNumber: json['contract_number']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      designOrder: json['design_order']?.toString() ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '0') ?? 0,
      unitOfMeasure: json['unit_of_measure']?.toString() ?? 'EA',
      value: double.tryParse(json['value']?.toString() ?? '0') ?? 0,
      salesEngineer: json['sales_engineer']?.toString() ?? '',
      orderDate: json['order_date']?.toString(),
      endDate: json['end_date']?.toString(),
      deliveryDate: json['delivery_date']?.toString(),
      factory: json['factory']?.toString(),
      designTeam: json['design_team']?.toString(),
      responsibleEngineer: json['responsible_engineer']?.toString(),
      reviewer: json['reviewer']?.toString(),
      correspondenceEngineer: json['correspondence_engineer']?.toString(),
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'status': status,
      'customer_name': customerName,
      'item_number': itemNumber,
      'product_code': productCode,
      'contract_number': contractNumber,
      'description': description,
      'design_order': designOrder,
      'quantity': quantity,
      'unit_of_measure': unitOfMeasure,
      'value': value,
      'sales_engineer': salesEngineer,
      'order_date': orderDate,
      'end_date': endDate,
      'delivery_date': deliveryDate,
      'factory': factory,
      'design_team': designTeam,
      'responsible_engineer': responsibleEngineer,
      'reviewer': reviewer,
      'correspondence_engineer': correspondenceEngineer,
    };
  }
}

// lib/models/employee_auth_model.dart

class EmployeeAuth {
  final String id;
  final String username;
  final String fullName;
  final String? department;
  final String? role;
  final String? phoneNumber;
  final bool isActive;
  final DateTime? lastLogin;
  final DateTime createdAt;

  EmployeeAuth({
    required this.id,
    required this.username,
    required this.fullName,
    this.department,
    this.role,
    this.phoneNumber,
    required this.isActive,
    this.lastLogin,
    required this.createdAt,
  });

  factory EmployeeAuth.fromJson(Map<String, dynamic> json) {
    return EmployeeAuth(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      department: json['department']?.toString(),
      role: json['role']?.toString(),
      phoneNumber: json['phone_number']?.toString(),
      isActive: json['is_active'] == true,
      lastLogin: json['last_login'] != null
          ? DateTime.tryParse(json['last_login'])
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'full_name': fullName,
      'department': department,
      'role': role,
      'phone_number': phoneNumber,
      'is_active': isActive,
      'last_login': lastLogin?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
    };
  }

  // Getters
  String get initials {
    if (fullName.isEmpty) return '?';
    return fullName[0].toUpperCase();
  }

  String get displayName {
    if (fullName.length > 20) return '${fullName.substring(0, 18)}...';
    return fullName;
  }
}