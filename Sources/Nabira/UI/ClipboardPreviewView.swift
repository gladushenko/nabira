import AppKit
import SwiftUI

struct ClipboardPreviewView: View {
    let item: ClipboardItem

    var body: some View {
        Group {
            if item.contentType == .image, let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Clipboard image preview")
            } else {
                ScrollView {
                    Text(textContent)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 320)
    }

    private var image: NSImage? {
        item.representations.lazy.compactMap { NSImage(data: $0.data) }.first
    }

    private var textContent: String {
        if item.contentType == .files {
            return item.searchableText
        }
        return item.plainText ?? item.searchableText
    }
}
