// lib/services/audit_service.dart
import 'package:supabase_flutter/supabase_flutter.dart';

class AuditService {
  final SupabaseClient _client;

  AuditService(this._client);

  // Log a change
  Future<void> logChange({
    required String orderId,
    String? designOrder,
    required String fieldName,
    String? oldValue,
    String? newValue,
    required String changedBy,
    String? changedById,
    String actionType = 'update',
    String? notes,
  }) async {
    try {
      await _client.from('order_audit_log').insert({
        'order_id': orderId,
        'design_order': designOrder,
        'field_name': fieldName,
        'old_value': oldValue,
        'new_value': newValue,
        'changed_by': changedBy,
        'changed_by_id': changedById,
        'action_type': actionType,
        'changed_at': DateTime.now().toIso8601String(),
        'notes': notes,
      });
    } catch (e) {
      print('Error logging audit: $e');
    }
  }

  // Get audit log for a specific order
  Future<List<Map<String, dynamic>>> getOrderAuditLog(String orderId) async {
    try {
      final response = await _client
          .from('order_audit_log')
          .select('*')
          .eq('order_id', orderId)
          .order('changed_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching audit log: $e');
      return [];
    }
  }

  // Get all recent changes
  Future<List<Map<String, dynamic>>> getRecentChanges({int limit = 50}) async {
    try {
      final response = await _client
          .from('order_audit_log')
          .select('*')
          .order('changed_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching recent changes: $e');
      return [];
    }
  }

  // Get changes made by a specific user
  Future<List<Map<String, dynamic>>> getUserChanges(String username, {int limit = 50}) async {
    try {
      final response = await _client
          .from('order_audit_log')
          .select('*')
          .eq('changed_by', username)
          .order('changed_at', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error fetching user changes: $e');
      return [];
    }
  }
}