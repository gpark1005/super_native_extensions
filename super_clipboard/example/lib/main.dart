import 'dart:ui' as ui;
import 'dart:typed_data';

import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter_layout_grid/flutter_layout_grid.dart';
import 'package:get/get.dart'; // Import GetX
import 'package:super_clipboard_example/clipboard_controller.dart';
import 'package:super_clipboard_example/history_item_widget.dart'; // Import the history item widget
import 'widget_for_reader.dart'; // Still needed for rendering clipboard data

// Main entry point of the application.
void main() async {
  // Ensures that Flutter bindings are initialized before any Flutter-specific code runs.
  // Necessary for initializing plugins or GetX services before runApp.
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize and register the ClipboardController globally using GetX.
  // This makes the controller accessible throughout the application via `Get.find()`.
  Get.put(ClipboardController());

  runApp(const MyApp());
}

// Constant message for cases where the system clipboard is not available.
const _notAvailableMessage =
    'Clipboard is not available on this platform. Use ClipboardEvents API instead.';

/// Helper function to display a snackbar using GetX.
///
/// - [title]: The title of the snackbar.
/// - [message]: The main message content of the snackbar.
/// - [isError]: If true, styles the snackbar as an error message (e.g., red background).
void showGetSnackbar(String title, String message, {bool isError = false}) {
  Get.snackbar(
    title,
    message,
    snackPosition: SnackPosition.BOTTOM, // Show snackbar at the bottom.
    backgroundColor: isError ? Colors.redAccent : Colors.lightGreen, // Color based on error status.
    colorText: Colors.white, // Text color for readability.
    duration: const Duration(seconds: 3), // How long the snackbar is visible.
    margin: const EdgeInsets.all(10), // Margin around the snackbar.
    borderRadius: 8.0, // Rounded corners for the snackbar.
  );
}

/// The root widget of the application.
/// It sets up [GetMaterialApp] to enable GetX features.
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // GetMaterialApp is used instead of MaterialApp to enable GetX's routing,
    // dependency injection, and other state management features.
    return GetMaterialApp(
      title: 'SuperClipboard Manager (GetX)', // Application title.
      theme: ThemeData(
        // Application theme configuration.
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating, // Floating snackbar style.
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 16)),
        ),
        primarySwatch: Colors.blue, // Primary color scheme.
        useMaterial3: false, // Set to true to opt-in to Material Design 3.
        // Consider visual and behavioral changes when migrating to Material 3.
      ),
      home: MyHomePage(title: 'SuperClipboard Manager (GetX)'), // The main page of the app.
      debugShowCheckedModeBanner: false, // Hides the debug banner in the top-right corner.
    );
  }
}

/// A utility widget that expands its child to fill available space.
/// Used here for buttons in the `LayoutGrid`.
class Expand extends SingleChildRenderObjectWidget {
  const Expand({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderExpanded();
}

class _RenderExpanded extends RenderProxyBox {
  @override
  void layout(Constraints constraints, {bool parentUsesSize = false}) {
    final boxConstraints = constraints as BoxConstraints;
    super.layout(
        boxConstraints.tighten(
          width: boxConstraints.maxWidth,
          height: boxConstraints.maxHeight,
        ),
        parentUsesSize: parentUsesSize);
  }
}

// HomeLayout can remain largely the same if its props are adapted
class HomeLayout extends StatelessWidget {
  const HomeLayout({
    super.key,
    required this.mainContent, // This will now be the history list
    required this.buttons, // These are the action buttons
  });

  final Widget mainContent; // Changed from List<Widget> to single Widget (ListView)
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 600) { // Adjusted breakpoint for better layout
        return Column( // Use Column for better scrollability of history
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: LayoutGrid(
                autoPlacement: AutoPlacement.rowDense,
                columnSizes: [1.fr, 1.fr], // Simplified for two columns
                rowSizes: const [auto, auto, auto, auto],
                gridFit: GridFit.expand,
                rowGap: 8,
                columnGap: 8,
                children: buttons.map((e) => Expand(child: e)).toList(),
              ),
            ),
            const Divider(),
            Expanded(child: mainContent), // History list will take remaining space
          ],
        );
      } else {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 220, // Fixed width for buttons panel
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: buttons
                      .intersperse(const SizedBox(height: 10))
                      .toList(growable: false),
                ),
              ),
            ),
            VerticalDivider(
              color: Colors.blueGrey.shade100,
              thickness: 1,
              width: 1,
            ),
            Expanded(
              child: mainContent, // History list takes remaining space
            ),
          ],
        );
      }
    });
  }
}

/// The main screen of the application, displaying clipboard history and action buttons.
///
/// This widget is a [StatelessWidget] that uses GetX to interact with the
/// [ClipboardController] for state management and clipboard operations.
class MyHomePage extends StatelessWidget {
  MyHomePage({super.key, required this.title});

  final String title;

  // Access the globally available ClipboardController instance.
  final ClipboardController _clipboardController = Get.find();

  /// Shows a snackbar message using the global [showGetSnackbar] helper.
  void _showMessage(String message, {bool isError = false}) {
    showGetSnackbar(isError ? 'Error' : 'Info', message, isError: isError);
  }

  /// Reads content from the system clipboard and adds it to the history.
  Future<void> _pasteFromSystemClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      _showMessage(_notAvailableMessage, isError: true);
      return;
    }
    try {
      final reader = await clipboard.read();
      // Delegate to the controller to add the read item to history.
      await _clipboardController.addClipboardReaderToHistory(reader,
          source: "System Paste");
      _showMessage('Pasted from system clipboard and added to history.');
    } catch (e) {
      _showMessage('Failed to read from clipboard: $e', isError: true);
      print("Error pasting from system clipboard: $e");
    }
  }

  /// A generic method to write a [DataWriterItem] to the system clipboard
  /// and then add it to the local clipboard history.
  ///
  /// - [item]: The [DataWriterItem] to be written to the clipboard.
  /// - [successMessage]: Message to show on successful copy.
  Future<void> _copyAndStore(
      DataWriterItem item, String successMessage) async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      _showMessage(_notAvailableMessage, isError: true);
      return;
    }
    try {
      // Write the item to the system clipboard.
      await clipboard.write([item]);

      // To ensure consistency and capture exactly what was written (especially with complex data),
      // read the content back from the clipboard and add this version to history.
      // This handles cases where the system might transform or select specific formats.
      final reader = await clipboard.read();
      await _clipboardController.addClipboardReaderToHistory(reader,
          source: "App Copy"); // Mark source as "App Copy".
      _showMessage(successMessage);
    } catch (e) {
      _showMessage('Failed to copy: $e', isError: true);
      print("Error in _copyAndStore: $e");
    }
  }

  // --- Methods to copy specific data types to the clipboard ---

  /// Copies sample plain text and HTML text to the clipboard.
  void _copyText() {
    final item = DataWriterItem();
    item.add(Formats.htmlText('<b>This is a <em>HTML</em> value</b>.'));
    item.add(Formats.plainText('This is a plaintext value.'));
    _copyAndStore(item, 'Text copied to clipboard and added to history.');
  }

  /// Copies a sample image (a red circle) to the clipboard.
  void _copyImage() async {
    final imageBytes = await createImageData(Colors.red); // Generate image data.
    final item = DataWriterItem(suggestedName: 'RedCircle.png');
    item.add(Formats.png(imageBytes)); // Add as PNG format.
    _copyAndStore(item, 'Image copied to clipboard and added to history.');
  }

  /// Copies a sample URI to the clipboard.
  void _copyUri() {
    final item = DataWriterItem();
    item.add(Formats.uri(NamedUri(
        Uri.parse('https://github.com/superlistapp/super_native_extensions'),
        name: 'Super Native Extensions'))); // URI with a name.
    _copyAndStore(item, 'URI copied to clipboard and added to history.');
  }

  // TODO: Implement example methods for copying lazy-loaded data and custom data formats
  //       using the _copyAndStore pattern to ensure they are added to history.
  // void _copyTextLazy() { ... }
  // void _copyImageLazy() { ... }
  // void _copyCustomData() { ... }

  @override
  Widget build(BuildContext context) {
    final TextEditingController searchEditingController = TextEditingController();
    // Ensure controller's searchQuery is updated if text field is cleared externally
    ever(_clipboardController.searchQuery, (String query) {
      if (query != searchEditingController.text) {
        searchEditingController.text = query;
      }
    });


    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear History',
            onPressed: () {
              Get.defaultDialog(
                title: "Clear History",
                middleText: "Are you sure you want to clear all clipboard history?",
                textConfirm: "Clear All",
                textCancel: "Cancel",
                confirmTextColor: Colors.white,
                buttonColor: Colors.redAccent,
                onConfirm: () {
                  _clipboardController.clearHistory();
                  Get.back();
                },
              );
            },
          ),
        ],
      ),
      body: Column( // Wrap HomeLayout with Column to add Search Bar on top
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: searchEditingController,
              decoration: InputDecoration(
                hintText: 'Search history...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25.0),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[200],
                contentPadding: EdgeInsets.symmetric(vertical: 0, horizontal: 20),
                suffixIcon: Obx(() => _clipboardController.searchQuery.value.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear),
                        onPressed: () {
                          _clipboardController.updateSearchQuery('');
                          // searchEditingController.clear(); // Already handled by `ever`
                        },
                      )
                    : SizedBox.shrink()),
              ),
              onChanged: (value) {
                _clipboardController.updateSearchQuery(value);
              },
            ),
          ),
          Expanded( // HomeLayout now takes the remaining space
            child: HomeLayout(
              mainContent: Obx(() {
                // Determine which list to show based on whether history or filteredHistory is empty
                final bool mainHistoryIsEmpty = _clipboardController.history.isEmpty;
                final bool filteredHistoryIsEmpty = _clipboardController.filteredHistory.isEmpty;
                final String currentSearchQuery = _clipboardController.searchQuery.value;

                if (mainHistoryIsEmpty) { // No items in history at all
                  return const Center(
                      child: Text('Clipboard history is empty. Try copying something!',
                          style: TextStyle(fontSize: 16, color: Colors.grey)));
                } else if (filteredHistoryIsEmpty && currentSearchQuery.isNotEmpty) { // Search yielded no results
                   return Center(
                      child: Text('No results found for "$currentSearchQuery".',
                          style: TextStyle(fontSize: 16, color: Colors.grey)));
                }
                // Display filtered history
                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: 70, top: 5),
                  itemCount: _clipboardController.filteredHistory.length, // Use filtered list
                  itemBuilder: (ctx, index) {
                    final historyItem = _clipboardController.filteredHistory[index]; // Use filtered list
                    return ClipboardHistoryItemWidget(
                      key: ValueKey(historyItem.id),
                      historyItem: historyItem,
                    );
                  },
                );
              }),
              buttons: [
          OutlinedButton.icon(
            icon: const Icon(Icons.text_fields),
            label: const Text('Copy Text'),
            onPressed: _copyText,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.text_fields),
            label: const Text('Copy Text'),
            onPressed: _copyText,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.image),
            label: const Text('Copy Image'),
            onPressed: _copyImage,
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.link),
            label: const Text('Copy URI'),
            onPressed: _copyUri,
          ),
          // TODO: Add buttons for lazy and custom data copy methods when implemented.
          ElevatedButton.icon(
            icon: const Icon(Icons.content_paste_go),
            label: const Text('Paste from System'),
            onPressed: _pasteFromSystemClipboard,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// Generates sample image data (a colored oval) as a [Uint8List] in PNG format.
/// - [color]: The color of the oval.
Future<Uint8List> createImageData(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final paint = Paint()..color = color;
  canvas.drawOval(const Rect.fromLTWH(0, 0, 200, 200), paint);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 200);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

// Intersperse extension can be removed if not used elsewhere,
// or moved to a utility file if it is.
// For now, it's not directly used by the refactored HomeLayout's button part.
// If lists are built directly, intersperse might not be needed.
extension IntersperseExtensions<T> on Iterable<T> {
  Iterable<T> intersperse(T element) sync* {
    final iterator = this.iterator;
    if (iterator.moveNext()) {
      yield iterator.current;
      while (iterator.moveNext()) {
        yield element;
        yield iterator.current;
      }
    }
  }
}
