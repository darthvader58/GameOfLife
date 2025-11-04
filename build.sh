echo "Building Conway's Game of Life on Steroids..."
echo ""

# Compile
swiftc -O \
    -framework Metal \
    -framework MetalKit \
    -framework Cocoa \
    Sources/*.swift \
    -o GameOfLife

if [ $? -eq 0 ]; then
    echo "✓ Build successful!"
    echo ""
    echo "Run with: ./GameOfLife"
else
    echo "✗ Build failed"
    exit 1
fi