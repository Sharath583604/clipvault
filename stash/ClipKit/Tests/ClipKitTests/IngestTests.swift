import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipKit

func makePNG(width: Int, height: Int) throws -> Data {
    let ctx = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
    ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(ctx.makeImage())
    let out = NSMutableData()
    let dest = try #require(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
    CGImageDestinationAddImage(dest, image, nil)
    #expect(CGImageDestinationFinalize(dest))
    return out as Data
}

@Suite struct IngestTests {
    @Test func imageIsDownsampledAndStored() async throws {
        let loc = try makeTempLocation()
        let s = try ClipStore.open(location: loc)
        let v = try #require(try await s.ingest(.image(makePNG(width: 4000, height: 1000)), method: .share))
        #expect(v.kind == .image)
        let url = try #require(s.blobURL(for: v))
        #expect(FileManager.default.fileExists(atPath: url.path))
        let thumb = try #require(ImageIngest.thumbnail(at: url, maxPixel: 4096))
        #expect(max(thumb.width, thumb.height) == 2048)
        #expect(v.preview.contains("2048"))
    }

    @Test func sameImageDedupes() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        let png = try makePNG(width: 64, height: 64)
        let a = try #require(try await s.ingest(.image(png), method: .share))
        let b = try #require(try await s.ingest(.image(png), method: .pasteButton))
        #expect(a.id == b.id)
    }

    @Test func undecodableImageIsRejected() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        #expect(try await s.ingest(.image(Data([0, 1, 2])), method: .share) == nil)
        #expect(try await s.recent(limit: 5).isEmpty)
    }

    @Test func blankTextIsRejectedAndUrlStored() async throws {
        let s = try ClipStore.open(location: makeTempLocation())
        #expect(try await s.ingest(.text("  \n "), method: .pasteButton) == nil)
        let v = try #require(try await s.ingest(.url(URL(string: "https://example.com")!), method: .share))
        #expect(v.kind == .url)
    }

    @Test func deleteAllRemovesEverything() async throws {
        let loc = try makeTempLocation()
        let s = try ClipStore.open(location: loc)
        let v = try #require(try await s.ingest(.image(makePNG(width: 32, height: 32)), method: .share))
        let url = try #require(s.blobURL(for: v))
        try await s.ingest(.text("hello"), method: .share)
        try await s.deleteAll()
        #expect(try await s.recent(limit: 10).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test func settingsDefaultsAndPersistence() {
        let suite = "ClipKitTests-\(UUID().uuidString)"
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = ClipSettings(suiteName: suite)
        #expect(settings.retentionDays == 30)
        settings.retentionDays = 0
        #expect(settings.policy.retentionDays == 0)
    }
}
