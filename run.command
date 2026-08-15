#!/bin/zsh
# Build (release) and launch the Blackmagic Camera Control app.
cd "$(dirname "$0")"
swift build -c release --disable-sandbox && exec .build/release/BlackmagicControl
