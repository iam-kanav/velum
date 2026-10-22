// Calls into the Phonon library (native/phonon), which hook/build.dart
// bundles into the app. Only phonon_tts_engine.dart's worker isolate uses
// these, apart from phononCancel.
@DefaultAsset('package:velum/phonon')
library;

import 'dart:ffi';
import 'dart:io';

final class PhononHandle extends Opaque {}

final class PhononCancelToken extends Opaque {}

@Native<Pointer<PhononHandle> Function(Pointer<Char>, Pointer<Char>, Uint32)>(symbol: 'phonon_new')
external Pointer<PhononHandle> phononNew(
  Pointer<Char> dir,
  Pointer<Char> lang,
  int threads,
);

@Native<Uint32 Function(Pointer<PhononHandle>)>(symbol: 'phonon_sample_rate')
external int phononSampleRate(Pointer<PhononHandle> h);

@Native<Pointer<Char> Function(Pointer<PhononHandle>)>(symbol: 'phonon_voices')
external Pointer<Char> phononVoices(Pointer<PhononHandle> h);

@Native<Bool Function(Pointer<PhononHandle>, Pointer<Char>)>(symbol: 'phonon_set_voice')
external bool phononSetVoice(Pointer<PhononHandle> h, Pointer<Char> name);

@Native<Pointer<Float> Function(Pointer<PhononHandle>, Pointer<Char>, Pointer<Size>)>(symbol: 'phonon_synth')
external Pointer<Float> phononSynth(
  Pointer<PhononHandle> h,
  Pointer<Char> text,
  Pointer<Size> len,
);

@Native<Void Function(Pointer<Float>, Size)>(symbol: 'phonon_free_pcm')
external void phononFreePcm(Pointer<Float> pcm, int len);

@Native<Pointer<PhononCancelToken> Function(Pointer<PhononHandle>)>(symbol: 'phonon_cancel_token')
external Pointer<PhononCancelToken> phononCancelToken(Pointer<PhononHandle> h);

/// Safe from any isolate while another one is in [phononSynth].
@Native<Void Function(Pointer<PhononCancelToken>)>(symbol: 'phonon_cancel')
external void phononCancel(Pointer<PhononCancelToken> token);

@Native<Pointer<Char> Function(Pointer<PhononHandle>)>(symbol: 'phonon_last_error')
external Pointer<Char> phononLastError(Pointer<PhononHandle> h);

@Native<Void Function(Pointer<PhononHandle>)>(symbol: 'phonon_free')
external void phononFree(Pointer<PhononHandle> h);

/// Whether this device can run the bundled library. It is built for 64-bit
/// Android only, and the phone build uses ARMv8.2 instructions (dotprod,
/// fp16) that crash older CPUs, so check for them before loading.
bool phononSupported() {
  final abi = Abi.current();
  if (abi == Abi.androidX64) return true;
  if (abi != Abi.androidArm64) return false;
  try {
    final features = File('/proc/cpuinfo')
        .readAsLinesSync()
        .where((l) => l.startsWith('Features'))
        .expand((l) => l.split(':').last.trim().split(' '))
        .toSet();
    return features.contains('asimddp') && features.contains('asimdhp');
  } catch (_) {
    return false;
  }
}
