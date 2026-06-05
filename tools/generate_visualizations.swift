import Foundation

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

func writeGridSVG(_ life: ToroidalLife, title: String, path: String, cellSize: Int = 10) throws {
    let width = life.width * cellSize
    let height = life.height * cellSize
    var svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(width) \(height)" role="img" aria-label="\(title)">
    <title>\(title)</title>
    <rect width="100%" height="100%" fill="#05070c"/>
    """

    for y in 0..<life.height {
        for x in 0..<life.width where life.alive(x, y) {
            let px = x * cellSize
            let py = y * cellSize
            svg += "\n<rect x=\"\(px)\" y=\"\(py)\" width=\"\(cellSize)\" height=\"\(cellSize)\" fill=\"#45d1c8\"/>"
        }
    }

    svg += "\n</svg>\n"
    try svg.write(toFile: path, atomically: true, encoding: .utf8)
}

func writeDensityPlot(_ values: [Double], path: String) throws {
    let width = 960.0
    let height = 420.0
    let padding = 48.0
    let maxValue = max(values.max() ?? 1.0, 0.01)

    func point(_ index: Int, _ value: Double) -> String {
        let x = padding + (Double(index) / Double(values.count - 1)) * (width - padding * 2)
        let y = height - padding - (value / maxValue) * (height - padding * 2)
        return "\(String(format: "%.2f", x)),\(String(format: "%.2f", y))"
    }

    let points = values.enumerated().map(point).joined(separator: " ")
    let lastDensity = values.last ?? 0

    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(Int(width)) \(Int(height))" role="img" aria-label="Live-cell density over time">
    <title>Live-cell density over time</title>
    <rect width="100%" height="100%" fill="#f7f9fb"/>
    <line x1="\(padding)" y1="\(height - padding)" x2="\(width - padding)" y2="\(height - padding)" stroke="#9aa6b2" stroke-width="2"/>
    <line x1="\(padding)" y1="\(padding)" x2="\(padding)" y2="\(height - padding)" stroke="#9aa6b2" stroke-width="2"/>
    <polyline points="\(points)" fill="none" stroke="#167c80" stroke-width="4" stroke-linejoin="round" stroke-linecap="round"/>
    <text x="\(padding)" y="28" fill="#1c2733" font-family="Menlo, monospace" font-size="18">Toroidal Game of Life density, 256 generations</text>
    <text x="\(padding)" y="\(height - 14)" fill="#4c5967" font-family="Menlo, monospace" font-size="14">generation</text>
    <text x="\(width - padding - 190)" y="\(padding + 18)" fill="#4c5967" font-family="Menlo, monospace" font-size="14">final density \(String(format: "%.3f", lastDensity))</text>
    </svg>
    """

    try svg.write(toFile: path, atomically: true, encoding: .utf8)
}

let outputDirectory = "Visualizations"
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)

var randomLife = makeRandomLife(width: 96, height: 96, density: 0.30, seed: 0xC0FFEE)
try writeGridSVG(randomLife, title: "Random toroidal seed", path: "\(outputDirectory)/random-seed.svg", cellSize: 6)

var densities: [Double] = []
for generation in 0...256 {
    densities.append(Double(randomLife.liveCount()) / Double(randomLife.width * randomLife.height))

    if generation == 64 {
        try writeGridSVG(randomLife, title: "Toroidal simulation at generation 64", path: "\(outputDirectory)/generation-064.svg", cellSize: 6)
    }

    randomLife.step()
}
try writeDensityPlot(densities, path: "\(outputDirectory)/density-plot.svg")

var glider = makeWraparoundGlider(width: 28, height: 28)
try writeGridSVG(glider, title: "Glider near toroidal edge, generation 0", path: "\(outputDirectory)/wraparound-glider-000.svg")
for _ in 0..<12 {
    glider.step()
}
try writeGridSVG(glider, title: "Glider after wrapping across toroidal edge", path: "\(outputDirectory)/wraparound-glider-012.svg")

print("Generated SVG visualizations in \(outputDirectory)/")
