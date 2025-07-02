import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:super_clipboard_example/clipboard_controller.dart'; // For ClipboardHistoryItem and ClipboardController
import 'package:timeago/timeago.dart' as timeago; // For user-friendly timestamps, e.g., "5 minutes ago"

/// A StatefulWidget that displays a single item from the clipboard history.
///
/// This widget shows a preview of the clipboard item (text or image) and
/// allows the user to expand it to see the full content, rendered by
/// `widget_for_reader.dart`. It also provides actions to copy the item
/// back to the clipboard or delete it from history.
class ClipboardHistoryItemWidget extends StatefulWidget {
  /// The [ClipboardHistoryItem] to display.
  final ClipboardHistoryItem historyItem;

  const ClipboardHistoryItemWidget({Key? key, required this.historyItem})
      : super(key: key);

  @override
  State<ClipboardHistoryItemWidget> createState() =>
      _ClipboardHistoryItemWidgetState();
}

class _ClipboardHistoryItemWidgetState extends State<ClipboardHistoryItemWidget> {
  // Access the global ClipboardController using GetX.
  final ClipboardController _clipboardController = Get.find();

  // Local state to manage whether the detailed content view is expanded or collapsed.
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    // When the widget is initialized, ensure that the preview for the history item
    // has been generated. This is often done when the item is first added to the
    // controller, but this serves as a fallback, especially if items were loaded
    // from persistence without immediate preview generation.
    if (!widget.historyItem.isPreviewReady.value) {
      widget.historyItem.generatePreview();
    }

    // Note: Full content (displayWidgets) is loaded lazily when the item is expanded
    // for the first time (see _toggleExpand method). This improves initial list loading performance.
  }

  /// Toggles the expanded/collapsed state of the detailed content view.
  /// If expanding and full content hasn't been loaded yet, it triggers
  /// [historyItem.loadDisplayWidgets].
  void _toggleExpand() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
    // If the item is being expanded and its displayable widgets haven't been loaded yet,
    // and it's not already in the process of loading them, then initiate loading.
    if (_isExpanded &&
        widget.historyItem.displayWidgets.isEmpty &&
        !widget.historyItem.isLoadingWidgets.value) {
      // Pass the current BuildContext, as it's needed by widget_for_reader.dart
      // to correctly build widgets (e.g., for MediaQuery, Theme).
      widget.historyItem.loadDisplayWidgets(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      elevation: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: Preview, Timestamp, Expand/Collapse button
          ListTile(
            leading: Obx(() {
              if (widget.historyItem.imagePreview != null) {
                return Image.memory(
                  widget.historyItem.imagePreview!,
                  width: 50,
                  height: 50,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.broken_image, size: 40),
                );
              }
              // You can add more specific icons based on content type if preview indicates it
              return const Icon(Icons.article_outlined, size: 40);
            }),
            title: Obx(() => Text(
                  widget.historyItem.preview ?? 'Loading preview...',
                  maxLines: _isExpanded ? 5 : 2, // Show more lines when expanded
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                )),
            subtitle: Text(
              '${timeago.format(widget.historyItem.timestamp)} ${widget.historyItem.source != null ? "(${widget.historyItem.source})" : ""}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: IconButton(
              icon: Icon(_isExpanded ? Icons.expand_less : Icons.expand_more),
              onPressed: _toggleExpand,
            ),
            onTap: _toggleExpand, // Allow tapping anywhere on the tile to expand
          ),
          // Expanded content area
          if (_isExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Obx(() {
                if (widget.historyItem.isLoadingWidgets.value) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                if (widget.historyItem.displayWidgets.isEmpty) {
                  // This might mean loading failed or no widgets were built
                  return const Text('No detailed view available or content failed to load.',
                                   style: TextStyle(fontStyle: FontStyle.italic));
                }
                // The displayWidgets are expected to be Column/ListView friendly
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // widget_for_reader usually produces a list of widgets, each representing a format.
                  // Wrap them in a Column.
                  children: widget.historyItem.displayWidgets,
                );
              }),
            ),
          // Actions: Copy, Delete
          Padding(
            padding: const EdgeInsets.only(right: 8.0, bottom: 0.0), // Adjusted padding
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.copy, size: 18, color: Colors.blue),
                  label: const Text('Copy', style: TextStyle(color: Colors.blue)),
                  onPressed: () {
                    _clipboardController.copyItemToClipboard(widget.historyItem);
                  },
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                  label: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
                  onPressed: () {
                    _clipboardController.removeItemFromHistory(widget.historyItem);
                    // Item will be removed from list by GetX, widget will disappear
                  },
                   style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
