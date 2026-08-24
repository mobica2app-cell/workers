// lib/services/user_preferences_service.dart
import 'dart:convert';
import 'package:universal_html/html.dart' as html;

class UserPreferencesService {
  // Keys for localStorage
  static const String _themeKey = 'user_theme';
  static const String _columnOrderKey = 'user_column_order';
  static const String _visibleColumnsKey = 'user_visible_columns';
  static const String _expandedSectionsKey = 'user_expanded_sections';

  final String userId;

  UserPreferencesService(this.userId);

  String _getKey(String key) => '${userId}_$key';

  // ==================== THEME ====================
  bool get isDarkMode {
    final saved = html.window.localStorage[_getKey(_themeKey)];
    return saved == 'dark';
  }

  void saveTheme(bool isDark) {
    html.window.localStorage[_getKey(_themeKey)] = isDark ? 'dark' : 'light';
  }

  // ==================== COLUMN ORDER ====================
  List<String>? getColumnOrder() {
    final saved = html.window.localStorage[_getKey(_columnOrderKey)];
    if (saved == null || saved.isEmpty) return null;
    try {
      return List<String>.from(jsonDecode(saved));
    } catch (e) {
      return null;
    }
  }

  void saveColumnOrder(List<String> order) {
    html.window.localStorage[_getKey(_columnOrderKey)] = jsonEncode(order);
  }

  // ==================== VISIBLE COLUMNS ====================
  Set<String>? getVisibleColumns() {
    final saved = html.window.localStorage[_getKey(_visibleColumnsKey)];
    if (saved == null || saved.isEmpty) return null;
    try {
      return Set<String>.from(jsonDecode(saved));
    } catch (e) {
      return null;
    }
  }

  void saveVisibleColumns(Set<String> columns) {
    html.window.localStorage[_getKey(_visibleColumnsKey)] = jsonEncode(columns.toList());
  }

  // ==================== EXPANDED SECTIONS ====================
  Set<String>? getExpandedSections() {
    final saved = html.window.localStorage[_getKey(_expandedSectionsKey)];
    if (saved == null || saved.isEmpty) return null;
    try {
      return Set<String>.from(jsonDecode(saved));
    } catch (e) {
      return null;
    }
  }

  void saveExpandedSections(Set<String> sections) {
    html.window.localStorage[_getKey(_expandedSectionsKey)] = jsonEncode(sections.toList());
  }

  // Clear all preferences
  void clearAll() {
    html.window.localStorage.remove(_getKey(_themeKey));
    html.window.localStorage.remove(_getKey(_columnOrderKey));
    html.window.localStorage.remove(_getKey(_visibleColumnsKey));
    html.window.localStorage.remove(_getKey(_expandedSectionsKey));
  }
}