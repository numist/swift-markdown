/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

// Every document's materialized string buffer starts with one shared newline, so each expected size is one more than
// the bytes the parse stores.
@Suite("Extended email autolinks store only their destination")
struct EmailAutolinkArenaStorageTests {

    private static let longText = String(repeating: "x ", count: 500_000)

    @Test("an address after a megabyte of text stores only its destination", arguments: [
        MarkdownDocument.ParseOptions.gfmAutolink,
        [.gfmAutolink, .inlineOnly],
    ])
    func longTextBeforeAddress(options: MarkdownDocument.ParseOptions) {
        let (size, url) = MarkdownDocument.withParsedDocument(Self.longText + "a@b.c", options: options) { document in
            (document._materializedStringSize, Self.firstLinkDestination(document.root))
        }
        #expect(url == "mailto:a@b.c")
        #expect(size == 13)
    }

    @Test("an address in text with a character reference stores its destination beside the decoded character")
    func addressAfterCharacterReference() {
        let (size, url) = MarkdownDocument.withParsedDocument("x &amp; a@b.c", options: .gfmAutolink) { document in
            (document._materializedStringSize, Self.firstLinkDestination(document.root))
        }
        #expect(url == "mailto:a@b.c")
        #expect(size == 14)
    }

    private static func firstLinkDestination(_ node: borrowing MarkdownNode) -> String? {
        if case .link(let destination, _) = node.stringContent {
            return destination
        }
        var found: String?
        node.children.forEach { child in
            if found == nil {
                found = firstLinkDestination(child)
            }
        }
        return found
    }
}
