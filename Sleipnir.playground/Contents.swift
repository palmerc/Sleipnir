import Cocoa
import MetalKit
import PlaygroundSupport

/*:

 # Sleipnir - A faster horse
 
 This playground demonstrates a fake compute shader generating a texture and outputting directly to the MTKView.
 
 Sleipnir is the name of Odin's horse and is depicted as having eight legs. Metal is rendering the still frames fast enough to provide a persistence effect that makes this partiuclar horse look as if it might just have eight legs too. Hence, the name.

 */
let shaderURL = Bundle.main.url(forResource: "Shader", withExtension: "metal")
let device = MTLCreateSystemDefaultDevice()
let frame = NSRect(x:0, y:0, width:256, height:256)
let mtkView = MTKView(frame: frame, device: device)

let horseMovie = HorseMovie()
let renderer = MetalRenderer(view: mtkView, shaderURL: shaderURL)
renderer.movie = horseMovie
mtkView.delegate = renderer

PlaygroundPage.current.liveView = mtkView


