import CryptoKit
import Foundation

public enum ContentHash {
    public static func hash(text: String) -> String {
        hash(data: Data(text.utf8))
    }

    public static func hash(data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
