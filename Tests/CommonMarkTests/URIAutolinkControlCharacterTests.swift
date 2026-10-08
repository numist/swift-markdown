/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Depth-first: the destination URL of the first `.link` node, or nil if the tree has none.
private func firstLinkURL(_ node: borrowing MarkdownNode) -> String?? {
    if case .link = node.kind, case .link(let url, _) = node.stringContent {
        return .some(url)
    }
    var found: String?? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstLinkURL(child)
        }
    }
    return found
}

/// Depth-first: all `.text` literal content concatenated.
private func collectText(_ node: borrowing MarkdownNode) -> String {
    var result = ""
    if case .text = node.kind, case .text(let s) = node.stringContent {
        result += s
    }
    node.children.forEach { child in
        result += collectText(child)
    }
    return result
}

/// An absolute URI excludes ASCII control characters (Autolinks), including DEL (U+007F), so a `<…>` containing
/// one is literal text.
@Suite("URI autolink control characters")
struct URIAutolinkControlCharacterTests {

    private static let options: MarkdownDocument.ParseOptions = []

    private func linkURL(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> String? {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstLinkURL(doc.root) ?? nil
        }
    }

    private func text(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> String {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> String in
            collectText(doc.root)
        }
    }

    @Test("`<tp:\\u{7F}>` is literal text")
    func delNotLink() {
        #expect(linkURL("<tp:\u{7F}>", options: Self.options) == nil)
        #expect(text("<tp:\u{7F}>", options: Self.options) == "<tp:\u{7F}>")
    }

    @Test("`<http://a\\u{7F}>` is literal text")
    func delInHttpNotLink() {
        #expect(linkURL("<http://a\u{7F}>", options: Self.options) == nil)
        #expect(text("<http://a\u{7F}>", options: Self.options) == "<http://a\u{7F}>")
    }

    @Test("`<tp:a\\u{7F}b>` is literal text")
    func delMidBodyNotLink() {
        #expect(linkURL("<tp:a\u{7F}b>", options: Self.options) == nil)
        #expect(text("<tp:a\u{7F}b>", options: Self.options) == "<tp:a\u{7F}b>")
    }

    @Test("`<tp:x>` is a link")
    func plainURILinks() {
        #expect(linkURL("<tp:x>", options: Self.options) == "tp:x")
    }

    @Test("`<tp:\\u{1F}>` is not a link")
    func c0ControlNotLink() {
        #expect(linkURL("<tp:\u{1F}>", options: Self.options) == nil)
    }

    @Test("`<tp:\\u{0B}>` is not a link")
    func vtControlNotLink() {
        #expect(linkURL("<tp:\u{0B}>", options: Self.options) == nil)
    }
}
