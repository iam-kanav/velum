import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/tts_settings.dart';

/// Represents a text chunk for TTS with its position info
class TtsChunk {
  final int index;
  final String text;
  final int paragraphIndex;
  final int? sentenceIndex; // null if highlight mode is paragraph

  const TtsChunk({
    required this.index,
    required this.text,
    required this.paragraphIndex,
    this.sentenceIndex,
  });
}

/// Service wrapper around FlutterTts
class TtsService {
  final FlutterTts _flutterTts = FlutterTts();

  List<dynamic> _availableLanguages = [];
  List<dynamic> _availableVoices = [];
  TtsState _state = TtsState.idle;

  // Callbacks
  VoidCallback? onStart;
  VoidCallback? onComplete;
  VoidCallback? onPause;
  VoidCallback? onContinue;
  void Function(String text, int start, int end, String word)? onProgress;
  void Function(String error)? onError;

  TtsState get state => _state;
  List<dynamic> get availableLanguages => _availableLanguages;
  List<dynamic> get availableVoices => _availableVoices;

  /// Initialize the TTS engine
  Future<void> init() async {
    // Get available languages and voices
    _availableLanguages = await _flutterTts.getLanguages ?? [];
    _availableVoices = await _flutterTts.getVoices ?? [];

    // Set up handlers
    _flutterTts.setStartHandler(() {
      _state = TtsState.playing;
      onStart?.call();
    });

    _flutterTts.setCompletionHandler(() {
      _state = TtsState.stopped;
      onComplete?.call();
    });

    _flutterTts.setPauseHandler(() {
      _state = TtsState.paused;
      onPause?.call();
    });

    _flutterTts.setContinueHandler(() {
      _state = TtsState.playing;
      onContinue?.call();
    });

    _flutterTts.setProgressHandler((text, start, end, word) {
      onProgress?.call(text, start, end, word);
    });

    _flutterTts.setErrorHandler((error) {
      _state = TtsState.stopped;
      onError?.call(error.toString());
    });

    debugPrint(
      'TTS initialized with ${_availableLanguages.length} languages and ${_availableVoices.length} voices',
    );
  }

  /// Apply TTS settings
  Future<void> applySettings(TtsSettings settings) async {
    await _flutterTts.setSpeechRate(settings.speechRate);
    await _flutterTts.setPitch(settings.pitch);
    await _flutterTts.setVolume(settings.volume);
    await _flutterTts.setLanguage(settings.language);

    if (settings.voiceName != null) {
      // Find matching voice
      final voice = _availableVoices.firstWhere(
        (v) => v['name'] == settings.voiceName,
        orElse: () => null,
      );
      if (voice != null) {
        await _flutterTts.setVoice({
          'name': voice['name'],
          'locale': voice['locale'],
        });
      }
    }
  }

  /// Get voices filtered by language (exact locale match)
  List<Map<String, dynamic>> getVoicesForLanguage(String language) {
    // Normalize language format (e.g., en-US -> en-us, en_US -> en-us)
    final normalizedLang = language.toLowerCase().replaceAll('_', '-');

    return _availableVoices
        .where((v) {
          final locale = (v['locale'] as String?)?.toLowerCase().replaceAll(
            '_',
            '-',
          );
          return locale == normalizedLang;
        })
        .map((v) => Map<String, dynamic>.from(v as Map))
        .toList();
  }

  /// Speak text
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    _state = TtsState.playing;
    await _flutterTts.speak(text);
  }

  /// Stop speaking
  Future<void> stop() async {
    _state = TtsState.stopped;
    await _flutterTts.stop();
  }

  /// Pause speaking (Android 26+)
  Future<void> pause() async {
    _state = TtsState.paused;
    await _flutterTts.pause();
  }

  /// Dispose resources
  Future<void> dispose() async {
    await _flutterTts.stop();
  }

  /// Split text into chunks based on highlight mode
  static List<TtsChunk> chunkText(String text, TtsHighlightMode mode) {
    final chunks = <TtsChunk>[];

    // Split into paragraphs first
    final paragraphs = text.split(RegExp(r'\n\s*\n'));

    int chunkIndex = 0;
    int filteredParagraphIndex = 0; // Only count non-empty paragraphs

    for (int pIndex = 0; pIndex < paragraphs.length; pIndex++) {
      final para = paragraphs[pIndex].trim();
      if (para.isEmpty) continue;

      if (mode == TtsHighlightMode.paragraph) {
        chunks.add(
          TtsChunk(
            index: chunkIndex++,
            text: para,
            paragraphIndex: filteredParagraphIndex,
          ),
        );
      } else {
        // Split into sentences
        final sentences = _splitIntoSentences(para);
        for (int sIndex = 0; sIndex < sentences.length; sIndex++) {
          final sentence = sentences[sIndex].trim();
          if (sentence.isEmpty) continue;
          chunks.add(
            TtsChunk(
              index: chunkIndex++,
              text: sentence,
              paragraphIndex: filteredParagraphIndex,
              sentenceIndex: sIndex,
            ),
          );
        }
      }
      filteredParagraphIndex++; // Increment after processing non-empty paragraph
    }

    return chunks;
  }

  /// Helper to split paragraph into sentences
  static List<String> _splitIntoSentences(String text) {
    // Split on sentence-ending punctuation followed by space or end
    final regex = RegExp(r'(?<=[.!?])\s+');
    return text.split(regex);
  }
}
