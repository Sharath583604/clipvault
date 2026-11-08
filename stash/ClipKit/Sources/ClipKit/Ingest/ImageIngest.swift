import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Image helpers that stay within ImageIO so memory use is bounded (share extensions are
/// killed at roughly 120 MB). Never used by the keyboard.
public enum ImageIngest {
    public struct Result: Sendable {
        public let jpegData: Data
        public let width: Int
        public let height: Int
    }

    /// Downsamples to `maxPixel` on the long edge and re-encodes as JPEG.
    public static func normalize(_ data: Data, maxPixel: Int = 2048) -> Result? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = thumbnail(from: source, maxPixel: maxPixel) else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return Result(jpegData: out as Data, width: image.width, height: image.height)
    }

    /// Small decoded image for list rows in the main app.
    public static func thumbnail(at url: URL, maxPixel: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(from: source, maxPixel: maxPixel)
    }

    private static func thumbnail(from source: CGImageSource, maxPixel: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
