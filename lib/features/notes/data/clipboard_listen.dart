import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../library/presentation/providers/library_notifier.dart';
import '../../reader/data/services/chapter_processor.dart';
import '../../reader/data/services/epub_service.dart';
import '../../tts/data/models/tts_chunk.dart';
import '../../tts/presentation/providers/tts_notifier.dart';
import 'note_service.dart';

/// "Listen to clipboard" (Android): a notification that stays in the shade.
/// Tapping it saves what was last copied as a note and reads it aloud,
/// without opening the app. The notification and the clipboard are handled
/// natively (QuickListen.kt); this side makes the note and plays it.
class ClipboardListen {
  static const _channel = MethodChannel('velum/quick_listen');

  final LibraryNotifier _library;
  final TtsNotifier _tts;
  final Future<void> _ttsReady;

  /// Show the note, so opening the app lands on it.
  final void Function(String notePath) _openNote;

  ClipboardListen(this._library, this._tts, this._ttsReady, this._openNote);

  static bool get isSupported => Platform.isAndroid;

  /// Whether the notification is turned on.
  static Future<bool> isEnabled() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isEnabled') ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> setEnabled(bool enabled) =>
      _channel.invokeMethod('setEnabled', enabled);

  /// Listen for notification taps, including the one that started the app.
  void start() {
    if (!isSupported) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'pending') await _takePending();
    });
    _takePending();
  }

  bool _busy = false;

  Future<void> _takePending() async {
    if (_busy) return;
    _busy = true;
    try {
      final text = await _channel.invokeMethod<String>('takePending');
      if (text != null && text.trim().isNotEmpty) await listen(text);
    } on MissingPluginException {
      // Started without the native side attached: nothing was tapped.
    } catch (e) {
      debugPrint('Listening to the clipboard failed: $e');
    } finally {
      _busy = false;
      // Let the native pill close.
      try {
        await _channel.invokeMethod('done');
      } on MissingPluginException {
        // As above.
      }
    }
  }

  /// Save [text] as a note and start reading it aloud from the top.
  Future<void> listen(String text) async {
    final note = noteFromText(text);
    final path = await const NoteService().save(note);
    await _library.saveNote(path, note.title);

    // Read the saved book back, so the paragraphs match the reader's page.
    final chapters = [
      ...?(await const EpubService().parseEpub(path)).book.Chapters,
    ];
    if (chapters.isEmpty) return;
    List<TtsParagraph> paragraphsFor(int i) =>
        ChapterProcessor.process(chapters[i].HtmlContent ?? '').$2;

    await _ttsReady;
    await _tts.loadChapter(
      ReadAloudBook(
        path: path,
        title: note.title,
        chapterTitles: [for (final c in chapters) c.Title ?? note.title],
        paragraphsFor: paragraphsFor,
        onChapterStarted: (_) {},
      ),
      0,
      paragraphsFor(0),
    );
    _openNote(path);
    unawaited(_tts.play());
    // Give the media notification a moment to start while the native pill
    // still counts as the app being in front.
    await Future.delayed(const Duration(milliseconds: 600));
  }

  /// A note of [text]: one paragraph per line, titled by its first line.
  @visibleForTesting
  static Note noteFromText(String text) {
    final lines = [
      for (final line in const LineSplitter().convert(text))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    const escape = HtmlEscape(HtmlEscapeMode.element);
    return Note(
      _title(lines.isEmpty ? '' : lines.first),
      lines.map((l) => '<p>${escape.convert(l)}</p>').join('\n'),
    );
  }

  static String _title(String firstLine) {
    const max = 60;
    if (firstLine.isEmpty) return 'Clipboard';
    if (firstLine.length <= max) return firstLine;
    final cut = firstLine.substring(0, max);
    final space = cut.lastIndexOf(' ');
    return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
  }
}
