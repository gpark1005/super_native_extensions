import 'dart:convert'; // For base64Encode/Decode
import 'dart:typed_data';
import 'package:flutter/material.dart'; // Added for Widget type
import 'package:get/get.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:super_clipboard_example/persistence/history_store.dart'; // Import the interface
import 'package:super_clipboard_example/persistence/shared_preferences_history_store.dart'; // Import the concrete implementation
import 'package:super_clipboard_example/widget_for_reader.dart';

import 'dart:async'; // For Timer

// Debouncer class to delay function execution
class Debouncer {
  final int milliseconds;
  Timer? _timer;

  Debouncer({required this.milliseconds});

  run(VoidCallback action) {
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: milliseconds), action);
  }

  cancel() {
    _timer?.cancel();
  }
}

// Helper class to store extracted, serializable data from a DataReaderItem.
// This is what will actually be persisted.
class PersistableDataItem {
  final String? plainText;
  final String? htmlText;
  final String? pngBase64; // Store image bytes as base64 string
  final String? uri; // Store URI as string
  // Add other common types as needed e.g., jpegBase64

  PersistableDataItem({
    this.plainText,
    this.htmlText,
    this.pngBase64,
    this.uri,
  });

  Map<String, dynamic> toJson() => {
        'plainText': plainText,
        'htmlText': htmlText,
        'pngBase64': pngBase64,
        'uri': uri,
      };

  factory PersistableDataItem.fromJson(Map<String, dynamic> json) =>
      PersistableDataItem(
        plainText: json['plainText'],
        htmlText: json['htmlText'],
        pngBase64: json['pngBase64'],
        uri: json['uri'],
      );

  bool get isEmpty => plainText == null && htmlText == null && pngBase64 == null && uri == null;
}

/// Represents a single item stored in the clipboard history.
///
/// Each item holds the raw [DataReaderItem]s from the clipboard,
/// its timestamp, a generated ID, and potentially its source.
/// It also manages reactive properties for UI display, including:
/// - A quick textual or image preview.
/// - A list of fully rendered widgets ([displayWidgets]) for detailed view,
///   loaded asynchronously.
/// - Loading states for preview and full content.
class ClipboardHistoryItem {
  final String id;
  final DateTime timestamp;
  // Store serializable data instead of live DataReaderItems for persistence.
  final List<PersistableDataItem> persistableItems;
  final String? source;

  // Non-persisted, live reader items, only available for items just copied.
  // For items loaded from persistence, this will be empty or reconstructed on demand.
  // This is a simplification; true reconstruction is complex.
  late List<DataReaderItem> readerItems;

  String? preview;
  Uint8List? imagePreview;

  final RxList<Widget> displayWidgets = <Widget>[].obs;
  final RxBool isLoadingWidgets = false.obs;
  final RxBool isPreviewReady = false.obs;

  ClipboardHistoryItem({
    required this.id,
    required this.timestamp,
    required this.persistableItems,
    this.source,
    List<DataReaderItem>? liveReaderItems, // Optional for newly copied items
  }) {
    // If live reader items are provided (i.e., item just copied), use them.
    // Otherwise, for items loaded from persistence, this will be empty.
    // The loadDisplayWidgets method will need to handle creating readers from persistableItems.
    readerItems = liveReaderItems ?? [];
  }


  /// Asynchronously extracts serializable data from live DataReaderItems.
  /// This should be called before an item is first saved.
  static Future<List<PersistableDataItem>> extractPersistableData(
      List<DataReaderItem> liveItems) async {
    List<PersistableDataItem> persistables = [];
    for (final item in liveItems) {
      String? plainText;
      String? htmlText;
      String? pngBase64;
      String? uriValue;

      if (item.reader.canProvide(Formats.plainText)) {
        plainText = await item.reader.readValue(Formats.plainText);
      }
      if (item.reader.canProvide(Formats.htmlText)) {
        htmlText = await item.reader.readValue(Formats.htmlText);
      }
      if (item.reader.canProvide(Formats.png)) {
        final bytes = await item.reader.readValue(Formats.png);
        if (bytes != null) {
          pngBase64 = base64Encode(bytes);
        }
      }
      if (item.reader.canProvide(Formats.uri)) {
         final namedUri = await item.reader.readValue(Formats.uri);
         if (namedUri != null) {
            uriValue = namedUri.uri.toString(); // Just store the URI string
         }
      }
      // Add more types as needed

      final pItem = PersistableDataItem(
          plainText: plainText, htmlText: htmlText, pngBase64: pngBase64, uri: uriValue);
      if (!pItem.isEmpty) {
        persistables.add(pItem);
      }
    }
    return persistables;
  }


  /// Generates a quick preview for the clipboard item.
  /// This version will try to use live readerItems if available,
  /// otherwise, it will use the persistableItems.
  ///
  /// This method attempts to extract a textual summary or a small image
  /// from the [readerItems] to be shown in the history list before the
  /// full content is loaded or when the item is collapsed.
  /// Sets [isPreviewReady] to true upon completion.
  Future<void> generatePreview() async {
    if (isPreviewReady.value) return;

    // Prioritize live reader items if available (item just copied)
    if (readerItems.isNotEmpty) {
      for (final item in readerItems) {
        if (imagePreview == null && item.reader.canProvide(Formats.png)) {
          try {
            imagePreview = await item.reader.readValue(Formats.png);
            if (imagePreview != null) preview = "[Image Item (PNG)]";
          } catch (e) { print("Error reading PNG preview for item ${id}: $e"); }
        }
        if (item.reader.canProvide(Formats.plainText)) {
          final text = await item.reader.readValue(Formats.plainText);
          if (text != null && text.isNotEmpty) {
            preview = text.length > 150 ? '${text.substring(0, 147)}...' : text;
            if (imagePreview != null && text.length > 20) preview = "[Image Item (PNG)]";
            break;
          }
        }
        if (preview == null && item.reader.canProvide(Formats.htmlText)) {
          final htmlText = await item.reader.readValue(Formats.htmlText);
          if (htmlText != null && htmlText.isNotEmpty) {
            final plainFromHtml = htmlText.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ').trim();
            preview = plainFromHtml.length > 150 ? '${plainFromHtml.substring(0, 147)}...' : plainFromHtml;
            if (imagePreview != null && plainFromHtml.length > 20) preview = "[Image Item (HTML)]";
            break;
          }
        }
      }
    } else if (persistableItems.isNotEmpty) {
      // Fallback to persisted data if no live readers
      for (final pItem in persistableItems) {
        if (imagePreview == null && pItem.pngBase64 != null) {
          try {
            imagePreview = base64Decode(pItem.pngBase64!);
            if (imagePreview != null) preview = "[Image Item (PNG)]";
          } catch (e) { print("Error decoding PNG preview for item ${id}: $e");}
        }
        if (pItem.plainText != null && pItem.plainText!.isNotEmpty) {
          preview = pItem.plainText!.length > 150 ? '${pItem.plainText!.substring(0, 147)}...' : pItem.plainText!;
          if (imagePreview != null && pItem.plainText!.length > 20) preview = "[Image Item (PNG)]";
          break;
        }
        if (preview == null && pItem.htmlText != null && pItem.htmlText!.isNotEmpty) {
          final plainFromHtml = pItem.htmlText!.replaceAll(RegExp(r'<[^>]*>|&[^;]+;'), ' ').trim();
          preview = plainFromHtml.length > 150 ? '${plainFromHtml.substring(0, 147)}...' : plainFromHtml;
          if (imagePreview != null && plainFromHtml.length > 20) preview = "[Image Item (HTML)]";
          break;
        }
      }
    }

    if (preview == null && imagePreview == null) {
      preview = "[Unsupported or empty data type]";
    }
    isPreviewReady.value = true;
  }

  /// Loads the full, rich widgets for displaying this clipboard item's content.
  /// This version needs to be able to reconstruct DataReader instances from persistableItems
  /// or indicate that live data is not available.
  ///
  /// Uses [buildWidgetsForReaders] from `widget_for_reader.dart` to generate
  /// the UI elements based on the available data formats in [readerItems].
  /// This method is typically called when the user expands the item in the UI.
  ///
  /// - [context]: The [BuildContext] required by `buildWidgetsForReaders`.
  Future<void> loadDisplayWidgets(BuildContext context) async {
    if (isLoadingWidgets.value || displayWidgets.isNotEmpty) return;

    isLoadingWidgets.value = true;
    try {
      List<DataReaderItem> itemsToProcess = readerItems;

      // If live readerItems are empty (e.g., loaded from persistence),
      // try to reconstruct them from persistableItems.
      if (itemsToProcess.isEmpty && persistableItems.isNotEmpty) {
        itemsToProcess = await _reconstructReaderItemsFromPersistables();
        // Update readerItems so they can be used by copyItemToClipboard if needed
        readerItems = itemsToProcess;
      }

      if (itemsToProcess.isEmpty) {
        displayWidgets.add(const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text("No displayable content found for this item. It might have been loaded from a previous session and some data types could not be fully restored."),
        ));
        isLoadingWidgets.value = false;
        return;
      }

      final List<ReaderInfo> infos = [];
      for (final item in itemsToProcess) {
        try {
          final info = await ReaderInfo.fromReader(item.reader);
          infos.add(info);
        } catch (e) {
          print("Error creating ReaderInfo for item ${id}: $e");
          displayWidgets.add(Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text("Error loading part of content: $e", style: TextStyle(color: Colors.red)),
          ));
        }
      }

      if (infos.isNotEmpty) {
        final List<Widget> widgets = await buildWidgetsForReaders(context, infos);
        if (widgets.isNotEmpty) {
          displayWidgets.assignAll(widgets);
        } else {
           displayWidgets.add(const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text("No suitable representations found to display."),
          ));
        }
      } else if (displayWidgets.isEmpty) { // Ensure we add a message if infos is empty AND no partial errors added widgets
        displayWidgets.add(const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text("Could not load any content representations for this item."),
        ));
      }
    } catch (e) {
      print("Error loading display widgets for item ${id}: $e");
      displayWidgets.assignAll([Padding(
        padding: const EdgeInsets.all(8.0),
        child: Text("Error loading content: $e", style: TextStyle(color: Colors.red)),
      )]);
    } finally {
      isLoadingWidgets.value = false;
    }
  }

  /// Attempts to reconstruct DataReaderItems from PersistableDataItems.
  /// This is a simplified reconstruction, mainly for display.
  Future<List<DataReaderItem>> _reconstructReaderItemsFromPersistables() async {
    List<DataReaderItem> reconstructed = [];
    for (final pItem in persistableItems) {
      final writerItem = DataWriterItem(); // Use a DataWriter to build up data
      bool added = false;
      if (pItem.plainText != null) {
        writerItem.add(Formats.plainText(pItem.plainText!));
        added = true;
      }
      if (pItem.htmlText != null) {
        writerItem.add(Formats.htmlText(pItem.htmlText!));
        added = true;
      }
      if (pItem.pngBase64 != null) {
        try {
          final bytes = base64Decode(pItem.pngBase64!);
          writerItem.add(Formats.png(bytes));
          added = true;
        } catch (e) {
          print("Error decoding base64 PNG for item $id: $e");
        }
      }
      if (pItem.uri != null) {
        try {
          writerItem.add(Formats.uri(NamedUri(Uri.parse(pItem.uri!)))); // Assuming no name for persisted URI
          added = true;
        } catch (e) {
          print("Error parsing URI for item $id: $e");
        }
      }

      if (added) {
        // To get a DataReaderItem, we need a DataProvider.
        // We can create a ClipboardDataProvider from the DataWriterItem.
        final dataProvider = ClipboardDataProvider(writerItem.toDataProviderHandle());
        // Then create a DataReader from this provider.
        // This is a bit of a workaround to get a live DataReader.
        final tempReader = await SystemClipboard.instance!.readFromProvider(dataProvider);
        reconstructed.addAll(tempReader.items);
      }
    }
    return reconstructed;
  }


  Future<String?> getPrimaryText() async {
    // Try live reader items first
    if (readerItems.isNotEmpty) {
      for (final item in readerItems) {
        if (item.reader.canProvide(Formats.plainText)) {
          return await item.reader.readValue(Formats.plainText);
        }
        if (item.reader.canProvide(Formats.htmlText)) {
          return await item.reader.readValue(Formats.htmlText);
        }
      }
    }
    // Fallback to persisted items
    for (final pItem in persistableItems) {
      if (pItem.plainText != null) return pItem.plainText;
      if (pItem.htmlText != null) return pItem.htmlText; // Or convert HTML to plain
    }
    return null;
  }

  // --- Serialization Methods ---

  /// Converts this [ClipboardHistoryItem] to a JSON map for persistence.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'timestamp': timestamp.toIso8601String(),
      'source': source,
      'preview': preview,
      'imagePreview': imagePreview != null ? base64Encode(imagePreview!) : null,
      // PersistableItems are already in a good format, just need to call toJson on them
      'persistableItems': persistableItems.map((item) => item.toJson()).toList(),
      // Note: displayWidgets, isLoadingWidgets, isPreviewReady are runtime state, not persisted.
      // readerItems (live ones) are not directly persisted either.
    };
  }

  /// Creates a [ClipboardHistoryItem] from a JSON map.
  factory ClipboardHistoryItem.fromJson(Map<String, dynamic> json) {
    final item = ClipboardHistoryItem(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      source: json['source'] as String?,
      // liveReaderItems will be empty when loading from JSON.
      // They need to be reconstructed if possible by loadDisplayWidgets
      // or copyItemToClipboard based on persistableItems.
      persistableItems: (json['persistableItems'] as List<dynamic>)
          .map((itemJson) =>
              PersistableDataItem.fromJson(itemJson as Map<String, dynamic>))
          .toList(),
    );
    // Restore preview state
    item.preview = json['preview'] as String?;
    if (json['imagePreview'] != null) {
      item.imagePreview = base64Decode(json['imagePreview'] as String);
    }
    // Mark preview as ready if it was restored
    if (item.preview != null || item.imagePreview != null) {
      item.isPreviewReady.value = true;
    }
    return item;
  }
}


/// GetX controller for managing clipboard history and operations.
///
/// This controller handles:
/// - Storing a list of [ClipboardHistoryItem]s.
/// - Adding new items from the system clipboard or application content.
/// - Copying items from history back to the system clipboard.
/// - Removing items from history.
/// - Clearing the entire history.
class ClipboardController extends GetxController {
  /// Observable list of clipboard history items.
  /// UI widgets (like `Obx` or `GetBuilder`) can listen to this list for updates.
  final RxList<ClipboardHistoryItem> history = <ClipboardHistoryItem>[].obs;

  /// Maximum number of items to keep in the clipboard history.
  final int maxHistoryLength = 50;

  // Instance of the history store.
  late final IClipboardHistoryStore _historyStore;

  // --- Search State ---
  /// The current search query. UI elements can bind to this.
  final RxString searchQuery = ''.obs;

  /// Debouncer for search input to avoid filtering on every keystroke.
  final _searchDebouncer = Debouncer(milliseconds: 300);

  /// Observable list of history items that match the current search query.
  /// If the search query is empty, this list contains all history items.
  final RxList<ClipboardHistoryItem> filteredHistory = <ClipboardHistoryItem>[].obs;


  ClipboardController({IClipboardHistoryStore? historyStore}) {
    _historyStore = historyStore ?? SharedPreferencesHistoryStore();
  }

  @override
  void onInit() {
    super.onInit();
    _loadHistoryFromStore().then((_) {
      // Initial filter after loading history
      _filterHistory();
    });

    // Listen to history changes to re-filter and save.
    history.listen((_) {
      _filterHistory(); // Re-filter when the main history changes
      _saveHistoryToStoreDebounced();
    });

    // Listen to search query changes to re-filter.
    searchQuery.listen((query) {
      _searchDebouncer.run(() {
         _filterHistory();
      });
    });

    print("ClipboardController initialized.");
  }

  final _saveDebouncer = Debouncer(milliseconds: 1000);

  Future<void> _loadHistoryFromStore() async {
    final loadedHistory = await _historyStore.loadHistory();
    history.assignAll(loadedHistory); // Load into the main history list
    // filteredHistory will be populated by the listener calling _filterHistory
    print("${loadedHistory.length} items loaded from store.");
  }

  Future<void> _saveHistoryToStore() async {
    // Always save the full history list, not the filtered one.
    await _historyStore.saveHistory(history.toList());
    print("${history.length} items saved to store.");
  }

  void _saveHistoryToStoreDebounced() {
    _saveDebouncer.run(() {
      _saveHistoryToStore();
    });
  }

  /// Filters the main [history] list based on the current [searchQuery]
  /// and updates the [filteredHistory] list.
  void _filterHistory() {
    final query = searchQuery.value.trim().toLowerCase();
    if (query.isEmpty) {
      filteredHistory.assignAll(history);
    } else {
      filteredHistory.assignAll(history.where((item) {
        // Search in preview text. Case-insensitive.
        // Ensure preview is not null.
        return item.preview?.toLowerCase().contains(query) ?? false;
        // TODO: Consider searching in other fields or even full content if feasible.
      }).toList());
    }
  }

  /// Updates the search query. Called by UI when search input changes.
  void updateSearchQuery(String query) {
    searchQuery.value = query;
  }

  @override
  void onClose() {
    _searchDebouncer.cancel();
    _saveDebouncer.cancel();
    _saveHistoryToStore(); // Final save
    print("ClipboardController closed and final history saved.");
    super.onClose();
  }

  /// Adds a new item to the clipboard history from a [ClipboardReader].
  ///
  /// - [reader]: The [ClipboardReader] containing the data to be added.
  /// - [source]: An optional string describing the origin of the data (e.g., "System Paste").
  Future<void> addClipboardReaderToHistory(ClipboardReader reader,
      {String? source}) async {
    final List<DataReaderItem> items = [];
    // Collect all DataReaderItems from the ClipboardReader.
    for (final item in reader.items) {
      items.add(item);
    }

    if (items.isEmpty) {
      Get.snackbar('Info', 'Clipboard reader is empty. Nothing to add to history.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    // Extract serializable data from the live reader items
    final persistableData = await ClipboardHistoryItem.extractPersistableData(items);

    if (persistableData.isEmpty && items.isNotEmpty) {
      // This case means we read something from clipboard but couldn't extract any known
      // persistable format from it. We might still want to store a generic entry
      // or log this. For now, we'll add it with empty persistable data,
      // it will show up as "[Unsupported or empty data type]".
       print("Warning: Clipboard content read, but no persistable data formats extracted.");
    }

    // Create a new history item.
    final newHistoryItem = ClipboardHistoryItem(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      timestamp: DateTime.now(),
      persistableItems: persistableData, // Store the extracted data
      liveReaderItems: items, // Keep live readers for immediate use
      source: source,
    );

    // Generate a quick preview for the new item.
    // The UI can display this while the full content (displayWidgets) loads on demand.
    await newHistoryItem.generatePreview();

    // Add the new item to the beginning of the history list.
    history.insert(0, newHistoryItem);

    // Enforce the maximum history length.
    if (history.length > maxHistoryLength) {
      history.removeRange(maxHistoryLength, history.length);
    }
    // GetX's RxList automatically notifies listeners, so no manual update() call is needed.
    print("Item added to history. Total items: ${history.length}");
  }

  /// Copies a given [ClipboardHistoryItem] back to the system clipboard.
  ///
  /// This method attempts to reconstruct [DataWriterItem]s from the stored
  /// [DataReaderItem]s by reading common data formats (text, HTML, PNG, URI).
  ///
  /// - [historyItem]: The item from history to be copied.
  Future<void> copyItemToClipboard(ClipboardHistoryItem historyItem) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      Get.snackbar('Error', 'Clipboard is not available on this platform.',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    final List<DataWriterItem> writerItems = [];
    // Prioritize using persistableItems for reconstruction, as liveReaderItems might be empty.
    if (historyItem.persistableItems.isNotEmpty) {
      for (final pItem in historyItem.persistableItems) {
        final writerItem = DataWriterItem();
        bool dataAdded = false;
        if (pItem.htmlText != null) {
          writerItem.add(Formats.htmlText(pItem.htmlText!));
          dataAdded = true;
        }
        if (pItem.plainText != null) {
          writerItem.add(Formats.plainText(pItem.plainText!));
          dataAdded = true;
        }
        if (pItem.pngBase64 != null) {
          try {
            final bytes = base64Decode(pItem.pngBase64!);
            writerItem.add(Formats.png(bytes));
            dataAdded = true;
          } catch (e) {
            print("Error decoding base64 PNG for copying item ${historyItem.id}: $e");
          }
        }
        if (pItem.uri != null) {
           try {
            // Reconstruct NamedUri. If name was persisted, it would be used here.
            // For simplicity, not storing name in PersistableDataItem's URI field currently.
            writerItem.add(Formats.uri(NamedUri(Uri.parse(pItem.uri!))));
            dataAdded = true;
          } catch (e) {
            print("Error parsing URI for copying item ${historyItem.id}: $e");
          }
        }
        // Add more types as needed from PersistableDataItem
        if (dataAdded) {
          writerItems.add(writerItem);
        }
      }
    } else if (historyItem.readerItems.isNotEmpty) {
      // Fallback to live reader items if persistable items are empty (should be rare if populated correctly)
      print("Warning: Copying item ${historyItem.id} using live reader items as persistable data was empty.");
      for (final liveReaderItem in historyItem.readerItems) {
        final writerItem = DataWriterItem();
        var dataAddedToThisWriterItem = false;
         if (liveReaderItem.reader.canProvide(Formats.htmlText)) {
            final val = await liveReaderItem.reader.readValue(Formats.htmlText);
            if (val != null) { writerItem.add(Formats.htmlText(val)); dataAddedToThisWriterItem = true; }
        }
        if (liveReaderItem.reader.canProvide(Formats.plainText)) {
            final val = await liveReaderItem.reader.readValue(Formats.plainText);
            if (val != null) { writerItem.add(Formats.plainText(val)); dataAddedToThisWriterItem = true; }
        }
        if (liveReaderItem.reader.canProvide(Formats.png)) {
            final val = await liveReaderItem.reader.readValue(Formats.png);
            if (val != null) { writerItem.add(Formats.png(val)); dataAddedToThisWriterItem = true; }
        }
        if (liveReaderItem.reader.canProvide(Formats.uri)) {
            final val = await liveReaderItem.reader.readValue(Formats.uri);
            if (val != null) { writerItem.add(Formats.uri(val)); dataAddedToThisWriterItem = true; }
        }
        if (dataAddedToThisWriterItem) writerItems.add(writerItem);
      }
    }


    if (writerItems.isNotEmpty) {
      try {
        await clipboard.write(writerItems);
        Get.snackbar(
            'Copied', '${historyItem.preview ?? "Item"} copied to clipboard!',
            snackPosition: SnackPosition.BOTTOM);
      } catch (e) {
        Get.snackbar('Error', 'Failed to write to clipboard: $e',
            snackPosition: SnackPosition.BOTTOM);
        print("Error writing to clipboard: $e");
      }
    } else {
      Get.snackbar('Error',
          'Could not prepare item for copying. Data may be unavailable or in an unsupported format.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  /// Removes a specific item from the clipboard history.
  void removeItemFromHistory(ClipboardHistoryItem item) {
    history.remove(item);
    Get.snackbar('Removed', 'Item removed from history.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 1));
  }

  /// Clears all items from the clipboard history.
  Future<void> clearHistory() async {
    history.clear(); // Clear in-memory list
    await _historyStore.clearHistory(); // Clear from persistent store
    // No need to call _saveHistoryToStore() immediately after clear if store.clearHistory() does its job.
    // However, if clearHistory was just a "mark for deletion" and save is batched, then a save might be needed.
    // For SharedPreferences, removing the key is direct.
    Get.snackbar('Cleared', 'Clipboard history cleared.',
        snackPosition: SnackPosition.BOTTOM);
  }

  // /// (Example) Handles paste events from the system clipboard.
  // /// This would be registered with `ClipboardEvents.instance`.
  // void _handleSystemPasteEvent(ClipboardReadEvent event) async {
  //   print("System paste event detected!");
  //   final reader = await event.getClipboardReader();
  //   addClipboardReaderToHistory(reader, source: "System Event");
  // }
}
