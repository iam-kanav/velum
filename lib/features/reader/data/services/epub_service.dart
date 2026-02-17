import 'dart:io';
import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EpubService {
  const EpubService();

  /// Parse EPUB from asset bundle (for sample books)
  Future<EpubBook> parseEpubFromAsset(String assetPath) async {
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final List<int> bytes = data.buffer.asUint8List();

      // Offload heavy parsing to a background thread
      return await compute(_parseEpubIsolate, Uint8List.fromList(bytes));
    } catch (e) {
      throw Exception('Failed to parse EPUB from asset: $e');
    }
  }

  /// Parse EPUB from file path (for scanned books)
  Future<EpubBook> parseEpubFromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final bytes = await file.readAsBytes();

      // Offload heavy parsing to a background thread
      return await compute(_parseEpubIsolate, bytes);
    } catch (e) {
      throw Exception('Failed to parse EPUB from file: $e');
    }
  }

  /// Smart parser that detects if path is asset or file
  Future<EpubBook> parseEpub(String path) async {
    if (path.startsWith('assets/')) {
      return parseEpubFromAsset(path);
    } else {
      return parseEpubFromFile(path);
    }
  }
}

// Top-level function for isolate
Future<EpubBook> _parseEpubIsolate(List<int> bytes) async {
  return EpubReader.readBook(bytes);
}
