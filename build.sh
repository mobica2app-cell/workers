#!/bin/bash

set -e

echo "Installing Flutter..."

git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"

export PATH="$HOME/flutter/bin:$PATH"

echo "Flutter version:"
flutter --version

echo "Getting dependencies..."
flutter pub get

echo "Building Flutter Web..."
flutter build web --release

echo "Flutter Web build completed!"