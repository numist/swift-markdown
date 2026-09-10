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

// The number of immediate children of `node` (used to assert the document root has no blocks).
private func childCount(_ node: borrowing MarkdownNode) -> Int {
    var n = 0
    node.children.forEach { _ in n += 1 }
    return n
}

/// cmark-gfm's bare link-destination scanner (`manual_scan_link_url_2`, `src/inlines.c`) terminates a
/// bare `(...)` / reference-definition destination only on `cmark_isspace` = {space, tab, `\n`, `\r`}
/// (the `cmark_ctype_class` class-1 bytes) or an unbalanced `)`. Vertical tab (VT, 0x0B) and form feed
/// (FF, 0x0C) are class-0, so cmark does NOT stop on them and KEEPS them as literal destination content.
///
/// That contradicts CommonMark §6.5 — a *bare* link destination "does not include ASCII control
/// characters", and VT/FF are ASCII controls (U+0000–U+001F) — so terminating a bare destination at
/// VT/FF is spec-correct. This is therefore a `[ref-b4b]` quirk: reproduced ONLY under
/// `.cmarkBugCompatibility` (adopted by the differential fuzzer); the shipped deliverable (flag OFF)
/// stays spec-correct and terminates at VT/FF.
///
/// The quirk is structural (the retained VT changes the destination content and, for a ref-def, whether
/// the definition forms at all — collapsing the document to no blocks), so it gates on
/// `.cmarkBugCompatibility` alone with no positions dependency; these tests parse without
/// `.sourcePosition`. The angle-bracket `<...>` destination form allows control chars in both cmark and
/// the spec and is unaffected.
@Suite("Bare link-destination VT/FF control-char quirk")
struct LinkDestinationControlCharQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []
    private static let flagOn: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]

    private func linkURL(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> String? {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstLinkURL(doc.root)
        }
    }

    // MARK: Facet A — inline bare destination (VT/FF kept as content flag ON)

    @Test("flag ON: `[](\\u{FFFD}\\u{0B})` keeps the VT — dest is `\u{FFFD}\u{0B}`")
    func flagOnInlineFacetA() throws {
        // The fuzzer artifact was `[](` + 0xE2 (repaired to U+FFFD) + VT + `)`.
        #expect(try linkURL("[](\u{FFFD}\u{0B})", options: Self.flagOn) == "\u{FFFD}\u{0B}")
    }

    @Test("flag ON: `[](a\\u{0B}b)` keeps the interior VT — dest is `a\u{0B}b`")
    func flagOnInlineInteriorVT() throws {
        #expect(try linkURL("[](a\u{0B}b)", options: Self.flagOn) == "a\u{0B}b")
    }

    @Test("flag ON: `[](a\\u{0B})` keeps the trailing VT — dest is `a\u{0B}`")
    func flagOnInlineTrailingVT() throws {
        #expect(try linkURL("[](a\u{0B})", options: Self.flagOn) == "a\u{0B}")
    }

    @Test("flag ON: `[](a\\u{0C}b)` keeps the interior FF — dest is `a\u{0C}b`")
    func flagOnInlineInteriorFF() throws {
        #expect(try linkURL("[](a\u{0C}b)", options: Self.flagOn) == "a\u{0C}b")
    }

    @Test("flag OFF: `[](\\u{FFFD}\\u{0B})` drops the VT — dest is `\u{FFFD}` (spec-correct)")
    func flagOffInlineFacetA() throws {
        #expect(try linkURL("[](\u{FFFD}\u{0B})", options: Self.flagOff) == "\u{FFFD}")
    }

    @Test("flag OFF: `[](a\\u{0B}b)` forms NO link — the VT terminates the dest so `b)` fails the close")
    func flagOffInlineInteriorVT() throws {
        #expect(try linkURL("[](a\u{0B}b)", options: Self.flagOff) == nil)
    }

    // MARK: Facet B — reference-definition bare destination (VT forms the dest flag ON)

    @Test("flag ON: `[?]:\\u{0B}` forms a valid (unused) ref-def — document has no blocks")
    func flagOnRefDefFacetB() throws {
        let count = try MarkdownDocument.withParsedDocument("[?]:\u{0B}", options: Self.flagOn) { doc in
            childCount(doc.root)
        }
        // Fixture-sanity: prove the input is meaningful (not a vacuous "empty tree passes anything")
        // by confirming the SAME input yields exactly one block (a paragraph) with the flag OFF.
        let offCount = try MarkdownDocument.withParsedDocument("[?]:\u{0B}", options: Self.flagOff) { doc in
            childCount(doc.root)
        }
        #expect(offCount == 1, "flag-OFF should produce one paragraph block; got \(offCount)")
        #expect(count == 0, "flag-ON should collapse to no blocks (ref-def forms); got \(count)")
    }

    @Test("flag OFF: `[?]:\\u{0B}` is not a ref-def — paragraph text is `[?]:\u{0B}` (spec-correct)")
    func flagOffRefDefFacetB() throws {
        let text = try MarkdownDocument.withParsedDocument("[?]:\u{0B}", options: Self.flagOff) { doc -> String? in
            firstText(doc.root)
        }
        // Fixture-sanity: a text node must exist, so the content claim can't pass against an empty tree.
        #expect(try #require(text, "expected a paragraph text node") == "[?]:\u{0B}")
    }

    // MARK: Agreeing controls — space/tab still terminate under BOTH flags (guard over-broadening)

    @Test("`[](a b)` forms no link under either flag (space terminates the dest)")
    func spaceTerminatesBothFlags() throws {
        #expect(try linkURL("[](a b)", options: Self.flagOn) == nil)
        #expect(try linkURL("[](a b)", options: Self.flagOff) == nil)
    }

    @Test("`[](a\tb)` forms no link under either flag (tab terminates the dest)")
    func tabTerminatesBothFlags() throws {
        #expect(try linkURL("[](a\tb)", options: Self.flagOn) == nil)
        #expect(try linkURL("[](a\tb)", options: Self.flagOff) == nil)
    }

    @Test("`[](ab)` is a link with dest `ab` under both flags (positive control)")
    func plainDestBothFlags() throws {
        #expect(try linkURL("[](ab)", options: Self.flagOn) == "ab")
        #expect(try linkURL("[](ab)", options: Self.flagOff) == "ab")
    }
}
