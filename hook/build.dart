import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Bundles the prebuilt Phonon library (native/phonon, built by
/// native/phonon/build.sh) for the experimental on-device voice, on Android.
/// Targets without a prebuilt library (32-bit Android, the Mac app) get none,
/// and the app reports the voice as unavailable there.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final dir = switch ((code.targetOS, code.targetArchitecture)) {
      (OS.android, Architecture.arm64) => 'android-arm64',
      (OS.android, Architecture.x64) => 'android-x64',
      _ => null,
    };
    if (dir == null) return;
    final file = code.targetOS.dylibFileName('velum_phonon');
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'phonon',
        linkMode: DynamicLoadingBundled(),
        file: input.packageRoot.resolve('native/phonon/prebuilt/$dir/$file'),
      ),
    );
  });
}
