# Super Clipboard Example - Clipboard Manager

This Flutter application demonstrates the capabilities of the `super_clipboard` package by implementing a functional clipboard manager. It allows users to view their clipboard history, see the content of copied items (text, images, URIs), and copy items from history back to the system clipboard.

The application uses the **GetX** package for state management, dependency injection, and route management (though routing is minimal in this example).

## Features

*   **Clipboard History:** Displays a list of items copied to the clipboard.
*   **Content Preview:** Shows a quick preview of each item (text snippet or image thumbnail).
*   **Detailed Content View:** Allows expanding an item to see its full content, rendered appropriately for different data types (plain text, HTML, images, URIs).
    *   Utilizes `widget_for_reader.dart` (from the original `super_clipboard` example) to handle the rendering of various `DataReader` formats.
*   **Copy from History:** Allows users to copy items from the history back to the system clipboard.
*   **Delete from History:** Allows users to remove individual items from the history.
*   **Clear History:** Provides an option to clear the entire clipboard history.
*   **Responsive Layout:** Adapts the layout for different screen sizes (narrow vs. wide).
*   **Example Copy Actions:** Includes buttons to copy sample text, images, and URIs to the system clipboard (which then appear in the history).

## Project Structure

Key files and directories in this example:

*   `lib/main.dart`: The main entry point of the application. Sets up the GetX controller, defines the overall app structure (`GetMaterialApp`), and the main page (`MyHomePage`).
*   `lib/clipboard_controller.dart`:
    *   `ClipboardController` (GetX controller): Manages the state of the clipboard history (`RxList<ClipboardHistoryItem>`). Handles logic for adding items, copying items to the system clipboard, and removing/clearing history.
    *   `ClipboardHistoryItem`: A class representing a single item in the clipboard history. It stores the raw `DataReaderItem`s, timestamp, preview data, and the lazily-loaded rich content widgets.
*   `lib/history_item_widget.dart`: A `StatefulWidget` responsible for displaying a single `ClipboardHistoryItem` in the list. It handles the expansion/collapse of the detailed view and triggers the loading of full content.
*   `lib/widget_for_reader.dart`: (Adapted from the original `super_clipboard` example) Contains the logic to build Flutter widgets from `DataReader` objects, rendering various data formats like text, HTML, images, and URIs. This file has been slightly refactored to better integrate with the controller.
*   `pubspec.yaml`: Defines project dependencies, including `super_clipboard`, `get` (for GetX), and `timeago` (for user-friendly timestamps).

## State Management with GetX

*   **`ClipboardController`**: A `GetxController` is used to manage the application's state, primarily the list of `ClipboardHistoryItem` objects.
*   **Dependency Injection**: `Get.put(ClipboardController())` is called in `main()` to initialize and register the controller, making it accessible anywhere via `Get.find()`.
*   **Reactive UI**:
    *   `Obx` widgets are used in `MyHomePage` (for the history list) and `ClipboardHistoryItemWidget` (for previews and content) to listen to changes in `Rx` observables (like `RxList` and `RxBool`) within the controller and history items.
    *   When an observable changes (e.g., an item is added to `history`, or `isLoadingWidgets` changes), the UI automatically rebuilds only the necessary parts.

## How It Works

1.  **Copying to Clipboard (In-App Actions):**
    *   When one of the "Copy Text/Image/URI" buttons in `MyHomePage` is pressed:
        *   A `DataWriterItem` is created with the sample data.
        *   `SystemClipboard.instance.write()` writes this item to the system clipboard.
        *   Immediately after, `SystemClipboard.instance.read()` reads the content back. This ensures that what's added to the history accurately reflects what the system clipboard accepted (including any transformations or format selections made by the OS).
        *   The `ClipboardReader` obtained from the read operation is passed to `_clipboardController.addClipboardReaderToHistory()`.
2.  **Pasting from System (Manual):**
    *   The "Paste from System" button in `MyHomePage` calls `SystemClipboard.instance.read()`.
    *   The resulting `ClipboardReader` is passed to `_clipboardController.addClipboardReaderToHistory()`.
3.  **Adding to History (`ClipboardController`):**
    *   `addClipboardReaderToHistory()` creates a `ClipboardHistoryItem` from the `ClipboardReader`.
    *   It calls `generatePreview()` on the new item to quickly extract a text snippet or image thumbnail.
    *   The new item is added to the `history` `RxList`, triggering UI updates.
4.  **Displaying History Items (`MyHomePage` & `ClipboardHistoryItemWidget`):**
    *   `MyHomePage` uses an `Obx` widget to build a `ListView` from the `_clipboardController.history` list.
    *   Each item in the `ListView` is a `ClipboardHistoryItemWidget`.
    *   `ClipboardHistoryItemWidget` initially displays the pre-generated preview (text/image).
    *   When an item is expanded:
        *   If the full content (`displayWidgets`) hasn't been loaded yet, it calls `historyItem.loadDisplayWidgets(context)`.
        *   `loadDisplayWidgets()` (in `ClipboardHistoryItem`) uses `buildWidgetsForReaders()` (from `widget_for_reader.dart`) to generate a list of widgets representing all available data formats for that item.
        *   These widgets are then displayed in the expanded section of the `ClipboardHistoryItemWidget`.
5.  **Copying from History (`ClipboardController`):**
    *   The "Copy" button on a history item calls `_clipboardController.copyItemToClipboard()`.
    *   This method reconstructs `DataWriterItem`s from the `DataReaderItem`s stored in the `ClipboardHistoryItem` and writes them to the system clipboard.

## How to Run

1.  Ensure you have Flutter installed.
2.  Navigate to the `super_clipboard/example` directory.
3.  Run `flutter pub get` to fetch dependencies.
4.  Run `flutter run` to launch the application on a connected device or emulator.

## Further Enhancements (TODOs)

*   **Persistence:** Save and load clipboard history to/from disk (e.g., using Hive, sqflite, or shared_preferences).
*   **System Paste Listener:** Implement `ClipboardEvents.instance.registerPasteEventListener` in the `ClipboardController` to automatically add items to history when they are copied from *other* applications (background monitoring).
*   **Search/Filter:** Add functionality to search or filter the clipboard history.
*   **Pinning Items:** Allow users to pin favorite or frequently used clipboard items.
*   **Settings:** Add a settings page for configuring history length, theme, etc.
*   **More Robust Data Handling:** For lazy-loaded or complex data types, improve how data is stored in `ClipboardHistoryItem` or reconstructed for copying to ensure reliability if the original data source is no longer available.
*   **Improved HTML Rendering:** Use a package like `flutter_html` for a richer display of HTML content instead of plain text.
*   **UI/UX Polish:** Add animations, refine layouts, and improve overall user experience.
*   **Error Handling:** More granular error display within items if specific formats fail to load.

This example provides a solid foundation for building a more feature-rich clipboard manager using `super_clipboard` and GetX.
