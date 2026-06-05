import Cocoa
import MetalKit

class GameOfLifeView: MTKView {
    struct RenderUniforms {
        var gridWidth: UInt32
        var gridHeight: UInt32
        var viewportWidth: UInt32
        var viewportHeight: UInt32
        var time: Float
        var zoom: Float
        var panX: Float
        var panY: Float
    }

    // Metal resources
    var commandQueue: MTLCommandQueue!
    var gameOfLifePipeline: MTLComputePipelineState!
    var randomizePipeline: MTLComputePipelineState!
    var visualizePipeline: MTLComputePipelineState!
    var clearPipeline: MTLComputePipelineState!
    
    // Simulation state
    let gridSize: Int
    var stateTextures: [MTLTexture] = []
    var currentStateIndex = 0
    
    var simulationPaused = false
    var frameCount: UInt32 = 0
    var startTime = Date()
    var launchTime = Date()
    var zoom: Float = 1.0
    var panX: Float = 0.0
    var panY: Float = 0.0

    static func chooseGridSize(for device: MTLDevice?) -> Int {
        if let override = ProcessInfo.processInfo.environment["GOL_GRID_SIZE"],
           let value = Int(override),
           value >= 64 {
            return value
        }

        guard let device else { return 2048 }
        let bytesPerGrid = { (size: Int) in size * size * 2 }
        let budget = max(Int(device.recommendedMaxWorkingSetSize / 8), 256 * 1024 * 1024)

        if bytesPerGrid(8192) <= budget { return 8192 }
        if bytesPerGrid(4096) <= budget { return 4096 }
        return 2048
    }
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        let metalDevice = device ?? MTLCreateSystemDefaultDevice()
        self.gridSize = GameOfLifeView.chooseGridSize(for: metalDevice)
        super.init(frame: frameRect, device: metalDevice)
        setup()
    }
    
    required init(coder: NSCoder) {
        let metalDevice = MTLCreateSystemDefaultDevice()
        self.gridSize = GameOfLifeView.chooseGridSize(for: metalDevice)
        super.init(coder: coder)
        setup()
    }
    
    func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        self.device = device
        self.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        self.framebufferOnly = false
        self.colorPixelFormat = .bgra8Unorm
        self.preferredFramesPerSecond = 60
        
        commandQueue = device.makeCommandQueue()!
        
        // Load shaders
        setupShaders()
        
        // Create textures
        setupTextures()
        
        // Initialize with random pattern
        randomizeGrid(density: 0.3)
        
        // Setup mouse tracking
        self.delegate = self
        
        print("Game of Life initialized")
        print("  Device: \(device.name)")
        print("  Grid: \(gridSize)x\(gridSize) (\(gridSize * gridSize / 1_000_000)M cells)")
        print("  Controls:")
        print("    SPACE - Pause/Resume")
        print("    R - Randomize")
        print("    C - Clear")
        print("    +/- - Zoom")
        print("    Arrow keys - Pan")
    }
    
    func setupShaders() {
        guard let device = device else { return }
        
        // Load Metal library from source
        let shaderPath = [
            "Shaders.metal",
            "./Shaders.metal",
            "../Shaders.metal"
        ].first { FileManager.default.fileExists(atPath: $0) }

        guard let shaderPath else {
            fatalError("Could not find Shaders.metal. Run the app from the project directory.")
        }

        let shaderSource = try! String(contentsOfFile: shaderPath, encoding: .utf8)
        let library = try! device.makeLibrary(source: shaderSource, options: nil)
        
        gameOfLifePipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "gameOfLife")!)
        randomizePipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "randomize")!)
        visualizePipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "visualize")!)
        clearPipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "clearGrid")!)
    }
    
    func setupTextures() {
        guard let device = device else { return }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Uint,
            width: gridSize,
            height: gridSize,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .private
        
        // Double buffering
        stateTextures.append(device.makeTexture(descriptor: textureDescriptor)!)
        stateTextures.append(device.makeTexture(descriptor: textureDescriptor)!)
    }
    
    func randomizeGrid(density: Float = 0.3) {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.setComputePipelineState(randomizePipeline)
        encoder.setTexture(stateTextures[currentStateIndex], index: 0)
        
        var densityVar = density
        var seed = UInt32.random(in: 0..<UInt32.max)
        encoder.setBytes(&densityVar, length: MemoryLayout<Float>.size, index: 0)
        encoder.setBytes(&seed, length: MemoryLayout<UInt32>.size, index: 1)
        
        let gridSize = MTLSize(width: self.gridSize, height: self.gridSize, depth: 1)
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    func clearGrid() {
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        encoder.setComputePipelineState(clearPipeline)
        encoder.setTexture(stateTextures[currentStateIndex], index: 0)
        
        let gridSize = MTLSize(width: self.gridSize, height: self.gridSize, depth: 1)
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123:
            panX -= 0.04 / zoom
            return
        case 124:
            panX += 0.04 / zoom
            return
        case 125:
            panY += 0.04 / zoom
            return
        case 126:
            panY -= 0.04 / zoom
            return
        default:
            break
        }

        switch event.charactersIgnoringModifiers {
        case " ":
            simulationPaused.toggle()
            print(simulationPaused ? "Paused" : "Resumed")
        case "r", "R":
            randomizeGrid(density: 0.3)
            print("Randomized")
        case "c", "C":
            clearGrid()
            print("Cleared")
        case "+", "=":
            zoom = min(zoom * 1.25, 32.0)
        case "-", "_":
            zoom = max(zoom / 1.25, 1.0)
        default:
            super.keyDown(with: event)
        }
    }
    
    override var acceptsFirstResponder: Bool { true }
}

extension GameOfLifeView: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
        guard let drawable = currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
        
        frameCount += 1
        let elapsedTime = Float(Date().timeIntervalSince(startTime))
        
        // Run simulation
        if !simulationPaused {
            encoder.setComputePipelineState(gameOfLifePipeline)
            encoder.setTexture(stateTextures[currentStateIndex], index: 0)
            encoder.setTexture(stateTextures[1 - currentStateIndex], index: 1)
            
            let gridSize = MTLSize(width: self.gridSize, height: self.gridSize, depth: 1)
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            
            currentStateIndex = 1 - currentStateIndex
        }
        
        // Visualize
        encoder.setComputePipelineState(visualizePipeline)
        encoder.setTexture(stateTextures[currentStateIndex], index: 0)
        encoder.setTexture(drawable.texture, index: 1)

        var uniforms = RenderUniforms(
            gridWidth: UInt32(gridSize),
            gridHeight: UInt32(gridSize),
            viewportWidth: UInt32(drawable.texture.width),
            viewportHeight: UInt32(drawable.texture.height),
            time: elapsedTime,
            zoom: zoom,
            panX: panX,
            panY: panY
        )
        encoder.setBytes(&uniforms, length: MemoryLayout<RenderUniforms>.stride, index: 0)
        
        let gridSize = MTLSize(width: drawable.texture.width, height: drawable.texture.height, depth: 1)
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
        
        // FPS counter
        if frameCount % 60 == 0 {
            let fps = 60.0 / Date().timeIntervalSince(startTime)
            print(String(format: "FPS: %.1f", fps))
            startTime = Date()
        }
    }
}
