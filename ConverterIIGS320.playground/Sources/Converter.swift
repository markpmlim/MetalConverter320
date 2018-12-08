/*
 To run this demo under XCode 9.x or later, minor editing is required.
 */
import AppKit
import MetalKit
import simd

// We need to pass the 16 color tables as 1D array of UInt16's to the
// metal shader. Each color table has 16 color entries of size 2 bytes.
class ExtractIIgsGraphicData {
    var iigsBitmap: [UInt8]?
    var colorTables: [UInt16]?
    var scbs: [UInt8]?

    public init?(_ url: URL) {

        // Each scanline is 160 bytes. Each byte consists of 2 "pixels".
        // There are 200 scanlines in a 320x200 IIGS graphic
        iigsBitmap = [UInt8](repeating: 0, count: 160*200)
        // First load the entire file
        // Extract the first 160x200 = 32 000 bytes - this is the bitmap
        // Then extract the next 256 bytes - this is the SCB table only 200 required
        // Then extract the last 512 bytes - 16 color tables = 16 x 32 bytes

        var rawData: Data? = nil
        do {
            try rawData = Data(contentsOf: url)
        }
        catch let error {
            print("Error", error)
            return nil
        }

        var range = Range(0..<32000)
        rawData?.copyBytes(to: &iigsBitmap!, from: range)

        scbs = [UInt8](repeating: 0, count: 256)
        range = Range(32000..<32256)
        rawData?.copyBytes(to: &scbs!, from: range)
        
        range = Range(32256..<32768)
        colorTables = [UInt16](repeating:0, count: 256)
        var buffer512 = [UInt8](repeating:0, count: 512)
        rawData?.copyBytes(to: &buffer512, from: range)
        var index = 0
        // On the IIGS, UInt16 is in little-endian format.
        for k in stride(from: 0, to: 512, by: 2) {
            colorTables![index] = UInt16(buffer512[k]) + (UInt16(buffer512[k+1]) << 8)
            // Checked! color table entries are correct.
            //print(colorTables![index], terminator: " ")
            index += 1
            //if index % 16 == 0 {
            //    print()
            //}
        }
    }
}

public class MetalViewRenderer: NSObject, MTKViewDelegate {
    var queue: MTLCommandQueue?
    var device: MTLDevice!
    var rps: MTLRenderPipelineState!
    var cps: MTLComputePipelineState!

    var vertexBuffer: MTLBuffer!
    var indexBuffer: MTLBuffer!

    var bitMapBuffer: MTLBuffer!
    var scbTablesBuffer: MTLBuffer!
    var colorTablesBuffer: MTLBuffer!

    var outputTexture: MTLTexture!

    public init?(device: MTLDevice) {
        super.init()
        self.device = device
        queue = device.makeCommandQueue()
        createBuffers()
        buildPipelineStates()
        guard let texture = createTexture()
        else {
            print("Texture could not be created")
            return nil
        }
        outputTexture = texture
    }

    func createBuffers() {
        let myBundle = Bundle.main
        let assetURL = myBundle.url(forResource: "ANGELFISH",
                                    withExtension:"SHR")
        let graphicsExtractor = ExtractIIgsGraphicData(assetURL!)!

        let bmData = graphicsExtractor.iigsBitmap!
        bitMapBuffer = device!.makeBuffer(bytes: bmData,
                                          length: MemoryLayout<UInt8>.stride * bmData.count,
                                          options: [])
        let colorTables =  graphicsExtractor.colorTables!
        let numberOfColorEntries = colorTables.count
        let sizeOfColorTables = MemoryLayout<UInt16>.stride * numberOfColorEntries
        colorTablesBuffer = device!.makeBuffer(bytes: colorTables,
                                               length: sizeOfColorTables,
                                               options: [])
        let scbTable =  graphicsExtractor.scbs!
        scbTablesBuffer = device!.makeBuffer(bytes: scbTable,
                                             length: MemoryLayout<UInt8>.stride * scbTable.count,
                                             options: [])

        // size = 16 bytes; alignment=8; stride=16
        struct Vertex {
            var position: packed_float2
            var texCoords: packed_float2
        }

        // Note: both the position & texture coordinates are already
        // normalized to the range [-1.0, 1.0] & [0.0, 1.0] respectively.
        // total size = 64 bytes
        let quadVertices: [Vertex] =
            // clockwise - triangle strip; origin of tex coord system is upper-left.
        [
            Vertex(position: [-0.75,  -0.75], texCoords: [ 0.0, 1.0 ]), // v0
            Vertex(position: [-0.75,   0.75], texCoords: [ 0.0, 0.0 ]), // v1
            Vertex(position: [ 0.75,  -0.75], texCoords: [ 1.0, 1.0 ]), // v2
            Vertex(position: [ 0.75,   0.75], texCoords: [ 1.0, 0.0 ]), // v3
        ]
        vertexBuffer = device!.makeBuffer(bytes: quadVertices,
                                          length: MemoryLayout<Vertex>.stride * quadVertices.count,
                                          options: [])

        // total size = 16 bytes.
        let indices: [UInt16] = [0, 1, 2, 2, 1, 3]
        indexBuffer = device!.makeBuffer(bytes: indices,
                                         length: MemoryLayout<UInt16>.stride * indices.count,
                                         options: [])
    }

    func buildPipelineStates() {
        let path = Bundle.main.path(forResource: "Shaders",
                                    ofType: "metal")
        let input: String?
        var library: MTLLibrary?

        do {
            input = try String(contentsOfFile: path!,
                               encoding: String.Encoding.utf8)
            library = try device!.makeLibrary(source: input!,
                                              options: nil)
            let kernel = library!.makeFunction(name: "convert320")!
            cps = try device!.makeComputePipelineState(function: kernel)
        }
        catch let e {
            Swift.print("\(e)")
        }

        let vertex_func = library!.makeFunction(name: "vertexShader")
        let frag_func = library!.makeFunction(name: "fragmentShader")
        // Setup a render pipeline descriptor
        let rpld = MTLRenderPipelineDescriptor()
        rpld.vertexFunction = vertex_func
        rpld.fragmentFunction = frag_func
        // Note: the kernel return each pixel as rgba but the render pipeline
        // insists it's bgra. Weird.
        rpld.colorAttachments[0].pixelFormat = .bgra8Unorm
        do {
            try rps = device!.makeRenderPipelineState(descriptor: rpld)
        }
        catch let error {
            Swift.print("\(error)")
        }
    }


    // Instantiate the output texture object and generate its contents
    // so that the render encoder could use.
    func createTexture() -> MTLTexture? {
        let width = 320
        let height = 200
        let textureDesc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm,
                                                                   width: Int(width),
                                                                   height: Int(height),
                                                                   mipmapped: false)
        // Must be read and write.
        textureDesc.usage = [.shaderWrite, .shaderRead]
        textureDesc.resourceOptions = .storageModeManaged

        let texture = device.makeTexture(descriptor: textureDesc)

        if let commandBuffer = queue?.makeCommandBuffer() {
  
            commandBuffer.addCompletedHandler {
                (commandBuffer: MTLCommandBuffer) -> Void in
                if commandBuffer.status == .error {
                    Swift.print(commandBuffer.error!)
                }
                else if commandBuffer.status == .completed {
                    Swift.print("Texture was generated successfully")
                }
            }
 
            let commandComputeEncoder = commandBuffer.makeComputeCommandEncoder()
            print("Generate Texture")
            commandComputeEncoder.setComputePipelineState(cps)
            commandComputeEncoder.setTexture(texture,
                                             at: 0)
            commandComputeEncoder.setBuffer(bitMapBuffer,
                                            offset: 0,
                                            at: 0)
            commandComputeEncoder.setBuffer(scbTablesBuffer,
                                            offset: 0,
                                            at: 1)
            commandComputeEncoder.setBuffer(colorTablesBuffer,
                                            offset: 0,
                                            at: 2)
            
            let threadGroupCount = MTLSizeMake(8, 8, 1)
            let threadGroups = MTLSizeMake(texture.width / threadGroupCount.width,
                                           texture.height / threadGroupCount.height,
                                           1)
            // Execute the kernel function
            commandComputeEncoder.dispatchThreadgroups(threadGroups,
                                                       threadsPerThreadgroup: threadGroupCount)
            commandComputeEncoder.endEncoding()
            commandBuffer.commit()
        }
        return texture
    }

    // Implementation of the 2 MTKView delegate protocol functions.
    public func mtkView(_ view: MTKView,
                        drawableSizeWillChange size: CGSize) {
    }

    // drawInMTKView:
    public func draw(in view: MTKView) {

        if  let rpd = view.currentRenderPassDescriptor,
            let drawable = view.currentDrawable,
            let commandBuffer = queue?.makeCommandBuffer() {
            view.clearColor = MTLClearColorMake(0.5, 0.5, 0.5, 1.0)

            // Render the generated graphic.
            let commandRenderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: rpd)

            commandRenderEncoder.setRenderPipelineState(rps)

            commandRenderEncoder.setVertexBuffer(vertexBuffer,
                                                 offset: 0,
                                                 at: 0)

            commandRenderEncoder.setFragmentTexture(outputTexture,
                                                    at: 0)

            commandRenderEncoder.drawIndexedPrimitives(type: MTLPrimitiveType.triangleStrip,
                                                       indexCount: indexBuffer.length/MemoryLayout<UInt16>.size,
                                                       indexType: MTLIndexType.uint16,
                                                       indexBuffer: indexBuffer,
                                                       indexBufferOffset: 0)

            commandRenderEncoder.endEncoding()
 
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
