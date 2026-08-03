import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Service for managing app settings and preferences
class SettingsService {
  // Singleton pattern
  SettingsService._internal();
  static final SettingsService _instance = SettingsService._internal();
  factory SettingsService() => _instance;

  static const String _defaultCategoryKey = 'default_category';
  static const String _recentSearchesKey = 'recent_product_searches';
  static const int _maxRecentSearches = 8;

  // Cache the SharedPreferences instance for better performance
  static SharedPreferences? _prefsInstance;

  /// Get SharedPreferences instance with error handling
  Future<SharedPreferences?> _getPrefs() async {
    try {
      _prefsInstance ??= await SharedPreferences.getInstance();
      return _prefsInstance;
    } catch (e) {
      debugPrint('❌ Error getting SharedPreferences: $e');
      if (kIsWeb) {
        debugPrint('⚠️  Web: Make sure localStorage is enabled in your browser');
      }
      return null;
    }
  }

  /// Get the default category preference
  Future<String?> getDefaultCategory() async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return null;

      final value = prefs.getString(_defaultCategoryKey);
      debugPrint('📖 Retrieved default category: $value');
      return value;
    } catch (e) {
      debugPrint('❌ Error getting default category: $e');
      return null;
    }
  }

  /// Set the default category preference
  Future<bool> setDefaultCategory(String category) async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return false;

      final success = await prefs.setString(_defaultCategoryKey, category);
      if (success) {
        debugPrint('✅ Saved default category: $category');
      } else {
        debugPrint('❌ Failed to save default category');
      }
      return success;
    } catch (e) {
      debugPrint('❌ Error setting default category: $e');
      return false;
    }
  }

  /// Clear the default category preference
  Future<bool> clearDefaultCategory() async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return false;

      final success = await prefs.remove(_defaultCategoryKey);
      if (success) {
        debugPrint('🗑️  Cleared default category');
      }
      return success;
    } catch (e) {
      debugPrint('❌ Error clearing default category: $e');
      return false;
    }
  }

  /// Recent product-search terms, most recent first, for quick-tap chips on
  /// the Record Sale screen.
  Future<List<String>> getRecentSearches() async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return [];
      return prefs.getStringList(_recentSearchesKey) ?? [];
    } catch (e) {
      debugPrint('❌ Error getting recent searches: $e');
      return [];
    }
  }

  /// Records a committed search term, moving it to the front (LRU) and
  /// capping the list at [_maxRecentSearches].
  Future<void> addRecentSearch(String term) async {
    final value = term.trim();
    if (value.isEmpty) return;

    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;

      final current = prefs.getStringList(_recentSearchesKey) ?? [];
      current.removeWhere((s) => s.toLowerCase() == value.toLowerCase());
      current.insert(0, value);

      await prefs.setStringList(
        _recentSearchesKey,
        current.take(_maxRecentSearches).toList(),
      );
    } catch (e) {
      debugPrint('❌ Error saving recent search: $e');
    }
  }

  /// Removes a single recent-search entry (e.g. the user dismissed its chip).
  Future<void> removeRecentSearch(String term) async {
    try {
      final prefs = await _getPrefs();
      if (prefs == null) return;

      final current = prefs.getStringList(_recentSearchesKey) ?? [];
      current.removeWhere((s) => s.toLowerCase() == term.toLowerCase());
      await prefs.setStringList(_recentSearchesKey, current);
    } catch (e) {
      debugPrint('❌ Error removing recent search: $e');
    }
  }
}
