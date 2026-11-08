import Foundation
import Testing
import UniformTypeIdentifiers
@testable import ClipKit

/// Synthetic share-sheet / paste items, to check what ProviderIngest can actually read.
@MainActor
@Suite struct ProviderIngestTests {
    @Test func webURL() async throws {
        let provider = NSItemProvider(object: URL(string: "https://example.com/page")! as NSURL)
        let result = await ProviderIngest.payloads(from: [provider])
        #expect(result == [.url(URL(string: "https://example.com/page")!)])
    }

    @Test func plainText() async throws {
        let provider = NSItemProvider(object: "hello world" as NSString)
        let result = await ProviderIngest.payloads(from: [provider])
        #expect(result == [.text("hello world")])
    }

    @Test func textRegisteredAsPlainTextType() async throws {
        let provider = NSItemProvider(item: "from a notes app" as NSString,
                                      typeIdentifier: UTType.plainText.identifier)
        let result = await ProviderIngest.payloads(from: [provider])
        #expect(result == [.text("from a notes app")])
    }

    @Test func textRegisteredAsRawUTF8Data() async throws {
        let provider = NSItemProvider(item: Data("raw bytes".utf8) as NSData,
                                      typeIdentifier: UTType.utf8PlainText.identifier)
        #expect(await ProviderIngest.payloads(from: [provider]) == [.text("raw bytes")])
    }

    @Test func imageRegisteredAsJPEG() async throws {
        let png = try makePNG(width: 12, height: 12)
        let provider = NSItemProvider(item: png as NSData, typeIdentifier: UTType.jpeg.identifier)
        guard case .image? = await ProviderIngest.payloads(from: [provider]).first else {
            Issue.record("jpeg-registered image was not read")
            return
        }
    }

    @Test func imageRegisteredAsConcreteType() async throws {
        // Photos and most apps register a concrete type (public.png / public.jpeg), not public.image.
        let png = try makePNG(width: 20, height: 20)
        let provider = NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)
        let result = await ProviderIngest.payloads(from: [provider])
        guard case .image(let data)? = result.first else {
            Issue.record("expected an image payload, got \(result)")
            return
        }
        #expect(!data.isEmpty)
    }

    @Test func safariStyleItemWithURLAndText() async throws {
        let provider = NSItemProvider()
        provider.registerObject(URL(string: "https://example.com")! as NSURL, visibility: .all)
        provider.registerObject("Example Domain" as NSString, visibility: .all)
        let result = await ProviderIngest.payloads(from: [provider])
        #expect(result == [.url(URL(string: "https://example.com")!)])
    }

    @Test func extensionItemWithOnlyAttributedText() async throws {
        // Some apps put the shared text on the item itself and attach nothing.
        let item = NSExtensionItem()
        item.attributedContentText = NSAttributedString(string: "text on the item")
        let result = await ProviderIngest.payloads(from: [item])
        #expect(result == [.text("text on the item")])
    }

    @Test func extensionItemWithAttachment() async throws {
        let item = NSExtensionItem()
        item.attachments = [NSItemProvider(object: "attached" as NSString)]
        #expect(await ProviderIngest.payloads(from: [item]) == [.text("attached")])
    }

    @Test func nothingUsableGivesEmpty() async throws {
        #expect(await ProviderIngest.payloads(from: [NSExtensionItem()]).isEmpty)
        #expect(await ProviderIngest.payloads(from: [NSItemProvider()]).isEmpty)
    }
}
