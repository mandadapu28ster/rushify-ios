// Renders the Rushify app icon (cream tile, green/red/green pulse line, blue arrowhead) to a 1024x1024 PNG.
// Usage: swift scripts/make_icon.swift Rushify/Assets.xcassets/AppIcon.appiconset/icon-1024.png
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024, s = CGFloat(size) / 108
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.translateBy(x: 0, y: CGFloat(size)); ctx.scaleBy(x: 1, y: -1)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * s, y: y * s) }
func stroke(_ pts: [CGPoint], _ color: CGColor, _ width: CGFloat) {
    ctx.setStrokeColor(color); ctx.setLineWidth(width * s); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.beginPath(); ctx.move(to: pts[0]); pts.dropFirst().forEach { ctx.addLine(to: $0) }; ctx.strokePath()
}

ctx.setFillColor(rgb(0xFB, 0xF3, 0xE0)); ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.setFillColor(rgb(47, 111, 228, 0.10))
ctx.beginPath(); ctx.move(to: pt(24, 72)); [pt(42, 48), pt(58, 68), pt(77, 39), pt(77, 86), pt(24, 86)].forEach { ctx.addLine(to: $0) }; ctx.closePath(); ctx.fillPath()
stroke([pt(22, 86), pt(86, 86)], rgb(0xB9, 0xAE, 0x95, 0.7), 1.5)
let green = rgb(22, 163, 74), red = rgb(229, 72, 77), blue = rgb(47, 111, 228)
stroke([pt(24, 72), pt(42, 48)], green, 9)
stroke([pt(42, 48), pt(58, 68)], red, 9)
stroke([pt(58, 68), pt(77, 39)], green, 9)
stroke([pt(82.2, 44.8), pt(80, 34), pt(69.2, 36.2)], blue, 8)

let url = URL(fileURLWithPath: out) as CFURL
let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(dest), "could not write PNG")
print("wrote \(out)")
