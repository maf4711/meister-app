#!/bin/bash
# Compile the optimized iOS engines against the real SDK without booting a simulator.
set -euo pipefail
cd "$(dirname "$0")/.."

xcrun --sdk iphonesimulator swiftc \
    -sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -target arm64-apple-ios17.0-simulator -swift-version 5 -parse-as-library -typecheck \
    MeisterIOS/Contacts/FuzzyMatcher.swift \
    MeisterIOS/Contacts/ContactDeduplicator.swift \
    MeisterIOS/Contacts/PhoneNormalizer.swift \
    MeisterIOS/Contacts/ContactScanner.swift \
    MeisterIOS/Photos/SimilarityClustering.swift \
    MeisterIOS/Photos/PhotoScanner.swift \
    MeisterIOS/Photos/PhotoThumbnailLoader.swift \
    MeisterIOS/Photos/BestShotSelector.swift \
    MeisterIOS/Photos/BlurDetector.swift
