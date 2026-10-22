import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'phonon_bindings.dart';

enum PhononModelStatus { unsupported, notInstalled, downloading, installed }

/// A voice downloaded with the model, as the catalog describes it.
class PhononVoiceInfo {
  final String name;
  final String locale; // "en-US" form
  final String? gender;

  const PhononVoiceInfo({required this.name, required this.locale, this.gender});

  Map<String, dynamic> toJson() => {
    'name': name,
    'locale': locale,
    'gender': ?gender,
  };

  factory PhononVoiceInfo.fromJson(Map<String, dynamic> json) =>
      PhononVoiceInfo(
        name: json['name'] as String,
        locale: json['locale'] as String,
        gender: json['gender'] as String?,
      );
}

/// The experimental Phonon voice's files: the Phonon 31m English model
/// (Apache 2.0) and the English voices of the Phonon voice catalog, both from
/// Hugging Face and pinned to one commit. Downloaded from the voice settings
/// rather than shipped in the app.
class PhononModel extends ChangeNotifier {
  static const _modelUrl =
      'https://huggingface.co/gradium/phonon-31m-en/resolve/92741c5b07d085ff840e26fea8ce43110b87852f';
  static const _voicesUrl =
      'https://huggingface.co/gradium/phonon-voices/resolve/da6c9ec0d47be8df5c87c730a3aa97187f3229c3';
  static const _modelFiles = {
    'config.json': 4634,
    'tokenizer.json': 277967,
    'model.q8.gguf': 64512352,
    'default-voice.safetensors': 256136,
  };
  static const _voiceFileSize = 256136;
  static const _voiceLocales = {'en-us', 'en-gb'};

  /// About what the download comes to, for the settings label.
  static const approximateMegabytes = 72;

  PhononModelStatus _status = PhononModelStatus.notInstalled;
  double _progress = 0;
  String? _error;
  Directory? _dir;
  HttpClient? _client;
  bool _cancelled = false;

  PhononModelStatus get status => _status;
  bool get isInstalled => _status == PhononModelStatus.installed;

  /// Download progress, 0 to 1.
  double get progress => _progress;

  /// Why the last download failed, until the next one starts.
  String? get error => _error;

  /// The checkpoint folder the library loads. Null until [init].
  String? get path => _dir?.path;

  Future<void> init() async {
    final support = await getApplicationSupportDirectory();
    _dir = Directory(p.join(support.path, 'phonon', 'phonon-31m-en'));
    if (!phononSupported()) {
      _status = PhononModelStatus.unsupported;
    } else if (_status != PhononModelStatus.downloading) {
      _status = await _dir!.exists()
          ? PhononModelStatus.installed
          : PhononModelStatus.notInstalled;
    }
    notifyListeners();
  }

  /// The voices that came with the model.
  Future<List<PhononVoiceInfo>> voices() async {
    final file = File(p.join(_dir!.path, 'voices.json'));
    if (!await file.exists()) return const [];
    return [
      for (final v in jsonDecode(await file.readAsString()) as List)
        PhononVoiceInfo.fromJson(v as Map<String, dynamic>),
    ];
  }

  /// Download everything into a staging folder, then move it into place, so
  /// a half-finished download never looks installed.
  Future<void> download() async {
    if (_status != PhononModelStatus.notInstalled || _dir == null) return;
    _status = PhononModelStatus.downloading;
    _progress = 0;
    _error = null;
    _cancelled = false;
    notifyListeners();

    final staging = Directory('${_dir!.path}.partial');
    final client = _client = HttpClient();
    try {
      if (await staging.exists()) await staging.delete(recursive: true);
      await Directory(p.join(staging.path, 'voices')).create(recursive: true);

      final catalog = await _fetchString(client, '$_voicesUrl/voices.jsonl');
      final voices = <(PhononVoiceInfo, String)>[];
      for (final line in const LineSplitter().convert(catalog)) {
        if (line.trim().isEmpty) continue;
        final v = jsonDecode(line) as Map<String, dynamic>;
        final locale = v['locale'] as String?;
        final file = v['filename'] as String?;
        if (!_voiceLocales.contains(locale) || file == null) continue;
        voices.add((
          PhononVoiceInfo(
            name: v['name'] as String,
            locale: '${locale!.substring(0, 2)}-${locale.substring(3).toUpperCase()}',
            gender: v['gender'] as String?,
          ),
          file,
        ));
      }

      final downloads = [
        for (final f in _modelFiles.keys) ('$_modelUrl/$f', f),
        // The library names each voice after its file.
        for (final (info, file) in voices)
          ('$_voicesUrl/$file', 'voices/${info.name}.safetensors'),
      ];
      final total = _modelFiles.values.fold(0, (a, b) => a + b) +
          voices.length * _voiceFileSize;
      var done = 0;
      for (final (url, name) in downloads) {
        done += await _fetchFile(client, url, File(p.join(staging.path, name)),
            (received) {
          final progress = ((done + received) / total).clamp(0.0, 1.0);
          // Every 0.5%, rather than for each network chunk.
          if (progress - _progress < 0.005) return;
          _progress = progress;
          notifyListeners();
        });
      }

      await File(p.join(staging.path, 'voices.json')).writeAsString(
        jsonEncode([for (final (info, _) in voices) info.toJson()]),
      );
      if (await _dir!.exists()) await _dir!.delete(recursive: true);
      await staging.rename(_dir!.path);
      _status = PhononModelStatus.installed;
    } catch (e) {
      debugPrint('Phonon download failed: $e');
      _status = PhononModelStatus.notInstalled;
      if (!_cancelled) _error = 'Download failed. Check your connection and try again.';
      try {
        if (await staging.exists()) await staging.delete(recursive: true);
      } catch (_) {}
    } finally {
      client.close(force: true);
      _client = null;
      notifyListeners();
    }
  }

  void cancelDownload() {
    _cancelled = true;
    _client?.close(force: true);
  }

  /// Remove the downloaded files. Unload the voice first.
  Future<void> delete() async {
    if (_status != PhononModelStatus.installed) return;
    try {
      await _dir!.delete(recursive: true);
    } catch (e) {
      debugPrint('Could not delete the Phonon model: $e');
    }
    _status = PhononModelStatus.notInstalled;
    notifyListeners();
  }

  Future<String> _fetchString(HttpClient client, String url) async {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    return response.transform(utf8.decoder).join();
  }

  /// Download [url] to [file], returning its size.
  Future<int> _fetchFile(
    HttpClient client,
    String url,
    File file,
    void Function(int received) onProgress,
  ) async {
    final response = await (await client.getUrl(Uri.parse(url))).close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('HTTP ${response.statusCode}', uri: Uri.parse(url));
    }
    final sink = file.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        onProgress(received);
      }
    } finally {
      await sink.close();
    }
    if (response.contentLength >= 0 && received != response.contentLength) {
      throw HttpException('incomplete download', uri: Uri.parse(url));
    }
    return received;
  }
}
