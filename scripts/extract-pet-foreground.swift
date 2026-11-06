import AppKit
import Vision

// Background removal only: the generated character pixels are never redrawn.
let args = CommandLine.arguments
if args.count != 3 { fatalError("用法：extract-pet-foreground 源图 输出目录") }
let source = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let image = NSImage(contentsOf: source)!
let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
for row in 0..<4 {
    for col in 0..<6 {
        let slot = cg.cropping(to: CGRect(x: col * cg.width / 6, y: row * cg.height / 4,
                                          width: cg.width / 6, height: cg.height / 4))!
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: slot)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            fatalError("无法识别宠物轮廓：\(row)-\(col)")
        }
        let buffer = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                    from: handler, croppedToInstancesExtent: false)
        let ci = CIImage(cvPixelBuffer: buffer)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let cutout = context.createCGImage(ci, from: ci.extent) else { fatalError("无法导出轮廓") }
        let png = NSBitmapImageRep(cgImage: cutout).representation(using: .png, properties: [:])!
        try png.write(to: output.appendingPathComponent("\(row)-\(col).png"))
    }
}
print("已提取24个宠物姿态：\(output.path)")
