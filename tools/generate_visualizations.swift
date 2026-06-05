import Foundation
import AppKit

struct ToroidalLife {
    let width: Int
    let height: Int
    private(set) var cells: [Bool]

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.cells = Array(repeating: false, count: width * height)
    }

    func index(_ x: Int, _ y: Int) -> Int {
        let wrappedX = (x % width + width) % width
        let wrappedY = (y % height + height) % height
        return wrappedY * width + wrappedX
    }

    mutating func set(_ x: Int, _ y: Int, alive: Bool = true) {
        cells[index(x, y)] = alive
    }

    func alive(_ x: Int, _ y: Int) -> Bool {
        cells[index(x, y)]
    }

    func liveCount() -> Int {
        cells.reduce(0) { $0 + ($1 ? 1 : 0) }
    }

    mutating func step() {
        var next = cells

        for y in 0..<height {
            for x in 0..<width {
                var neighbors = 0

                for dy in -1...1 {
                    for dx in -1...1 where !(dx == 0 && dy == 0) {
                        if alive(x + dx, y + dy) {
                            neighbors += 1
                        }
                    }
                }

                let currentlyAlive = alive(x, y)
                next[index(x, y)] = currentlyAlive
                    ? (neighbors == 2 || neighbors == 3)
                    : (neighbors == 3)
            }
        }

        cells = next
    }
}

func seededRandom(_ value: UInt32) -> UInt32 {
    var x = value
    x ^= x << 13
    x ^= x >> 17
    x ^= x << 5
    return x
}

func makeRandomLife(width: Int, height: Int, density: Double, seed: UInt32) -> ToroidalLife {
    var life = ToroidalLife(width: width, height: height)

    for y in 0..<height {
        for x in 0..<width {
            let hx = UInt32(truncatingIfNeeded: x &* 73_856_093)
            let hy = UInt32(truncatingIfNeeded: y &* 19_349_663)
            let h = seededRandom(hx ^ hy ^ seed)
            let r = Double(h % 10_000) / 10_000.0
            life.set(x, y, alive: r < density)
        }
    }

    return life
}

func makeWraparoundGlider(width: Int, height: Int) -> ToroidalLife {
    var life = ToroidalLife(width: width, height: height)
    let ox = width - 4
    let oy = height - 4

    life.set(ox + 1, oy)
    life.set(ox + 2, oy + 1)
    life.set(ox, oy + 2)
    life.set(ox + 1, oy + 2)
    life.set(ox + 2, oy + 2)

    return life
}

func pngData(width: Int, height: Int, draw: (CGContext) -> Void) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: width * 4,
        bitsPerPixel: 32
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else {
        throw NSError(domain: "Visualization", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create bitmap context"])
    }

    context.setAllowsAntialiasing(false)
    context.setShouldAntialias(false)
    draw(context)

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "Visualization", code: 2, userInfo: [NSLocalizedDescriptionKey: "Could not encode PNG"])
    }

    return data
}

func writePNG(_ data: Data, path: String) throws {
    try data.write(to: URL(fileURLWithPath: path), options: .atomic)
}

func writeGridPNG(_ life: ToroidalLife, path: String, cellSize: Int = 10) throws {
    let width = life.width * cellSize
    let height = life.height * cellSize

    let data = try pngData(width: width, height: height) { context in
        context.setFillColor(CGColor(red: 0.02, green: 0.027, blue: 0.047, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setFillColor(CGColor(red: 0.27, green: 0.82, blue: 0.78, alpha: 1.0))

        for y in 0..<life.height {
            for x in 0..<life.width where life.alive(x, y) {
                let px = x * cellSize
                let py = y * cellSize
                context.fill(CGRect(x: px, y: py, width: cellSize, height: cellSize))
            }
        }
    }

    try writePNG(data, path: path)
}

func writeDensityPlot(_ values: [Double], path: String) throws {
    let width = 960
    let height = 420
    let padding = 48.0
    let maxValue = max(values.max() ?? 1.0, 0.01)

    let data = try pngData(width: width, height: height) { context in
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)

        context.setFillColor(CGColor(red: 0.97, green: 0.98, blue: 0.99, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.setStrokeColor(CGColor(red: 0.60, green: 0.65, blue: 0.70, alpha: 1.0))
        context.setLineWidth(2)
        context.move(to: CGPoint(x: padding, y: Double(height) - padding))
        context.addLine(to: CGPoint(x: Double(width) - padding, y: Double(height) - padding))
        context.move(to: CGPoint(x: padding, y: padding))
        context.addLine(to: CGPoint(x: padding, y: Double(height) - padding))
        context.strokePath()

        context.setStrokeColor(CGColor(red: 0.09, green: 0.49, blue: 0.50, alpha: 1.0))
        context.setLineWidth(4)
        context.setLineJoin(.round)
        context.setLineCap(.round)

        for (index, value) in values.enumerated() {
            let x = padding + (Double(index) / Double(values.count - 1)) * (Double(width) - padding * 2)
            let y = Double(height) - padding - (value / maxValue) * (Double(height) - padding * 2)

            if index == 0 {
                context.move(to: CGPoint(x: x, y: y))
            } else {
                context.addLine(to: CGPoint(x: x, y: y))
            }
        }
        context.strokePath()

        let title = "Toroidal Game of Life density, 256 generations"
        let finalDensity = String(format: "final density %.3f", values.last ?? 0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .regular),
            .foregroundColor: NSColor(red: 0.11, green: 0.15, blue: 0.20, alpha: 1.0)
        ]
        title.draw(at: CGPoint(x: padding, y: 16), withAttributes: attributes)
        finalDensity.draw(at: CGPoint(x: Double(width) - padding - 210, y: padding), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor(red: 0.30, green: 0.35, blue: 0.40, alpha: 1.0)
        ])
    }

    try writePNG(data, path: path)
}

struct TorusPoint {
    let depth: Double
    let x: Double
    let y: Double
    let radius: Double
    let color: CGColor
}

func torusProjection(theta: Double, phi: Double, canvasWidth: Int, canvasHeight: Int) -> (x: Double, y: Double, depth: Double, light: Double) {
    let majorRadius = 1.55
    let minorRadius = 0.56
    let tube = majorRadius + minorRadius * cos(phi)

    var x = tube * cos(theta)
    var y = tube * sin(theta)
    var z = minorRadius * sin(phi)

    let zRotation = -0.58
    let xAfterZ = x * cos(zRotation) - y * sin(zRotation)
    let yAfterZ = x * sin(zRotation) + y * cos(zRotation)
    x = xAfterZ
    y = yAfterZ

    let xRotation = 0.98
    let yAfterX = y * cos(xRotation) - z * sin(xRotation)
    let zAfterX = y * sin(xRotation) + z * cos(xRotation)
    y = yAfterX
    z = zAfterX

    let scale = Double(min(canvasWidth, canvasHeight)) * 0.28
    let screenX = Double(canvasWidth) * 0.50 + x * scale
    let screenY = Double(canvasHeight) * 0.52 - y * scale
    let light = max(0.20, min(1.0, 0.50 + z * 0.40 + sin(phi) * 0.20))

    return (screenX, screenY, z, light)
}

func writeTorusPNG(_ life: ToroidalLife, path: String) throws {
    let width = 1040
    let height = 760

    let data = try pngData(width: width, height: height) { context in
        context.setShouldAntialias(true)
        context.setAllowsAntialiasing(true)
        context.setFillColor(CGColor(red: 0.015, green: 0.018, blue: 0.030, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        var points: [TorusPoint] = []

        for y in stride(from: 0, to: life.height, by: 2) {
            for x in stride(from: 0, to: life.width, by: 2) {
                let theta = (Double(x) / Double(life.width)) * Double.pi * 2.0
                let phi = (Double(y) / Double(life.height)) * Double.pi * 2.0
                let projected = torusProjection(theta: theta, phi: phi, canvasWidth: width, canvasHeight: height)
                let shade = projected.light

                points.append(TorusPoint(
                    depth: projected.depth,
                    x: projected.x,
                    y: projected.y,
                    radius: 2.2,
                    color: CGColor(red: 0.05 * shade, green: 0.22 * shade, blue: 0.27 * shade, alpha: 0.50)
                ))
            }
        }

        for y in 0..<life.height {
            for x in 0..<life.width where life.alive(x, y) {
                let theta = (Double(x) / Double(life.width)) * Double.pi * 2.0
                let phi = (Double(y) / Double(life.height)) * Double.pi * 2.0
                let projected = torusProjection(theta: theta, phi: phi, canvasWidth: width, canvasHeight: height)
                let front = max(0.0, min(1.0, (projected.depth + 1.6) / 3.2))
                let shade = projected.light

                points.append(TorusPoint(
                    depth: projected.depth + 0.01,
                    x: projected.x,
                    y: projected.y,
                    radius: 3.0 + front * 2.8,
                    color: CGColor(
                        red: min(1.0, 0.25 + 0.50 * shade + 0.20 * front),
                        green: min(1.0, 0.72 + 0.22 * shade),
                        blue: min(1.0, 0.68 + 0.24 * front),
                        alpha: 0.72 + 0.25 * front
                    )
                ))
            }
        }

        for point in points.sorted(by: { $0.depth < $1.depth }) {
            context.setFillColor(point.color)
            context.fillEllipse(in: CGRect(
                x: point.x - point.radius,
                y: point.y - point.radius,
                width: point.radius * 2.0,
                height: point.radius * 2.0
            ))
        }

        let title = "Toroidal plane projected as a 3D torus"
        let subtitle = "Live cells are mapped from the wrapped 2D grid onto the donut surface"
        title.draw(at: CGPoint(x: 42, y: 34), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 22, weight: .semibold),
            .foregroundColor: NSColor(red: 0.88, green: 0.94, blue: 0.96, alpha: 1.0)
        ])
        subtitle.draw(at: CGPoint(x: 42, y: 64), withAttributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular),
            .foregroundColor: NSColor(red: 0.57, green: 0.68, blue: 0.72, alpha: 1.0)
        ])
    }

    try writePNG(data, path: path)
}

let outputDirectory = "Visualizations"
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

var randomLife = makeRandomLife(width: 96, height: 96, density: 0.30, seed: 0xC0FFEE)
try writeGridPNG(randomLife, path: "\(outputDirectory)/random-seed.png", cellSize: 6)

var densities: [Double] = []
for generation in 0...256 {
    densities.append(Double(randomLife.liveCount()) / Double(randomLife.width * randomLife.height))

    if generation == 64 {
        try writeGridPNG(randomLife, path: "\(outputDirectory)/generation-064.png", cellSize: 6)
        try writeTorusPNG(randomLife, path: "\(outputDirectory)/toroidal-plane-3d.png")
    }

    randomLife.step()
}
try writeDensityPlot(densities, path: "\(outputDirectory)/density-plot.png")

var glider = makeWraparoundGlider(width: 28, height: 28)
try writeGridPNG(glider, path: "\(outputDirectory)/wraparound-glider-000.png")
for _ in 0..<12 {
    glider.step()
}
try writeGridPNG(glider, path: "\(outputDirectory)/wraparound-glider-012.png")

print("Generated PNG visualizations in \(outputDirectory)/")
