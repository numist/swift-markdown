/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the destination URL of the first `.link` node, or nil if there is none. File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (a link's `url()` is always a
// String, so a nil result means "no link node", never "a link with a nil URL").
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

// Depth-first: the literal text of the first `.text` node, or nil if there is none.
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

/// cmark-gfm's bare link-destination scanner (`manual_scan_link_url_2`, `src/inlines.c`) terminates a
/// bare `(...)` / reference-definition destination only on `cmark_isspace` = {space, tab, `\n`, `\r`}
/// (the `cmark_ctype_class` class-1 bytes) or an unbalanced `)`. Vertical tab (VT, 0x0B) and form feed
/// (FF, 0x0C) are class-0, so cmark does NOT stop on them and KEEPS them as literal destination content.
///
/// That contradicts CommonMark §6.5 — a *bare* link destination "does not include ASCII control
/// characters", and VT/FF are ASCII controls (U+0000–U+001F) — so terminating a bare destination at
/// VT/FF is spec-correct.
///
/// The angle-bracket `<...>` destination form allows control chars in both cmark and
/// the spec and is unaffected.
@Suite("Bare link-destination VT/FF control-char quirk")
struct LinkDestinationControlCharQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []

    private func linkURL(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> String? {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstLinkURL(doc.root)
        }
    }

    // MARK: Facet A — inline bare destination

    @Test("flag OFF: `[](\\u{FFFD}\\u{0B})` drops the VT — dest is `\u{FFFD}` (spec-correct)")
    func flagOffInlineFacetA() {
        #expect(linkURL("[](\u{FFFD}\u{0B})", options: Self.flagOff) == "\u{FFFD}")
    }

    @Test("flag OFF: `[](a\\u{0B}b)` forms NO link — the VT terminates the dest so `b)` fails the close")
    func flagOffInlineInteriorVT() {
        #expect(linkURL("[](a\u{0B}b)", options: Self.flagOff) == nil)
    }

    /// A bare destination stops at the VT, which then separates the destination from the `)` as whitespace, so the
    /// destination is `a` where cmark-gfm keeps the VT in it.
    @Test("flag OFF: `[](a\\u{0B})` drops the trailing VT — dest is `a` (spec-correct)")
    func flagOffInlineTrailingVT() {
        #expect(linkURL("[](a\u{0B})", options: Self.flagOff) == "a")
    }

    /// A bare destination stops at the FF, and the `b)` that follows is no link title, so no link forms where
    /// cmark-gfm keeps the FF in the destination `a\u{0C}b`.
    @Test("flag OFF: `[](a\\u{0C}b)` forms NO link — the FF terminates the dest so `b)` fails the close")
    func flagOffInlineInteriorFF() {
        #expect(linkURL("[](a\u{0C}b)", options: Self.flagOff) == nil)
    }

    // MARK: Facet B — reference-definition bare destination

    /// A link reference definition needs a destination, and the paragraph's final whitespace, here a line
    /// tabulation, is removed (spec "Paragraphs").
    @Test("`[?]:\\u{0B}` is not a ref-def — paragraph text is `[?]:`")
    func flagOffRefDefFacetB() throws {
        let text = MarkdownDocument.withParsedDocument("[?]:\u{0B}", options: Self.flagOff) { doc -> String? in
            firstText(doc.root)
        }
        // Fixture-sanity: a text node must exist, so the content claim can't pass against an empty tree.
        #expect(try #require(text, "expected a paragraph text node") == "[?]:")
    }

    // MARK: Agreeing controls — space/tab still terminate (guard over-broadening)

    @Test("`[](a b)` forms no link under either flag (space terminates the dest)")
    func spaceTerminatesBothFlags() {
        #expect(linkURL("[](a b)", options: Self.flagOff) == nil)
    }

    @Test("`[](a\tb)` forms no link under either flag (tab terminates the dest)")
    func tabTerminatesBothFlags() {
        #expect(linkURL("[](a\tb)", options: Self.flagOff) == nil)
    }

    @Test("`[](ab)` is a link with dest `ab` under both flags (positive control)")
    func plainDestBothFlags() {
        #expect(linkURL("[](ab)", options: Self.flagOff) == "ab")
    }
}
