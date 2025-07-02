import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard_example/clipboard_controller.dart'; // For ClipboardHistoryItem
import 'history_store.dart'; // For IClipboardHistoryStore

/// An implementation of [IClipboardHistoryStore] that uses [SharedPreferences]
/// to persist the clipboard history.
///
/// Data is stored as a JSON string under a predefined key.
class SharedPreferencesHistoryStore implements IClipboardHistoryStore {
  static const String _historyKey = 'clipboard_history';

  @override
  Future<List<ClipboardHistoryItem>> loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? historyJson = prefs.getString(_historyKey);

      if (historyJson == null || historyJson.isEmpty) {
        return [];
      }

      final List<dynamic> decodedList = jsonDecode(historyJson);
      final List<ClipboardHistoryItem> history = decodedList
          .map((dynamic itemJson) =>
              ClipboardHistoryItem.fromJson(itemJson as Map<String, dynamic>))
          .toList();

      // After loading, it's good practice to generate previews if they weren't persisted
      // or if the logic for preview generation might have changed.
      // For items loaded from persistence, readerItems will be empty initially.
      // generatePreview will use persistableItems.
      for (final item in history) {
        if (!item.isPreviewReady.value) {
          // No await here, let them generate in background. UI will update via Obx.
          item.generatePreview();
        }
      }
      return history;
    } catch (e) {
      print("Error loading history from SharedPreferences: $e");
      // In case of error (e.g., corrupted data), return an empty list or handle appropriately.
      return [];
    }
  }

  @override
  Future<void> saveHistory(List<ClipboardHistoryItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Convert each ClipboardHistoryItem to its JSON representation.
      final List<Map<String, dynamic>> encodedList =
          items.map((item) => item.toJson()).toList();
      final String historyJson = jsonEncode(encodedList);
      await prefs.setString(_historyKey, historyJson);
    } catch (e) {
      print("Error saving history to SharedPreferences: $e");
      // Handle error (e.g., log it, notify user if critical).
    }
  }

  @override
  Future<void> clearHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_historyKey);
    } catch (e) {
      print("Error clearing history from SharedPreferences: $e");
      // Handle error.
    }
  }
}
