import AppKit

// 用组件实拍图（透明底 iPod）合成 App 图标：
//   1024×1024 圆角浅灰渐变底 + 设备等比居中（带投影）
// 用法: make-icon <设备透明底PNG> <输出1024PNG>

let args = CommandLine.arguments
guard args.count >= 3, let src = NSImage(contentsOfFile: args[1]),
      let cgSrc = src.cgImage(forProposedRect: nil, context: nil, hints: nil)
else {
    FileHandle.standardError.write(Data("usage: make-icon <device.png> <out.png>\n".utf8))
    exit(1)
}

// 1. 扫 alpha 包围盒，裁掉透明边
let W = cgSrc.width, H = cgSrc.height
let scanCtx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W * 4,
                        space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
scanCtx.draw(cgSrc, in: CGRect(x: 0, y: 0, width: W, height: H))
let scan = scanCtx.data!.assumingMemoryBound(to: UInt8.self)
var minX = W, minY = H, maxX = -1, maxY = -1
for row in 0..<H {
    for col in 0..<W {
        if scan[(row * W + col) * 4 + 3] > 24 {
            if col < minX { minX = col }
            if col > maxX { maxX = col }
            if row < minY { minY = row }
            if row > maxY { maxY = row }
        }
    }
}
guard maxX > minX, maxY > minY else {
    FileHandle.standardError.write(Data("image looks empty\n".utf8))
    exit(1)
}
let cropped = cgSrc.cropping(to: CGRect(x: minX, y: minY,
                                        width: maxX - minX + 1, height: maxY - minY + 1))!

// 2. 合成 1024 画布
let S = 1024
let ctx = CGContext(data: nil, width: S, height: S, bitsPerComponent: 8, bytesPerRow: S * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

// 圆角浅灰渐变底（macOS squircle 风格的近似）
let path = CGPath(roundedRect: CGRect(x: 0, y: 0, width: S, height: S),
                  cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(path)
ctx.clip()
let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                      colors: [CGColor(red: 0.972, green: 0.972, blue: 0.976, alpha: 1),
                               CGColor(red: 0.862, green: 0.862, blue: 0.882, alpha: 1)] as CFArray,
                      locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(S)),
                       end: CGPoint(x: 0, y: 0), options: [])

// 设备等比放到高 856 居中，带柔和投影
let devH: CGFloat = 856
let devW = devH * CGFloat(cropped.width) / CGFloat(cropped.height)
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30,
              color: CGColor(red: 0.1, green: 0.12, blue: 0.2, alpha: 0.38))
ctx.draw(cropped, in: CGRect(x: (CGFloat(S) - devW) / 2, y: (CGFloat(S) - devH) / 2,
                             width: devW, height: devH))

// 3. 写 PNG
let out = NSBitmapImageRep(cgImage: ctx.makeImage()!)
guard let png = out.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: args[2]))
print("icon written: \(args[2])")
