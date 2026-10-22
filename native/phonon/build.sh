#!/bin/bash
# Build the Phonon library for Velum and copy it to prebuilt/, which
# hook/build.dart bundles into the app. Rebuild after changing src/ or the
# ptts version. Needs Rust (https://rustup.rs) with the targets below,
# cargo-ndk (`cargo install cargo-ndk`) and the Android NDK; run it on a Mac
# for the Mac libraries.
set -euo pipefail
cd "$(dirname "$0")"

export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/27.0.12077973}"
rustup target add aarch64-linux-android x86_64-linux-android \
  aarch64-apple-darwin x86_64-apple-darwin >/dev/null

# Phonon's kernels are picked at compile time. dotprod and fp16 (ARMv8.2) are
# on nearly every phone since 2019; the app checks for them before loading
# the library, which would crash without them. 16 KB pages for Android 15+.
COMMON="-C strip=symbols -C link-arg=-Wl,-z,max-page-size=16384"
export CARGO_TARGET_AARCH64_LINUX_ANDROID_RUSTFLAGS="$COMMON -C target-cpu=generic -C target-feature=+dotprod,+fp16"
export CARGO_TARGET_X86_64_LINUX_ANDROID_RUSTFLAGS="$COMMON -C target-cpu=x86-64"
unset RUSTFLAGS CARGO_ENCODED_RUSTFLAGS
cargo ndk -t arm64-v8a -t x86_64 -P 24 build --release

# Every Apple silicon Mac has the M1's instructions. Intel Macs need AVX2
# (2013 on), which the app checks for. The app framework is renamed by
# Flutter, so the install name only has to be relative.
export MACOSX_DEPLOYMENT_TARGET=12.0
MAC="-C strip=symbols -C link-arg=-Wl,-install_name,@rpath/libvelum_phonon.dylib"
export CARGO_TARGET_AARCH64_APPLE_DARWIN_RUSTFLAGS="$MAC -C target-cpu=apple-m1"
export CARGO_TARGET_X86_64_APPLE_DARWIN_RUSTFLAGS="$MAC -C target-cpu=x86-64-v3"
cargo build --release --target aarch64-apple-darwin --target x86_64-apple-darwin

copy() { mkdir -p "prebuilt/$2" && cp "target/$1/release/$3" "prebuilt/$2/$3"; }
copy aarch64-linux-android android-arm64 libvelum_phonon.so
copy x86_64-linux-android android-x64 libvelum_phonon.so
copy aarch64-apple-darwin macos-arm64 libvelum_phonon.dylib
copy x86_64-apple-darwin macos-x64 libvelum_phonon.dylib
du -sh prebuilt/*/*
