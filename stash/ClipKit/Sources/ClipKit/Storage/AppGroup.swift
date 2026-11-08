import Foundation

public enum AppGroupError: Error, Sendable {
    case containerUnavailable(String)
}

/// Locates the shared storage used by every target. Everything takes a base directory so
/// tests can inject a temporary one.
public struct StorageLocation: Sendable {
    public static let appGroupIdentifier = "group.com.sclera.clipvault"

    public let directory: URL
    public var storeURL: URL { directory.appendingPathComponent("clips.store") }
    public var blobsDirectory: URL { directory.appendingPathComponent("blobs", isDirectory: true) }

    public init(directory: URL) { self.directory = directory }

    public static func appGroup(identifier: String = appGroupIdentifier) throws -> StorageLocation {
        guard let base = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: identifier) else {
            throw AppGroupError.containerUnavailable(identifier)
        }
        return StorageLocation(directory: base.appendingPathComponent("ClipVault", isDirectory: true))
    }

    public func prepare() throws {
        try FileManager.default.createDirectory(at: blobsDirectory, withIntermediateDirectories: true)
    }
}
