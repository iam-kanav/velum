import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import '../models/tts_settings.dart';
import 'tts_engine.dart';

/// Default engine: the speech engine(s) installed on the phone.
/// Works offline and starts speaking almost instantly.
class DeviceTtsEngine extends TtsEngine {
  final FlutterTts _tts = FlutterTts();

  List<TtsVoice> _voices = [];
  List<String> _engines = [];
  String? _defaultEngine;
  String? _activeEngine;
  bool _initialized = false;

  /// True while an utterance we started hasn't finished or been stopped,
  /// so late completion events from a stopped utterance are ignored.
  bool _awaitingCompletion = false;

  static const _knownEngines = <String, String>{
    'com.google.android.tts': 'Speech Services by Google',
    'com.samsung.SMT': 'Samsung text-to-speech',
    'com.svox.pico': 'Pico TTS',
    'com.acapelagroup.android.tts': 'Acapela TTS',
    'es.codefactory.eloquencetts': 'Eloquence',
    'org.nobody.multitts': 'MultiTTS',
    'com.github.olga_yakovleva.rhvoice.android': 'RHVoice',
    'com.k2fsa.sherpa.onnx.tts.engine': 'Sherpa-ONNX TTS',
    'com.vnspeak.autotts': 'Auto TTS',
  };

  /// Installed engine package names (Android only).
  List<String> get engines => _engines;
  String? get defaultEngine => _defaultEngine;

  static String engineLabel(String package) =>
      _knownEngines[package] ?? package;

  @override
  List<TtsVoice> get voices => _voices;

  @override
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _tts.setStartHandler(() => onStart?.call());
    _tts.setCompletionHandler(() {
      if (!_awaitingCompletion) return;
      _awaitingCompletion = false;
      onComplete?.call();
    });
    _tts.setErrorHandler((msg) {
      if (!_awaitingCompletion) return;
      _awaitingCompletion = false;
      onError?.call('$msg');
    });
    await _tts.awaitSpeakCompletion(false);

    if (Platform.isAndroid) {
      try {
        _engines = List<String>.from(await _tts.getEngines ?? const []);
        _defaultEngine = await _tts.getDefaultEngine as String?;
        _activeEngine = _defaultEngine;
      } catch (e) {
        debugPrint('Failed to list TTS engines: $e');
      }
    }
    await _loadVoices();
  }

  Future<void> _loadVoices() async {
    try {
      final raw = await _tts.getVoices;
      final byName = <String, Map<String, dynamic>>{};
      for (final v in (raw as List? ?? const [])) {
        final map = Map<String, dynamic>.from(v as Map);
        final name = map['name']?.toString();
        if (name == null || map['locale'] == null) continue;
        // Skip voices that still need downloading.
        if ((map['features']?.toString() ?? '').contains('notInstalled')) {
          continue;
        }
        byName[name] = map;
      }

      final voices = <TtsVoice>[];
      byName.forEach((name, map) {
        // Google lists most voices twice (on-device and online); keep the
        // on-device one, which starts faster and works offline.
        if (name.endsWith('-network') &&
            byName.containsKey(name.replaceFirst(RegExp(r'-network$'), '-local'))) {
          return;
        }
        voices.add(
          TtsVoice(
            id: name,
            label: _voiceLabel(name, map['network_required'] == '1'),
            locale: TtsEngine.normaliseLocale(map['locale'].toString()),
          ),
        );
      });
      voices.sort((a, b) => a.label.compareTo(b.label));
      _voices = voices;
    } catch (e) {
      debugPrint('Failed to load device voices: $e');
      _voices = [];
    }
  }

  /// 'en-us-x-iob-local' → 'Voice IOB', 'en-US-language' → 'Standard';
  /// voices that need a connection are marked.
  static String _voiceLabel(String name, bool online) {
    final i = name.indexOf('-x-');
    var label = name;
    if (i != -1) {
      final code = name
          .substring(i + 3)
          .replaceAll(RegExp(r'-(local|network)$'), '')
          .toUpperCase();
      label = 'Voice $code';
    } else if (name.endsWith('-language')) {
      label = 'Standard';
    }
    return online ? '$label (online)' : label;
  }

  @override
  Future<void> applySettings(TtsSettings settings) async {
    final wanted = settings.deviceEngine ?? _defaultEngine;
    if (Platform.isAndroid &&
        wanted != null &&
        wanted != _activeEngine &&
        _engines.contains(wanted)) {
      await _tts.setEngine(wanted);
      _activeEngine = wanted;
      await _loadVoices();
    }

    // flutter_tts uses 0.5 as normal speed on both Android and iOS,
    // which matches how speechRate is stored.
    await _tts.setSpeechRate(settings.speechRate);
    await _tts.setPitch(settings.pitch);
    await _tts.setVolume(settings.volume);

    final voice = _voices
        .where((v) => v.id == settings.deviceVoice)
        .firstOrNull;
    if (voice != null) {
      await _tts.setVoice({'name': voice.id, 'locale': voice.locale});
    } else {
      await _tts.setLanguage(settings.language);
    }
  }

  @override
  Future<void> speak(String text) async {
    if (text.isEmpty) return;
    _awaitingCompletion = true;
    final result = await _tts.speak(text);
    if (result != 1 && _awaitingCompletion) {
      _awaitingCompletion = false;
      onError?.call('Speech engine failed to speak');
    }
  }

  @override
  Future<void> stop() async {
    _awaitingCompletion = false;
    await _tts.stop();
  }

  /// Pause mid-utterance. Speaking the same text again continues from the
  /// word where it paused (flutter_tts tracks the position on Android 8+;
  /// older versions restart the chunk).
  @override
  Future<void> pause() async {
    _awaitingCompletion = false;
    await _tts.pause();
  }
}
