import CryptoKit
import Foundation

enum ContentHasher {
    static func hash(_ representations: [PasteboardRepresentation]) -> String {
        var hasher = SHA256()
        for representation in representations.sorted(by: { $0.type < $1.type }) {
            hasher.update(data: Data(representation.type.utf8))
            hasher.update(data: representation.data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
