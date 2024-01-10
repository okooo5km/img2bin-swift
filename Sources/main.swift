import AppKit
import ArgumentParser
import Foundation
import UniformTypeIdentifiers
// The Swift Programming Language
// https://docs.swift.org/swift-book
import os

extension URL {
    var isImageFile: Bool {
        isFile(ofTypes: [.png, .jpeg, .heic])
    }

    var uti: UTType? {
        hasDirectoryPath ? nil : UTType(filenameExtension: pathExtension)
    }

    func isFile(ofTypes types: [UTType]) -> Bool {
        guard let uti = self.uti else {
            return false
        }

        return types.contains(where: { uti.conforms(to: $0) })
    }

    var imageRepType: NSBitmapImageRep.FileType? {
        if !isImageFile {
            return nil
        }
        switch uti {
        case UTType.png:
            return .png
        case UTType.jpeg, UTType.heic:
            return .jpeg
        default:
            return nil
        }
    }

    func changingPathExtension(to newExtension: String) -> URL {
        return self.deletingPathExtension().appendingPathExtension(newExtension)
    }
}

extension NSImage {
    func save(to url: URL) {
        guard let type = url.imageRepType else {
            print("Saving Image to \(url), the url is not a valid image file url!")
            return
        }

        guard let data = self.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data),
            let bitmapData = bitmap.representation(using: type, properties: [:])
        else {
            print("Saving Image to \(url), bitmap data generation failed!")
            return
        }

        do {
            try bitmapData.write(to: url)
        } catch {
            print("Saved Image to \(url) with error: \(error)")
        }
    }

}

struct Img2bin: ParsableCommand {
    @Option(name: [.customShort("t"), .long], help: "二值阈值")
    var threshold: Int = 128

    @Argument(help: "输入文件或目录路径")
    var inputs: [String]

    func run() throws {
        let fileManager = FileManager.default
        let currentDirectoryURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let outputDirectoryURL = currentDirectoryURL.appendingPathComponent("output")

        // 创建输出目录，如果它不存在
        try fileManager.createDirectory(at: outputDirectoryURL, withIntermediateDirectories: true)

        for input in inputs {
            let inputURL = URL(fileURLWithPath: input)
            if fileManager.fileExists(atPath: inputURL.path, isDirectory: nil) {
                if inputURL.hasDirectoryPath {
                    // 遍历目录及子目录
                    let enumerator = fileManager.enumerator(at: inputURL, includingPropertiesForKeys: nil)!
                    for case let fileURL as URL in enumerator {
                        try processImage(fileURL: fileURL, outputDirectoryURL: outputDirectoryURL)
                    }
                } else {
                    // 处理单个文件
                    try processImage(fileURL: inputURL, outputDirectoryURL: outputDirectoryURL)
                }
            }
        }
    }

    private func processImage(fileURL: URL, outputDirectoryURL: URL) throws {

        if !fileURL.isImageFile {
            print("跳过非图像文件：\(fileURL.path), 格式不支持！")
            return
        }

        guard let image = NSImage(contentsOf: fileURL),
            let tiffData = image.tiffRepresentation,
            let bitmapImageRep = NSBitmapImageRep(data: tiffData),
            let cgImage = bitmapImageRep.cgImage
        else {
            print("无法读取图像：\(fileURL.path)")
            return
        }

        let width = Int(bitmapImageRep.size.width)
        let height = Int(bitmapImageRep.size.height)

        let colorSpace = CGColorSpaceCreateDeviceGray()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)

        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: colorSpace, bitmapInfo: bitmapInfo.rawValue)
        else {
            print("无法创建图像上下文")
            return
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

        if let imageData = context.data {
            let pointer = imageData.bindMemory(to: UInt8.self, capacity: width * height)
            for i in 0..<width * height {
                pointer[i] = pointer[i] > UInt8(threshold) ? 255 : 0
            }
        }

        if let outputCGImage = context.makeImage() {
            let outputImage = NSImage(cgImage: outputCGImage, size: NSZeroSize)
            let outputFileName = fileURL.deletingPathExtension().lastPathComponent + "-bin.png"
            let outputURL = outputDirectoryURL.appendingPathComponent(outputFileName)
            outputImage.save(to: outputURL)
            print("图像已保存至：\(outputURL.path)")
        }
    }
}

Img2bin.main()
