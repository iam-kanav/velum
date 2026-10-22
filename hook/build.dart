import 'dart:io';
import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

/// Bundles the prebuilt Phonon library (native/phonon, built by
/// native/phonon/build.sh) for the experimental on-device voice, on Android
/// and the Mac. Targets without a prebuilt library (32-bit Android) get none,
/// and the app reports the voice as unavailable there.
void main(List<String> args) async {
  await build(args, (input, output) async {
    if (!input.config.buildCodeAssets) return;
    final code = input.config.code;
    final dir = switch ((code.targetOS, code.targetArchitecture)) {
      (OS.android, Architecture.arm64) => 'android-arm64',
      (OS.android, Architecture.x64) => 'android-x64',
      (OS.macOS, Architecture.arm64) => 'macos-arm64',
      (OS.macOS, Architecture.x64) => 'macos-x64',
      _ => null,
    };
    if (dir == null) return;
    final name = code.targetOS.dylibFileName('velum_phonon');
    final prebuilt =
        input.packageRoot.resolve('native/phonon/prebuilt/$dir/$name');
    // Hand Flutter a copy: it treats asset files as build outputs it may
    // delete, which would take the committed library with it.
    final copy = input.outputDirectory.resolve(name);
    await File.fromUri(prebuilt).copy(copy.toFilePath());
    output.dependencies.add(prebuilt);
    output.assets.code.add(
      CodeAsset(
        package: input.packageName,
        name: 'phonon',
        linkMode: DynamicLoadingBundled(),
        file: copy,
      ),
    );
  });
}
