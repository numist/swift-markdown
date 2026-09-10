/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the destination URL of the first `.link` node, or nil if the tree has none. File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see code-conventions: use file-scope
// helpers, don't capture the borrow across the tree walk).
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

// Depth-first: all `.text` literal content concatenated. Used for fixture-sanity so a "not a link" claim
// can't pass against a degenerate empty tree — the literal source must survive as text.
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

/// cmark's URI-autolink scanner `_scan_autolink_uri` (swift-cmark `src/scanners.re`) matches the body after
/// `scheme:` with the character class `[^\x00-\x20<>]*`. That class excludes 0x00–0x20 and `<`/`>`, but NOT
/// DEL (U+007F). DEL is an ASCII control character, so CommonMark §6.5 ("zero or more characters other than
/// ASCII control characters, space, `<`, and `>`") excludes it and a valid autolink cannot contain it — yet
/// cmark's scanner wrongly ADMITS it, so `<tp:\u{7F}>` parses as an autolink under cmark. The email form
/// (`_scan_autolink_email`) uses explicit alnum + punctuation classes that never include 0x7F, so ONLY the
/// URI form diverges.
///
/// This is a `[ref-b4b]` quirk: reproduced ONLY under `.cmarkBugCompatibility` (adopted by the differential
/// fuzzer). The shipped deliverable (flag OFF) stays spec-correct — DEL is rejected, so the `<…>` stays
/// literal text. The quirk is STRUCTURAL (a `.link` node appears vs. not), so it is gated on
/// `.cmarkBugCompatibility` alone with no positions dependency; these tests parse without `.sourcePosition`.
@Suite("Angle URI-autolink DEL (0x7F) quirk")
struct AngleAutolinkURIDelQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []
    private static let flagOn: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]

    private func linkURL(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> String? {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstLinkURL(doc.root) ?? nil
        }
    }

    private func text(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> String {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> String in
            collectText(doc.root)
        }
    }

    // MARK: Flag ON — reproduce cmark admitting DEL into the URI body

    @Test("flag ON: `<tp:\\u{7F}>` is a link (DEL admitted)")
    func flagOnDelIsLink() throws {
        let url = try #require(try linkURL("<tp:\u{7F}>", options: Self.flagOn), "expected an autolink")
        #expect(url == "tp:\u{7F}")
    }

    @Test("flag ON: `<tp:\\u{7F}>` link text carries the DEL")
    func flagOnDelLinkText() throws {
        #expect(try text("<tp:\u{7F}>", options: Self.flagOn) == "tp:\u{7F}")
    }

    @Test("flag ON: `<tp:aDELb>` is a link (DEL mid-body)")
    func flagOnDelMidBody() throws {
        let url = try #require(try linkURL("<tp:a\u{7F}b>", options: Self.flagOn), "expected an autolink")
        #expect(url == "tp:a\u{7F}b")
    }

    @Test("flag ON: `<http://aDEL>` is a link (DEL in URL)")
    func flagOnDelInHttpURL() throws {
        let url = try #require(try linkURL("<http://a\u{7F}>", options: Self.flagOn), "expected an autolink")
        #expect(url == "http://a\u{7F}")
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (DEL rejected → literal text)

    @Test("flag OFF: `<tp:\\u{7F}>` is NOT a link (literal text)")
    func flagOffDelNotLink() throws {
        #expect(try linkURL("<tp:\u{7F}>", options: Self.flagOff) == nil)
        // Fixture-sanity: the literal source survives as text, so the "not a link" claim isn't vacuous.
        #expect(try text("<tp:\u{7F}>", options: Self.flagOff) == "<tp:\u{7F}>")
    }

    @Test("flag OFF: `<http://aDEL>` is NOT a link (literal text)")
    func flagOffDelInHttpNotLink() throws {
        #expect(try linkURL("<http://a\u{7F}>", options: Self.flagOff) == nil)
        #expect(try text("<http://a\u{7F}>", options: Self.flagOff) == "<http://a\u{7F}>")
    }

    // MARK: Agreeing controls — guard against over-broadening (only 0x7F changes under the flag)

    @Test("both flags: `<tp:x>` is a link (ordinary URI)")
    func bothPlainURILinks() throws {
        #expect(try linkURL("<tp:x>", options: Self.flagOff) == "tp:x")
        #expect(try linkURL("<tp:x>", options: Self.flagOn) == "tp:x")
    }

    @Test("both flags: `<tp:\\u{1F}>` is NOT a link (0x1F C0 control rejected either way)")
    func bothC0ControlNotLink() throws {
        #expect(try linkURL("<tp:\u{1F}>", options: Self.flagOff) == nil)
        #expect(try linkURL("<tp:\u{1F}>", options: Self.flagOn) == nil)
    }

    @Test("both flags: `<tp:\\u{0B}>` is NOT a link (VT control rejected either way)")
    func bothVTControlNotLink() throws {
        #expect(try linkURL("<tp:\u{0B}>", options: Self.flagOff) == nil)
        #expect(try linkURL("<tp:\u{0B}>", options: Self.flagOn) == nil)
    }
}
