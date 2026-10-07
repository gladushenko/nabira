import CryptoKit
import Foundation

enum ContentHasher {
    static func hash(_ representations: [PasteboardRepresentation]) -> String {
        var hasher = SHA256()
        let hasMultipleItems = representations.contains { ($0.itemIndex ?? 0) > 0 }
        for representation in representations.sorted(by: {
            ($0.itemIndex ?? 0, $0.type) < ($1.itemIndex ?? 0, $1.type)
        }) {
            if hasMultipleItems {
                // Frame boundaries so separate pasteboard items cannot hash as one.
                hasher.update(data: Data("\(representation.itemIndex ?? 0):\(representation.type.utf8.count):\(representation.data.count):".utf8))
            }
            hasher.update(data: Data(representation.type.utf8))
            hasher.update(data: representation.data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
