import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Audio source that plays encoded audio (MP3, WAV) from memory.
// ignore: experimental_member_use
class BytesAudioSource extends StreamAudioSource {
  final Uint8List _bytes;
  final String _contentType;
  BytesAudioSource(this._bytes, this._contentType);

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _bytes.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_bytes.sublist(start, end)),
      contentType: _contentType,
    );
  }
}
