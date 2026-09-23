#!/usr/bin/env bash
# 在 WSL 内为 Android(arm64-v8a) 交叉编译 AppFlowy Rust 内核，并把 .so 回填到 jniLibs
# 用法：wsl -d Ubuntu -u root -- bash /mnt/e/Dev/AppFlowy/doc/tools/android-rust-build.sh
set -euo pipefail

export PATH="$HOME/.cargo/bin:$PATH"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/root/android-ndk-r24}"
export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/af-target-android}"

# bindgen 交叉编译必须给 NDK 的 target + sysroot，否则会去读宿主机 glibc 头文件而失败
NDK_TOOLCHAIN="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64"
export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--target=aarch64-linux-android21 --sysroot=$NDK_TOOLCHAIN/sysroot"

REPO="${REPO:-/mnt/e/Dev/AppFlowy}"
JNI_SRC="$REPO/frontend/rust-lib/jniLibs"
JNI_DST="$REPO/frontend/appflowy_flutter/android/app/src/main/jniLibs"

if [ ! -x "$NDK_TOOLCHAIN/bin/clang" ]; then
  echo "找不到 Android NDK(linux-x86_64): $ANDROID_NDK_HOME" >&2
  echo "请先执行 doc/tools/wsl-android-env-setup.sh" >&2
  exit 1
fi

cd "$REPO/frontend/rust-lib"

# 用 cargo rustc --crate-type cdylib 产出 .so，等价于上游 cargo-make 的 setup-crate-type，
# 但不修改 dart-ffi/Cargo.toml（保证仓库工作区干净）
echo "==> cargo ndk build (arm64-v8a)"
cargo ndk -t arm64-v8a -o ./jniLibs rustc --crate-type cdylib \
  --features "dart,openssl_vendored" --package=dart-ffi

# 注意：不要清空 jniLibs 目录。android/app/src/main/CMakeLists.txt 会在 configure 阶段
# 往同目录拷贝 libc++_shared.so，libdart_ffi.so 依赖它（缺失会导致真机 dlopen 失败：
# "library libc++_shared.so not found"）。这里只覆盖我们自己的内核产物。
echo "==> 回填 jniLibs"
mkdir -p "$JNI_DST/arm64-v8a"
cp -f "$JNI_SRC/arm64-v8a/libdart_ffi.so" "$JNI_DST/arm64-v8a/"

# 兜底：若 libc++_shared.so 缺失（例如 jniLibs 被清理过且未重新 configure），从 NDK 补齐
LIBCXX="$JNI_DST/arm64-v8a/libc++_shared.so"
if [ ! -f "$LIBCXX" ]; then
  NDK_LIBCXX="$ANDROID_NDK_HOME/sources/cxx-stl/llvm-libc++/libs/arm64-v8a/libc++_shared.so"
  if [ -f "$NDK_LIBCXX" ]; then
    cp -f "$NDK_LIBCXX" "$LIBCXX"
    echo "已从 NDK 补齐 libc++_shared.so"
  else
    echo "警告：未找到 libc++_shared.so，构建 APK 前请重新执行 flutter build（触发 CMake configure）" >&2
  fi
fi

ls -la "$JNI_DST/arm64-v8a"
echo "ANDROID_RUST_OK"
