import AppKit
import CoreGraphics

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func icon(size: Int) -> Data {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: size * 4, space: colorSpace,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let scale = CGFloat(size) / 64
    ctx.scaleBy(x: scale, y: scale)
    ctx.translateBy(x: 0, y: 64)
    ctx.scaleBy(x: 1, y: -1)

    func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: UInt32) {
        ctx.setFillColor(color(fill)); ctx.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    let border = CGPath(roundedRect: CGRect(x: 5, y: 4, width: 54, height: 54),
                        cornerWidth: 12, cornerHeight: 12, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 2 * scale), blur: 3 * scale,
                  color: color(0x07130B, alpha: 0.42))
    ctx.setFillColor(color(0x263D2A)); ctx.addPath(border); ctx.fillPath()
    ctx.restoreGState()
    ctx.addPath(border); ctx.clip()
    let gradient = CGGradient(colorsSpace: colorSpace,
                              colors: [color(0x456950), color(0x182D22)] as CFArray,
                              locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 10, y: 2),
                           end: CGPoint(x: 51, y: 62), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.addPath(border); ctx.setStrokeColor(color(0xABC49A, alpha: 0.3))
    ctx.setLineWidth(0.8); ctx.strokePath()

    // The centered terminal and walnut desk are readable even in Finder's smallest icon view.
    rect(19, 38, 27, 4, 0x172C21)
    rect(17, 13, 30, 21, 0x172C21)
    rect(18, 12, 28, 20, 0xD4DFAD)
    rect(20, 14, 24, 15, 0x203B2E)
    rect(21, 15, 22, 1, 0x547A59)
    rect(23, 18, 2, 2, 0xD6F3A8)
    rect(25, 20, 2, 2, 0xD6F3A8)
    rect(23, 22, 2, 2, 0xD6F3A8)
    rect(29, 23, 8, 1.5, 0xD6F3A8)
    rect(30, 32, 4, 3, 0x9EAE88)
    rect(27, 35, 10, 1, 0xD1DBAB)

    rect(13, 38, 38, 5, 0x61422F)
    rect(13, 36, 38, 4, 0xB88154)
    rect(13, 36, 38, 1, 0xD8A477)
    rect(15, 43, 3, 5, 0x624833)
    rect(46, 43, 3, 5, 0x624833)
    rect(43, 33, 4, 3, 0xE6DAAE)
    rect(47, 34, 1, 1, 0xD7C79D)

    // The small seated agent echoes the sprites in the 2D office.
    rect(28, 39, 8, 7, 0x392A23)
    rect(29, 42, 6, 4, 0xD6A475)
    rect(27, 46, 10, 6, 0x90B778)
    rect(25, 48, 2, 3, 0xD6A475)
    rect(37, 48, 2, 3, 0xD6A475)
    rect(28, 52, 8, 2, 0x274234)

    let image = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return image.representation(using: .png, properties: [:])!
}

let sizes = [16, 32, 128, 256, 512]
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in sizes {
    try icon(size: size).write(to: output.appendingPathComponent("icon_\(size)x\(size).png"))
    try icon(size: size * 2).write(to: output.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
