// TODO(knopp): This seems to be false positive, remove when no longer needed
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:collection/collection.dart';
import 'package:super_clipboard/super_clipboard.dart';

const formatCustom = CustomValueFormat<Uint8List>(
  applicationId: "com.superlist.clipboard.Example.CustomType",
);

/// Asynchronously builds a list of [Widget]s to display the content of clipboard items.
///
/// This function iterates through a collection of [ReaderInfo] objects (each representing
/// a single logical item from the clipboard, which might itself contain multiple data formats).
/// For each `ReaderInfo`, it generates a list of `_RepresentationWidget`s, one for each
/// available and renderable data format (e.g., plain text, HTML, PNG).
///
/// - [context]: The `BuildContext` used for creating widgets (e.g., for `MediaQuery`, `Theme`).
/// - [readers]: An iterable of [ReaderInfo] objects, each associated with a `DataReader`
///   from `super_clipboard`.
///
/// Returns a `Future` that completes with a flat list of all generated representation widgets.
Future<List<Widget>> buildWidgetsForReaders(
  BuildContext context,
  Iterable<ReaderInfo> readers,
) async {
  final List<Widget> allRepresentationWidgets = [];

  for (final readerInfo in readers) {
    // For each ReaderInfo, build its specific representation widgets.
    final representations =
        await _buildRepresentationsForSingleReader(context, readerInfo);
    allRepresentationWidgets.addAll(representations);
  }
  return allRepresentationWidgets;
}

/// Builds a list of `_RepresentationWidget`s for a single [ReaderInfo] object.
///
/// It queries the `DataReader` within `readerInfo` for supported standard formats
/// (plus a custom format) and attempts to create a `_RepresentationWidget` for each.
/// Duplicate widgets (e.g., if multiple raw formats resolve to the same `DataFormat`)
/// are filtered out.
///
/// - [context]: The `BuildContext`.
/// - [readerInfo]: The [ReaderInfo] object to process.
///
/// Returns a `Future` that completes with a list of `_RepresentationWidget`s.
Future<List<Widget>> _buildRepresentationsForSingleReader(
  BuildContext context,
  ReaderInfo readerInfo,
) async {
  // Get the list of supported data formats for the current reader.
  final itemFormats = readerInfo.reader.getFormats([
    ...Formats.standardFormats, // Includes common types like text, HTML, images, URIs.
    formatCustom, // The example custom format.
  ]);

  // Asynchronously generate a widget for each format.
  final futures =
      itemFormats.map((e) => _widgetForFormat(context, e, readerInfo.reader));

  // Wait for all format widgets to be built.
  final widgets = await Future.wait(futures);

  // Filter out any null results (formats that couldn't be rendered)
  // and ensure they are of type _RepresentationWidget.
  final children = widgets
      .where((element) => element != null)
      .cast<_RepresentationWidget>()
      .toList(growable: true);

  // Remove duplicate widgets if different raw types map to the same DataFormat.
  final Set<DataFormat> uniqueFormats = <DataFormat>{};
  children.retainWhere((element) => uniqueFormats.add(element.format));
  return children;
}

/// A helper class to hold information about a `DataReader` and its associated metadata.
/// This includes the raw `DataReader`, its suggested name, and details about its platform formats.
class ReaderInfo {
  final DataReader reader;
  final String? suggestedName;
  final List<_PlatformFormat> _formats; // Internal list of platform format details.
  final Object? localData; // Optional local data associated with the reader.

  ReaderInfo._({
    required this.reader,
    required this.suggestedName,
    required List<_PlatformFormat> formats,
    this.localData,
  }) : _formats = formats;

  /// Asynchronously creates a [ReaderInfo] instance from a [DataReader].
  ///
  /// It fetches platform format details, including whether they are virtual or synthesized.
  static Future<ReaderInfo> fromReader(
    DataReader reader, {
    Object? localData,
  }) async {
    final List<String> platformFmts = reader.platformFormats;
    final List<String> rawFormats = await reader.rawReader!.getAvailableFormats();

    // Identify formats synthesized by the reader itself (not directly present as raw formats).
    List<String> synthesizedByReader = List.of(platformFmts)
      ..removeWhere((element) => rawFormats.contains(element));

    // Check virtual and synthesized status for each platform format.
    final virtualFlags = await Future.wait(
        platformFmts.map((e) => reader.rawReader!.isVirtual(e)));
    final synthesizedFlags = await Future.wait(platformFmts.map((e) async =>
        await reader.rawReader!.isSynthesized(e) ||
        synthesizedByReader.contains(e)));

    return ReaderInfo._(
      reader: reader,
      suggestedName: await reader.getSuggestedName(),
      localData: localData,
      formats: platformFmts
          .mapIndexed((index, element) => _PlatformFormat(
                element, // The platform format string (e.g., MIME type).
                virtual: virtualFlags[index],
                synthesized: synthesizedFlags[index],
              ))
          .toList(growable: false),
    );
  }
}

/// Internal helper class to store a platform format string along with its
/// `virtual` and `synthesized` status.
class _PlatformFormat {
  final PlatformFormat format;
  final bool virtual;
  final bool synthesized;

  _PlatformFormat(
    this.format, {
    required this.virtual,
    required this.synthesized,
  });
}

/// Turn [DataReader.getValue] into a future.
extension _ReadValue on DataReader {
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) {
    final c = Completer<T?>();
    final progress = getValue<T>(format, (value) {
      c.complete(value);
    }, onError: (e) {
      c.completeError(e);
    });
    if (progress == null) {
      c.complete(null);
    }
    return c.future;
  }

  Future<Uint8List?>? readFile(FileFormat format) {
    final c = Completer<Uint8List?>();
    final progress = getFile(format, (file) async {
      try {
        final all = await file.readAll();
        c.complete(all);
      } catch (e) {
        c.completeError(e);
      }
    }, onError: (e) {
      c.completeError(e);
    });
    if (progress == null) {
      c.complete(null);
    }
    return c.future;
  }
}

// _buildWidgetForReader, _ReaderWidget, _HeaderWidget, and _FooterWidget are no longer needed
// as their functionality is either incorporated into _buildRepresentationsForSingleReader
// or handled by ClipboardHistoryItemWidget.

/// A widget to display a [NamedUri] (a URI with an optional name).
class _UriWidget extends StatelessWidget {
  const _UriWidget({required this.uri});

  final NamedUri uri;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Align text to the start
      children: [
        SelectableText(uri.uri.toString()), // Make URI selectable
        if (uri.name != null && uri.name!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              const TextSpan(
                  text: 'Name: ',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: uri.name!),
            ]),
            style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
          ),
        ]
      ],
    );
  }
}

/// A widget that displays a single data representation from the clipboard.
///
/// It shows the name of the data format (e.g., "Plain Text", "Image (PNG)")
/// and any relevant tags (virtual, synthesized). The actual content is provided
/// via the [content] widget.
class _RepresentationWidget extends StatelessWidget {
  const _RepresentationWidget({
    required this.format,
    required this.name,
    required this.synthesized,
    required this.virtual,
    required this.content,
  });

  final DataFormat format; // The DataFormat this widget represents.
  final String name; // Display name for the format.
  final bool synthesized; // True if the data is synthesized by the system.
  final bool virtual; // True if the data is virtual (loaded on demand).
  final Widget content; // The actual widget displaying the content for this format.

  @override
  Widget build(BuildContext context) {
    // Create a tag string for virtual/synthesized status.
    final List<String> tags = [];
    if (virtual) tags.add('virtual');
    if (synthesized) tags.add('synthesized');
    final String tagString = tags.isNotEmpty ? ' (${tags.join(', ')})' : '';

    return DefaultTextStyle.merge(
      style: const TextStyle(
          fontSize: 13,
          color: Colors.black87), // Base style for the content.
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: 4.0, vertical: 8.0), // Padding around the content.
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start, // Align content to the start.
          children: [
            // Display the format name and tags.
            Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: name,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (tagString.isNotEmpty)
                  TextSpan(
                      text: tagString,
                      style: TextStyle(
                          fontSize: 11, color: Colors.grey.shade600)),
              ]),
            ),
            const SizedBox(height: 4), // Spacing before the actual content.
            content, // The widget that renders the data itself.
          ],
        ),
      ),
    );
  }
}

/// Asynchronously creates a [_RepresentationWidget] for image data.
///
/// - [context]: The `BuildContext`.
/// - [format]: The specific [FileFormat] of the image (e.g., `Formats.png`).
/// - [name]: The display name for this image format (e.g., "PNG").
/// - [reader]: The [DataReader] to read the image data from.
///
/// Returns a `Future` that completes with the `_RepresentationWidget` or `null` if
/// the image data cannot be read or is empty.
Future<_RepresentationWidget?> _widgetForImage(
  BuildContext context,
  FileFormat format,
  String name, // e.g., "PNG", "JPEG"
  DataReader reader,
) async {
  final scale =
      MediaQuery.of(context).devicePixelRatio; // For proper image scaling.
  try {
    final imageBytes = await reader.readFile(format);
    if (imageBytes == null || imageBytes.isEmpty) {
      // This can happen, e.g., for TIFF on Firefox/Linux as per original comment.
      return null;
    }
    return _RepresentationWidget(
      format: format,
      name: 'Image ($name)', // e.g., "Image (PNG)"
      synthesized: reader.isSynthesized(format),
      virtual: reader.isVirtual(format),
      content: Container(
        padding: const EdgeInsets.only(top: 4),
        alignment: Alignment.centerLeft, // Align image to the left.
        constraints: BoxConstraints(
          maxHeight: 300, // Max height for image preview.
          maxWidth: MediaQuery.of(context).size.width * 0.7, // Max width.
        ),
        child: Image.memory(
          imageBytes,
          scale: scale, // Apply device pixel ratio.
          fit: BoxFit.contain, // Ensure image fits within constraints.
          errorBuilder: (context, error, stackTrace) =>
              const Text('Could not load image preview.'), // Error display.
        ),
      ),
    );
  } catch (e) {
    print("Error reading image format $name: $e");
    return _RepresentationWidget(
        format: format,
        name: 'Image ($name) - Error',
        synthesized: false, virtual: false,
        content: Text('Error loading image: $e', style: TextStyle(color: Colors.red))
    );
  }
}

/// Asynchronously creates a specific [_RepresentationWidget] based on the [DataFormat].
///
/// This function acts as a dispatcher, calling more specialized handlers like
/// [_widgetForImage] or creating `Text` widgets directly for text-based formats.
///
/// - [context]: The `BuildContext`.
/// - [format]: The [DataFormat] to render.
/// - [reader]: The [DataReader] to read data from.
///
/// Returns a `Future` that completes with the `_RepresentationWidget` or `null`
/// if the format is not supported or data cannot be read.
Future<_RepresentationWidget?> _widgetForFormat(
    BuildContext context, DataFormat format, DataReader reader) async {
  try {
    switch (format) {
      case Formats.plainText:
        final text = await reader.readValue(Formats.plainText);
        return text == null
            ? null
            : _RepresentationWidget(
                format: format,
                name: 'Plain Text',
                synthesized: reader.isSynthesized(format),
                virtual: reader.isVirtual(format),
                // Sanitize line breaks (macOS sometimes uses CR).
                content: SelectableText(
                    text.replaceAll(RegExp('\r[\n]?'), '\n')),
              );

      case Formats.plainTextFile:
        // This format is typically for virtual/synthesized text files.
        if (!reader.isVirtual(format) && !reader.isSynthesized(format)) {
          return null;
        }
        final contents = await reader.readFile(Formats.plainTextFile);
        return contents == null
            ? null
            : _RepresentationWidget(
                format: format,
                name: 'Plain Text (UTF-8 File)',
                synthesized: reader.isSynthesized(format),
                virtual: reader.isVirtual(format),
                content: SelectableText(
                    utf8.decode(contents, allowMalformed: true)),
              );

      case Formats.htmlText:
        final html = await reader.readValue(Formats.htmlText);
        // TODO: Consider using flutter_html package for richer HTML rendering.
        // For now, displaying raw HTML string.
        return html == null
            ? null
            : _RepresentationWidget(
                format: format,
                name: 'HTML',
                synthesized: reader.isSynthesized(format),
                virtual: reader.isVirtual(format),
                content: SelectableText(html),
              );

      // Image formats delegating to _widgetForImage:
      case Formats.png:
        return _widgetForImage(context, Formats.png, 'PNG', reader);
      case Formats.jpeg:
        return _widgetForImage(context, Formats.jpeg, 'JPEG', reader);
      case Formats.gif:
        return _widgetForImage(context, Formats.gif, 'GIF', reader);
      case Formats.tiff:
        return _widgetForImage(context, Formats.tiff, 'TIFF', reader);
      case Formats.webp:
        return _widgetForImage(context, Formats.webp, 'WebP', reader);

      // URI formats (regular and file URIs):
      case Formats.uri:
      case Formats.fileUri:
        // Attempt to read both file URI and regular URI, prioritizing file URI.
        final fileUri = await reader.readValue(Formats.fileUri);
        if (fileUri != null) {
          return _RepresentationWidget(
            format: Formats.fileUri, // Explicitly use Formats.fileUri here
            name: 'File URI',
            synthesized: reader.isSynthesized(Formats.fileUri),
            virtual: reader.isVirtual(Formats.fileUri),
            content: _UriWidget(uri: fileUri), // Use the dedicated _UriWidget
          );
        }
        final uri = await reader.readValue(Formats.uri);
        return uri == null
            ? null
            : _RepresentationWidget(
                format: Formats.uri, // Explicitly use Formats.uri
                name: 'URI',
                synthesized: reader.isSynthesized(Formats.uri),
                virtual: reader.isVirtual(Formats.uri),
                content: _UriWidget(uri: uri), // Use the dedicated _UriWidget
              );

      case formatCustom: // Example custom format
        final data = await reader.readValue(formatCustom);
        return data == null
            ? null
            : _RepresentationWidget(
                format: format,
                name: 'Custom Data',
                synthesized: reader.isSynthesized(formatCustom),
                virtual: reader.isVirtual(formatCustom),
                content: Text(data.toString()), // Simple string representation
              );
      default:
        // This format is not explicitly handled for display.
        return null;
    }
  } catch (e) {
    print("Error processing format $format: $e");
    return _RepresentationWidget(
        format: format, // Return a representation for the format that errored
        name: 'Error: ${format.platformType}',
        synthesized: false, virtual: false,
        content: Text('Could not load data for this format: $e', style: TextStyle(color: Colors.red))
    );
  }
}

/// Utility extension for interspersing elements in an iterable.
/// Example: `[1, 2, 3].intersperse(0)` yields `[1, 0, 2, 0, 3]`.
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
