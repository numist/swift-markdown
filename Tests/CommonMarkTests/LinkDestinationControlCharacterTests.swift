/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The destination URL of the first `.link` node in depth-first order, or nil if there is none.
private func firstLinkURL(_ node: borrowing MarkdownNode) -> String? {
    if node.kind == .link {
        return node.url()
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstLinkURL(child)
        }
    }
    return found
}

/// The literal text of the first `.text` node in depth-first order, or nil if there is none.
private func firstText(_ node: borrowing MarkdownNode) -> String? {
    if node.kind == .text {
        return node.literal()
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstText(child)
        }
    }
    return found
}

/// A bare link destination does not include ASCII control characters (Links), so a line tabulation (VT) or form feed
/// (FF) ends it. Both are whitespace characters (Characters and lines), so either may separate the destination from
/// what follows.
@Suite("Control characters in a bare link destination")
struct LinkDestinationControlCharacterTests {

    private static let options: MarkdownDocument.ParseOptions = []

    private func linkURL(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> String? {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstLinkURL(doc.root)
        }
    }

    // MARK: Inline links

    @Test("`[](\\u{FFFD}\\u{0B})` has the destination `\u{FFFD}`")
    func inlineTrailingVTAfterReplacementCharacter() {
        #expect(linkURL("[](\u{FFFD}\u{0B})", options: Self.options) == "\u{FFFD}")
    }

    @Test("`[](a\\u{0B}b)` forms no link: the VT ends the destination and `b)` is not a link title")
    func inlineInteriorVT() {
        #expect(linkURL("[](a\u{0B}b)", options: Self.options) == nil)
    }

    @Test("`[](a\\u{0B})` has the destination `a`")
    func inlineTrailingVT() {
        #expect(linkURL("[](a\u{0B})", options: Self.options) == "a")
    }

    @Test("`[](a\\u{0C}b)` forms no link: the FF ends the destination and `b)` is not a link title")
    func inlineInteriorFF() {
        #expect(linkURL("[](a\u{0C}b)", options: Self.options) == nil)
    }

    // MARK: Link reference definitions

    /// A link reference definition needs a destination, and the paragraph's final whitespace, here a line
    /// tabulation, is removed (Paragraphs).
    @Test("`[?]:\\u{0B}` is not a link reference definition: the paragraph text is `[?]:`")
    func refDefWithOnlyVT() throws {
        let text = MarkdownDocument.withParsedDocument("[?]:\u{0B}", options: Self.options) { doc -> String? in
            firstText(doc.root)
        }
        #expect(try #require(text, "expected a paragraph text node") == "[?]:")
    }

    // MARK: Space, tab and ordinary characters

    @Test("`[](a b)` forms no link: the space ends the destination")
    func spaceEndsDestination() {
        #expect(linkURL("[](a b)", options: Self.options) == nil)
    }

    @Test("`[](a\tb)` forms no link: the tab ends the destination")
    func tabEndsDestination() {
        #expect(linkURL("[](a\tb)", options: Self.options) == nil)
    }

    @Test("`[](ab)` is a link with the destination `ab`")
    func plainDestination() {
        #expect(linkURL("[](ab)", options: Self.options) == "ab")
    }
}
