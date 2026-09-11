// Renders the app icon: the dial's red disk on the paper-coloured face.
//   swift make-icon.swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024.0
let space = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: space,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no context")
}

func colour(_ r: Double, _ g: Double, _ b: Double) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, 1])!
}

let paper = colour(0.984, 0.969, 0.941)
let rim = colour(0.886, 0.863, 0.820)
let red = colour(0.886, 0.227, 0.149)

ctx.setFillColor(paper)
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))

let centre = CGPoint(x: size / 2, y: size / 2)

// the bezel
ctx.setStrokeColor(rim)
ctx.setLineWidth(size * 0.042)
ctx.addArc(center: centre, radius: size * 0.375, startAngle: 0, endAngle: .pi * 2, clockwise: false)
ctx.strokePath()

// three quarters left, the state the dial spends most of its time in
let radius = size * 0.315
ctx.setFillColor(red)
ctx.move(to: centre)
ctx.addArc(center: centre, radius: radius,
           startAngle: .pi / 2, endAngle: 0, clockwise: true)
ctx.closePath()
ctx.fillPath()
ctx.move(to: centre)
ctx.addArc(center: centre, radius: radius,
           startAngle: 0, endAngle: -.pi, clockwise: true)
ctx.closePath()
ctx.fillPath()

guard let image = ctx.makeImage() else { fatalError("no image") }
let url = URL(fileURLWithPath: "Assets.xcassets/AppIcon.appiconset/icon-1024.png")
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no destination")
}
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
print("wrote \(url.path)")
