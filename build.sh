#!/bin/sh
set -eu

echo "Building Conway's Game of Life..."
echo ""

mkdir -p .build/module-cache

swiftc -O \
    -module-cache-path .build/module-cache \
    -framework Metal \
    -framework MetalKit \
    -framework Cocoa \
    main.swift \
    AppDelegate.swift \
    GameOfLifeView.swift \
    -o GameOfLife

echo "Build successful"
echo ""
echo "Run with: ./GameOfLife"
