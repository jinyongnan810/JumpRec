#!/bin/sh
set -e

# Install the Metal toolchain if it is missing from the Xcode Cloud environment.
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
