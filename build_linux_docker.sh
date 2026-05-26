#!/bin/bash
# Cross-compile Linux binaries (arm64 & x86_64) using Ubuntu Docker container.
set -e

echo "=== Building Linux arm64 and x86_64 binaries via Docker ==="

# Ensure dist exists
mkdir -p dist

# Run the build inside an Ubuntu container, passing current directory as volume
# Using DEBIAN_FRONTEND=noninteractive to make apt installations completely silent/non-interactive
docker run --rm -v "$(pwd)":/workspace -w /workspace ubuntu:22.04 bash -c '
    set -e
    
    # Set up multi-arch package repository configuration dynamically based on native arch
    NATIVE_ARCH=$(dpkg --print-architecture)
    if [ "$NATIVE_ARCH" = "arm64" ]; then
        sed -i -e "s/deb http/deb [arch=arm64] http/g" /etc/apt/sources.list
        sed -i -e "s/deb-src http/deb-src [arch=arm64] http/g" /etc/apt/sources.list
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=amd64] http://archive.ubuntu.com/ubuntu/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=amd64] http://security.ubuntu.com/ubuntu/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list
    elif [ "$NATIVE_ARCH" = "amd64" ]; then
        sed -i -e "s/deb http/deb [arch=amd64] http/g" /etc/apt/sources.list
        sed -i -e "s/deb-src http/deb-src [arch=amd64] http/g" /etc/apt/sources.list
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-updates main restricted universe multiverse" >> /etc/apt/sources.list
        echo "deb [arch=arm64] http://ports.ubuntu.com/ubuntu-ports/ jammy-security main restricted universe multiverse" >> /etc/apt/sources.list
    fi

    dpkg --add-architecture amd64 || true
    dpkg --add-architecture arm64 || true
    apt-get update -y -q

    # Setup compilers dynamically based on native arch to prevent dependency conflicts
    if [ "$NATIVE_ARCH" = "arm64" ]; then
        ARM64_CC="gcc"
        ARM64_CXX="g++"
        ARM64_STRIP="strip"
        X86_64_CC="x86_64-linux-gnu-gcc"
        X86_64_CXX="x86_64-linux-gnu-g++"
        X86_64_STRIP="x86_64-linux-gnu-strip"

        DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
            build-essential \
            cmake \
            curl \
            git \
            gcc-x86-64-linux-gnu \
            g++-x86-64-linux-gnu \
            libbluetooth-dev \
            libbluetooth-dev:amd64
    else
        ARM64_CC="aarch64-linux-gnu-gcc"
        ARM64_CXX="aarch64-linux-gnu-g++"
        ARM64_STRIP="aarch64-linux-gnu-strip"
        X86_64_CC="gcc"
        X86_64_CXX="g++"
        X86_64_STRIP="strip"

        DEBIAN_FRONTEND=noninteractive apt-get install -y -q \
            build-essential \
            cmake \
            curl \
            git \
            gcc-aarch64-linux-gnu \
            g++-aarch64-linux-gnu \
            libbluetooth-dev \
            libbluetooth-dev:arm64
    fi

    # Install Rustup
    curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable
    source "$HOME/.cargo/env"
    rustup target add x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu

    # 1. Build Rust Linux x86_64
    echo "Building Rust Linux x86_64..."
    CARGO_TARGET_X86_64_UNKNOWN_LINUX_GNU_LINKER=$X86_64_CC \
        cargo build --manifest-path rust/Cargo.toml --release --target x86_64-unknown-linux-gnu
    cp rust/target/x86_64-unknown-linux-gnu/release/bmapctl dist/bmapctl-rust-linux-x86_64
    $X86_64_STRIP dist/bmapctl-rust-linux-x86_64

    # 2. Build Rust Linux arm64
    echo "Building Rust Linux arm64..."
    CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=$ARM64_CC \
        cargo build --manifest-path rust/Cargo.toml --release --target aarch64-unknown-linux-gnu
    cp rust/target/aarch64-unknown-linux-gnu/release/bmapctl dist/bmapctl-rust-linux-arm64
    $ARM64_STRIP dist/bmapctl-rust-linux-arm64

    # 3. Build C++ Linux x86_64
    echo "Building C++ Linux x86_64..."
    cmake -S cpp -B cpp/build-linux-x86_64 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=$X86_64_CC \
        -DCMAKE_CXX_COMPILER=$X86_64_CXX
    cmake --build cpp/build-linux-x86_64 --config Release
    cp cpp/build-linux-x86_64/bmapctl dist/bmapctl-cpp-linux-x86_64
    $X86_64_STRIP dist/bmapctl-cpp-linux-x86_64

    # 4. Build C++ Linux arm64
    echo "Building C++ Linux arm64..."
    cmake -S cpp -B cpp/build-linux-arm64 \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_C_COMPILER=$ARM64_CC \
        -DCMAKE_CXX_COMPILER=$ARM64_CXX
    cmake --build cpp/build-linux-arm64 --config Release
    cp cpp/build-linux-arm64/bmapctl dist/bmapctl-cpp-linux-arm64
    $ARM64_STRIP dist/bmapctl-cpp-linux-arm64
'

echo "=== Linux builds completed successfully! ==="
