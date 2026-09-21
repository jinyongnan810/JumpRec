#!/bin/sh
set -e

# Xcode Cloud build environments do not include the Metal Toolchain by default in Xcode 16/26.
# If the toolchain is missing, download and install it so CompileMetalFile can succeed.
if xcodebuild -showComponent metalToolchain >/dev/null 2>&1; then
    echo "✓ Metal toolchain is already installed"
else
    echo "❌ Metal toolchain is not installed. Downloading..."
    xcodebuild -downloadComponent metalToolchain -exportPath /tmp/metalToolchainDownload/
    echo "📦 Importing Metal toolchain..."
    xcodebuild -importComponent metalToolchain -importPath /tmp/metalToolchainDownload/*.exportedBundle
    rm -rf /tmp/metalToolchainDownload
    echo "✓ Metal toolchain installation complete"
fi
