import AppKit
import MetalKit
import PlaygroundSupport

/*
 Originally developed using XCode 9.x
 Modified to compile and run under  XCode 8.x, macOS 10.12
  */
let frame = NSRect(x: 0, y: 0,
                   width: 640, height: 400)
let device = MTLCreateSystemDefaultDevice()

let renderer = MetalViewRenderer(device: device!)
let view = MTKView(frame: frame, device: device!)
view.delegate = renderer
PlaygroundPage.current.liveView = view


