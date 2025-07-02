import 'package:super_clipboard_example/clipboard_controller.dart'; // For ClipboardHistoryItem

/// Abstract interface for storing and retrieving clipboard history.
/// This allows for different storage mechanisms to be implemented (e.g., SharedPreferences, SQLite, File).
abstract class IClipboardHistoryStore {
  /// Loads the clipboard history from the persistent store.
  ///
  /// Returns a list of [ClipboardHistoryItem]s. If no history is found or an error occurs,
  /// it should ideally return an empty list or handle errors gracefully.
  Future<List<ClipboardHistoryItem>> loadHistory();

  /// Saves the current clipboard history to the persistent store.
  ///
  /// - [items]: The list of [ClipboardHistoryItem]s to save.
  Future<void> saveHistory(List<ClipboardHistoryItem> items);

  /// Clears all clipboard history from the persistent store.
  Future<void> clearHistory();

  /// Adds a single item to the history.
  /// Optional: Useful if we want to save items one by one as they are created.
  /// However, batch saving (via saveHistory) is often more performant.
  // Future<void> addItem(ClipboardHistoryItem item);

  /// Removes a single item from the history.
  /// Optional: Similar to addItem, useful for targeted deletion.
  // Future<void> removeItem(String itemId);
}
