import Cocoa
import MetalKit

class GameOfLifeView: MTKView {
    // Metal resources
    var commandQueue: MTLCommandQueue!
    var gameOfLifePipeline: MTLComputePipelineState!
    var randomizePipeline: MTLComputePipelineState!
    var visualizePipeline: MTLComputePipelineState!
    var clearPipeline: MTLComputePipelineState!
    
    // Simulation state
    let GRID_SIZE = 8192  // 67 million cells!
    var stateTextures: [MTLTexture] = []
    var currentStateIndex = 0
    var displayTexture: MTLTexture!
    
    var isPaused = false
    var frameCount: UInt32 = 0
    var startTime = Date()
    
    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setup()
    }
    
    required init(coder: NSCoder) {
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
        self.preferredFramesPerSecond = 60
        
        commandQueue = device.makeCommandQueue()!
        
        // Load shaders
        setupShaders()
        
        // Create textures
        setupTextures()
        
        // Initialize with random pattern
        randomizeGrid(density: 0.3)
        
        // Setup mouse tracking
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        
        self.delegate = self
        
        print("✓ Game of Life initialized")
        print("  Grid: \\(GRID_SIZE)×\\(GRID_SIZE) (\\(GRID_SIZE*GRID_SIZE/1_000_000)M cells)")
        print("  Controls:")
        print("    SPACE - Pause/Resume")
        print("    R - Randomize")
        print("    C - Clear")
    }
    
    func setupShaders() {
        guard let device = device else { return }
        
        // Load Metal library from source
        let shaderSource = try! String(contentsOfFile: "../Shaders.metal")
        let library = try! device.makeLibrary(source: shaderSource, options: nil)
        
        gameOfLifePipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "gameOfLife")!)
        randomizePipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "randomize")!)
        visualizePipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "visualize")!)
        clearPipeline = try! device.makeComputePipelineState(function: library.makeFunction(name: "clearGrid")!)
    }
    
    func setupTextures() {
        guard let device = device else { return }
        
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba32Float,
            width: GRID_SIZE,
            height: GRID_SIZE,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        textureDescriptor.storageMode = .private
        
        // Double buffering
        stateTextures.append(device.makeTexture(descriptor: textureDescriptor)!)
        stateTextures.append(device.makeTexture(descriptor: textureDescriptor)!)
        
        // Display texture
        displayTexture = device.makeTexture(descriptor: textureDescriptor)!
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
        
        let gridSize = MTLSize(width: GRID_SIZE, height: GRID_SIZE, depth: 1)
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
        
        let gridSize = MTLSize(width: GRID_SIZE, height: GRID_SIZE, depth: 1)
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
    }
    
    override func keyDown(with event: NSEvent) {
        switch event.charactersIgnoringModifiers {
        case " ":
            isPaused.toggle()
            print(isPaused ? "⏸ Paused" : "▶ Resumed")
        case "r", "R":
            randomizeGrid(density: 0.3)
            print("🔄 Randomized")
        case "c", "C":
            clearGrid()
            print("🗑 Cleared")
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
        if !isPaused {
            encoder.setComputePipelineState(gameOfLifePipeline)
            encoder.setTexture(stateTextures[currentStateIndex], index: 0)
            encoder.setTexture(stateTextures[1 - currentStateIndex], index: 1)
            
            let gridSize = MTLSize(width: GRID_SIZE, height: GRID_SIZE, depth: 1)
            let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
            encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
            
            currentStateIndex = 1 - currentStateIndex
        }
        
        // Visualize
        encoder.setComputePipelineState(visualizePipeline)
        encoder.setTexture(stateTextures[currentStateIndex], index: 0)
        encoder.setTexture(displayTexture, index: 1)
        
        var time = elapsedTime
        encoder.setBytes(&time, length: MemoryLayout<Float>.size, index: 0)
        
        let gridSize = MTLSize(width: GRID_SIZE, height: GRID_SIZE, depth: 1)
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        encoder.dispatchThreads(gridSize, threadsPerThreadgroup: threadGroupSize)
        
        encoder.endEncoding()
        
        // Blit to drawable
        if let blitEncoder = commandBuffer.makeBlitCommandEncoder() {
            blitEncoder.copy(
                from: displayTexture,
                sourceSlice: 0,
                sourceLevel: 0,
                sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                sourceSize: MTLSize(width: GRID_SIZE, height: GRID_SIZE, depth: 1),
                to: drawable.texture,
                destinationSlice: 0,
                destinationLevel: 0,
                destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0)
            )
            blitEncoder.endEncoding()
        }
        
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