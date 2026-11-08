import Foundation
@testable import ClipKit

func makeTempLocation() throws -> StorageLocation {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("ClipKitTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return StorageLocation(directory: dir)
}
