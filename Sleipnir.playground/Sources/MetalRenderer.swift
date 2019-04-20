import Foundation
import MetalKit

private let kInflightCommandBuffers = 3
private let kTextureCount = 3
private let kImageBufferCount = 1



public class MetalRenderer: NSObject, MTKViewDelegate {
    fileprivate var metalDevice: MTLDevice?
    fileprivate var metalLibrary: MTLLibrary?

    public var movie: Movie?
    fileprivate var currentImageContainer: ImageContainer?

    fileprivate var metalView: MTKView?
    fileprivate var metalCommandQueue: MTLCommandQueue?

    fileprivate var computePipelineState: MTLComputePipelineState?
    fileprivate var renderPipelineState: MTLRenderPipelineState?
    fileprivate var samplerState: MTLSamplerState?

    fileprivate var imageBuffers: [MTLBuffer]?
    fileprivate var vertexBuffer: MTLBuffer?
    fileprivate var textureQueue: [MTLTexture]?
    fileprivate var currentTexture: MTLTexture?

//    fileprivate var computeFrameCycle: Int = 0
    fileprivate var inflightSemaphore: DispatchSemaphore?

    public init(view: MTKView, shaderURL: URL?)
    {
        self.metalView = view
        self.metalDevice = view.device

        if let shaderURL = shaderURL {
            do {
                let shaderCode = try String(contentsOf: shaderURL, encoding: .utf8)
                self.metalLibrary = try self.metalDevice?.makeLibrary(source: shaderCode, options: nil)
            } catch {
                print("Failed to create Metal library. \(error.localizedDescription)")
            }
        }

        super.init()

        self.metalCommandQueue = self.metalDevice?.makeCommandQueue()
        self.imageBuffers = [MTLBuffer]()
        self.inflightSemaphore = DispatchSemaphore(value: kInflightCommandBuffers)

        self.textureQueue = [MTLTexture]()

        buildRenderResources()
        buildRenderPipeline()
        buildComputeResources()
        buildComputePipelines()
    }

    fileprivate func buildRenderResources()
    {
        // Vertex data for a full-screen quad. The first two numbers in each row represent
        // the x, y position of the point in normalized coordinates. The second two numbers
        // represent the texture coordinates for the corresponding position.
        let vertexData = [Float](arrayLiteral:
            -1,  1, 0, 0,
            -1, -1, 0, 1,
             1, -1, 1, 1,
             1, -1, 1, 1,
             1,  1, 1, 0,
            -1,  1, 0, 0)

        // Create a buffer to hold the static vertex data

        let options = MTLResourceOptions().union(.storageModeShared)
        let byteCount = vertexData.count * MemoryLayout<Float>.size
        let vertexBuffer = self.metalDevice?.makeBuffer(bytes: vertexData, length: byteCount, options: options)
        vertexBuffer?.label = "Image Quad Vertices"
        self.vertexBuffer = vertexBuffer
    }

    fileprivate func buildRenderPipeline()
    {
        if let metalLibrary = self.metalLibrary {
            let vertexProgram: MTLFunction? = metalLibrary.makeFunction(name: "simple_vertex")
            let fragmentProgram: MTLFunction? = metalLibrary.makeFunction(name: "simple_fragment")
            // Create a vertex descriptor that describes a vertex with two float2 members:
            // position and texture coordinates
            let vertexDescriptor: MTLVertexDescriptor = MTLVertexDescriptor()
            vertexDescriptor.attributes[0].offset = 0
            vertexDescriptor.attributes[0].bufferIndex = 0
            vertexDescriptor.attributes[0].format = .float2
            vertexDescriptor.attributes[1].offset = MemoryLayout<float2>.size * 2
            vertexDescriptor.attributes[1].bufferIndex = 0
            vertexDescriptor.attributes[1].format = .float2
            vertexDescriptor.layouts[0].stride = MemoryLayout<float2>.size * 4
            vertexDescriptor.layouts[0].stepRate = 1
            vertexDescriptor.layouts[0].stepFunction = .perVertex

            // Describe and create a render pipeline state
            let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
            pipelineStateDescriptor.label = "Image Quad Pipeline"
            pipelineStateDescriptor.vertexFunction = vertexProgram
            pipelineStateDescriptor.fragmentFunction = fragmentProgram
            pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
            if let pixelFormat = self.metalView?.colorPixelFormat {
                pipelineStateDescriptor.colorAttachments[0].pixelFormat = pixelFormat
            }

            var renderPipelineState: MTLRenderPipelineState?
            do {
                renderPipelineState = try self.metalDevice?.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
            } catch {
                print("Failed to create render pipeline state. \(error.localizedDescription)")
            }
            self.renderPipelineState = renderPipelineState

            let samplerDescriptor = MTLSamplerDescriptor()
            samplerDescriptor.normalizedCoordinates = true
            samplerDescriptor.minFilter = .linear
            samplerDescriptor.magFilter = .linear
            samplerDescriptor.sAddressMode = .clampToZero
            samplerDescriptor.rAddressMode = .clampToZero
            self.samplerState = self.metalDevice?.makeSamplerState(descriptor: samplerDescriptor)
        } else {
            print("No metal library available")
        }
    }

    fileprivate func buildComputePipelines()
    {
        if let metalLibrary = self.metalLibrary {
            let (_, computePipelineState) = MetalHelper.setupComputePipeline(kernelFunctionName: "doNothingComputeShader", metalDevice: self.metalDevice, metalLibrary: metalLibrary)
            self.computePipelineState = computePipelineState
        }
    }

    fileprivate func buildComputeResources()
    {
        for index in 0 ..< kImageBufferCount {
            var pixelCount = 0
            if let drawableSize = self.metalView?.drawableSize {
                pixelCount = Int(drawableSize.width) * Int(drawableSize.height)
            }

            let byteCount = pixelCount * MemoryLayout<UInt8>.size
            if let imageBuffer = self.metalDevice?.makeBuffer(length: byteCount, options: []) {
                imageBuffer.label = "Image Buffer \(index)"
                imageBuffers?.append(imageBuffer)
            }
        }

        for index in 0 ..< kTextureCount {
            let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Uint, width: 360, height: 230, mipmapped: false)
            textureDescriptor.usage = MTLTextureUsage.shaderWrite.union(.shaderRead)
            if let texture = self.metalDevice?.makeTexture(descriptor: textureDescriptor) {
                texture.label = "Output Texture \(index)"
                self.textureQueue?.append(texture)
            }
        }
    }

    fileprivate func encodeComputeWork(in commandBuffer: MTLCommandBuffer)
    {
        if let imageBuffers = imageBuffers,
            let imageContainer = self.currentImageContainer {
            let imageBuffer = imageBuffers[0]
            let imageBufferPointer = imageBuffer.contents()

            let pixelCount = imageContainer.pixelValues.count
            let byteCount = pixelCount * MemoryLayout<UInt8>.size
            imageContainer.pixelValues.withUnsafeBytes({
                (bytes: UnsafeRawBufferPointer) -> () in
                memcpy(imageBufferPointer, bytes.baseAddress, byteCount)
            })

            let commandEncoder = commandBuffer.makeComputeCommandEncoder()
            commandEncoder?.pushDebugGroup("Compute Processing")

            if let pipelineState = self.computePipelineState,
                let writeTexture = self.textureQueue?.first {
//                print("Computing")
                commandEncoder?.setComputePipelineState(pipelineState)

                commandEncoder?.setTexture(writeTexture, index: 0)
                commandEncoder?.setBuffer(imageBuffer, offset: 0, index: 0)

                let maxTotalThreadsPerThreadgroup = Float(pipelineState.maxTotalThreadsPerThreadgroup)
                var executionWidth = Int(pow(2.0, floor(log2(maxTotalThreadsPerThreadgroup))))
                let largestPowerOf2 = pixelCount & (~pixelCount + 1)
                if executionWidth > largestPowerOf2 {
                    executionWidth = largestPowerOf2
                }
                let threadsPerThreadgroup = MTLSize(width: executionWidth, height: 1, depth: 1)
                let threadGroups = MTLSize(width: pixelCount / threadsPerThreadgroup.width, height: 1, depth:1)

                commandEncoder?.dispatchThreadgroups(threadGroups, threadsPerThreadgroup: threadsPerThreadgroup)
            }
            commandEncoder?.popDebugGroup()
            commandEncoder?.endEncoding()

        }

        if let texture = self.textureQueue?.first {
            self.currentTexture = texture
            self.textureQueue?.removeFirst()
            self.textureQueue?.append(texture)
        }
    }

    fileprivate func encodeRenderWork(in buffer: MTLCommandBuffer)
    {
        if let renderPipelineState = self.renderPipelineState,
            let renderPassDescriptor = self.metalView?.currentRenderPassDescriptor,
            let currentDrawable = self.metalView?.currentDrawable {
            // Create a render command encoder, which we can use to encode draw calls into the buffer
//            print("Rendering")
            let renderEncoder = buffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

            // Configure the render encoder for drawing the full-screen quad, then issue the draw call
            renderEncoder?.setRenderPipelineState(renderPipelineState)
            renderEncoder?.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            renderEncoder?.setFragmentTexture(self.currentTexture, index: 0)
            renderEncoder?.setFragmentSamplerState(self.samplerState, index: 0)
            renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

            renderEncoder?.endEncoding()

            // Present the texture we just rendered on the screen
            buffer.present(currentDrawable)
        }
    }

    // MARK: MTKViewDelegate

    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)
    {

    }

    public func draw(in view: MTKView)
    {
        _ = self.inflightSemaphore?.wait(timeout: .distantFuture);
        let commandBuffer = self.metalCommandQueue?.makeCommandBuffer()
        commandBuffer?.addCompletedHandler({
            (buffer: MTLCommandBuffer) in
            self.inflightSemaphore?.signal()
        })

        if let currentImageContainer = self.movie?.nextFrame() {
            self.currentImageContainer = currentImageContainer

            if let commandBuffer = commandBuffer {
                self.encodeComputeWork(in: commandBuffer)
                self.encodeRenderWork(in: commandBuffer)
                commandBuffer.commit()
            }
        }
    }
}
