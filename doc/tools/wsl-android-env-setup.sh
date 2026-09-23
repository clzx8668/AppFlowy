#!/usr/bin/env bash
# 在 WSL Ubuntu 内准备 AppFlowy Android(Rust) 交叉编译环境（一次性）
# 用法（Windows PowerShell，无需 sudo 密码）：wsl -d Ubuntu -u root -- bash /mnt/e/Dev/AppFlowy/doc/tools/wsl-android-env-setup.sh
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "[1/5] apt 依赖"
apt-get update -qq
apt-get install -y -qq build-essential clang libclang-dev pkg-config curl git unzip ca-certificates >/dev/null

echo "[2/5] Rust 1.85（与 frontend/rust-lib/rust-toolchain.toml 对齐）"
if ! command -v cargo >/dev/null 2>&1; then
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/rustup-init.sh
  sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain 1.85 --component clippy,rustfmt >/dev/null
fi
export PATH="$HOME/.cargo/bin:$PATH"

echo "[3/5] Android 目标"
rustup target add aarch64-linux-android

echo "[4/5] cargo-ndk（Rust 1.85 不支持 4.x，固定 3.5.4）"
command -v cargo-ndk >/dev/null 2>&1 || cargo install cargo-ndk --version 3.5.4 --locked

echo "[5/5] Linux 版 Android NDK r24 (= 24.0.8215888)"
NDK_DIR=/root/android-ndk-r24
if [ ! -x "$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" ]; then
  ZIP=/root/android-ndk-r24-linux.zip
  [ -s "$ZIP" ] || curl -L --retry 3 -o "$ZIP" \
    https://mirrors.cloud.tencent.com/AndroidSDK/android-ndk-r24-linux.zip
  (cd /root && unzip -q -o "$ZIP")
fi

rustc --version
cargo ndk --version
"$NDK_DIR/toolchains/llvm/prebuilt/linux-x86_64/bin/clang" --version | head -1
echo "SETUP_OK"
