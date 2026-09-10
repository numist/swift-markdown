/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the literal content of the first `.htmlInline` node, or nil if the tree has none.
// File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// code-conventions: use file-scope helpers, don't capture the borrow across the tree walk).
private func firstInlineHTML(_ node: borrowing MarkdownNode) -> String? {
    if case .htmlInline = node.kind, case .text(let s) = node.stringContent {
        return s
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstInlineHTML(child)
        }
    }
    return found
}

// Depth-first: the body of the first `.htmlBlock` node, or nil if the tree has none.
private func firstHTMLBlock(_ node: borrowing MarkdownNode) -> String? {
    if case .htmlBlock = node.kind, case .htmlBlock(let body) = node.stringContent {
        return body
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstHTMLBlock(child)
        }
    }
    return found
}

// Depth-first: all `.text` literal content concatenated. Used for fixture-sanity so a "no inline
// HTML" claim can't pass against a degenerate empty tree — the literal source must survive as text.
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

/// cmark-gfm's INLINE processing-instruction scanner (`handle_pointy_brace` + `_scan_html_pi`,
/// swift-cmark `src/inlines.c` / `src/scanners.re`) matches the PI body with the regex
/// `processinginstruction = ([^?>\x00]+ | [?][^>\x00] | [>])+` starting at the byte AFTER the
/// opening `?`, then unconditionally frames the match with `<?`…`?>` (`matchlen += 3`) and REJECTS
/// the PI when that framing overruns the subject (`subj->pos + matchlen > input.len`). Because the
/// regex admits a lone `>` and pairs every `?` with its FOLLOWING byte, a body that begins with `?`
/// can swallow the closing `?>`: for `<???>` the scan (from the 3rd byte, `??>`) eats `??` then `>`,
/// leaving no terminator, so `matchlen` overruns and cmark treats the whole `<???>` as literal text.
/// A body of `x` (`<?x?>`) matches only `x` and stops before `?>`, so it is accepted. This is
/// INLINE-only: `<???>` alone on a line is an HTML block (type 3), whose scanner (`<?` opener +
/// end-of-block on `?>`) does not use the buggy regex, so both parsers agree there.
///
/// Per CommonMark 0.31 §6.6 a processing instruction is `<?`, a string of characters not including
/// `?>`, then `?>`; `<???>` = `<?` + `?` + `?>` (the body `?` contains no `?>`) is a VALID inline
/// PI. cmark's regex-based scanner rejects it, so this is a `[ref-b4b]` quirk: reproduced ONLY under
/// `.cmarkBugCompatibility` (adopted by the differential fuzzer). The shipped deliverable (flag OFF)
/// stays spec-correct — `<???>` is recognized as an inline PI. The quirk is STRUCTURAL (an
/// `.htmlInline` node appears vs. not), so it is gated on `.cmarkBugCompatibility` alone with no
/// positions dependency; these tests parse without `.sourcePosition`.
@Suite("Inline processing-instruction `<???>` question-mark quirk")
struct InlineProcessingInstructionQuestionMarkQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []
    private static let flagOn: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]

    private func inlineHTML(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> String? {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstInlineHTML(doc.root)
        }
    }

    private func text(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> String {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> String in
            collectText(doc.root)
        }
    }

    // MARK: Flag ON — reproduce cmark rejecting `<???>` inline (literal text)

    @Test("flag ON: `f<???>` is literal text (inline PI rejected)")
    func flagOnFindingLiteral() throws {
        #expect(try inlineHTML("f<???>", options: Self.flagOn) == nil)
        // Fixture-sanity: the literal source survives as text, so the "no inline HTML" claim isn't
        // vacuous against an empty tree.
        #expect(try text("f<???>", options: Self.flagOn) == "f<???>")
    }

    @Test("flag ON: `\\u{0000}<???>` is literal text (NUL→U+FFFD, then PI rejected)")
    func flagOnFindingWithNUL() throws {
        #expect(try inlineHTML("\u{0000}<???>", options: Self.flagOn) == nil)
        #expect(try text("\u{0000}<???>", options: Self.flagOn) == "\u{FFFD}<???>")
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (`<???>` is a valid inline PI)

    @Test("flag OFF: `f<???>` recognizes the inline PI")
    func flagOffFindingRecognized() throws {
        #expect(try inlineHTML("f<???>", options: Self.flagOff) == "<???>")
        #expect(try text("f<???>", options: Self.flagOff) == "f")
    }

    @Test("flag OFF: `\\u{0000}<???>` recognizes the inline PI")
    func flagOffFindingWithNUL() throws {
        #expect(try inlineHTML("\u{0000}<???>", options: Self.flagOff) == "<???>")
        #expect(try text("\u{0000}<???>", options: Self.flagOff) == "\u{FFFD}")
    }

    // MARK: Agreeing controls — inline PIs both parsers still recognize (must not regress)

    @Test("both flags: `f<?x?>` recognizes the inline PI (body `x`)")
    func bothInlinePIBodyX() throws {
        #expect(try inlineHTML("f<?x?>", options: Self.flagOff) == "<?x?>")
        #expect(try inlineHTML("f<?x?>", options: Self.flagOn) == "<?x?>")
    }

    @Test("both flags: `a<?b?>c` recognizes the inline PI mid-text")
    func bothInlinePIMidText() throws {
        #expect(try inlineHTML("a<?b?>c", options: Self.flagOff) == "<?b?>")
        #expect(try inlineHTML("a<?b?>c", options: Self.flagOn) == "<?b?>")
        #expect(try text("a<?b?>c", options: Self.flagOff) == "ac")
        #expect(try text("a<?b?>c", options: Self.flagOn) == "ac")
    }

    @Test("both flags: `f<? ?>` recognizes the inline PI (space body)")
    func bothInlinePISpaceBody() throws {
        #expect(try inlineHTML("f<? ?>", options: Self.flagOff) == "<? ?>")
        #expect(try inlineHTML("f<? ?>", options: Self.flagOn) == "<? ?>")
    }

    @Test("both flags: `f<??>` recognizes the empty inline PI")
    func bothInlinePIEmptyBody() throws {
        #expect(try inlineHTML("f<??>", options: Self.flagOff) == "<??>")
        #expect(try inlineHTML("f<??>", options: Self.flagOn) == "<??>")
    }

    @Test("both flags: `f<????>` recognizes the inline PI (one more `?` than the finding)")
    func bothInlinePIFourQuestionMarks() throws {
        // Parity crux of the quirk: `<???>` rejects flag-ON because the body scan of `??>` pairs `??`
        // then swallows `>`, leaving no closer. `<????>` scans `???>` — it pairs `??`, stops at the
        // next `?` (which precedes `>`), and leaves the closing `?>` intact, so cmark accepts it, as
        // does the spec. So one extra `?` flips the flag-ON result from reject back to accept.
        #expect(try inlineHTML("f<????>", options: Self.flagOff) == "<????>")
        #expect(try inlineHTML("f<????>", options: Self.flagOn) == "<????>")
    }

    // MARK: Agreeing control — `<???>` alone is an HTML block (type 3), not inline, either way

    @Test("both flags: `<???>` alone is an HTML block, not inline")
    func bothStandaloneIsHTMLBlock() throws {
        for options in [Self.flagOff, Self.flagOn] {
            #expect(try inlineHTML("<???>", options: options) == nil)
            let block = try MarkdownDocument.withParsedDocument("<???>", options: options) { doc -> String? in
                firstHTMLBlock(doc.root)
            }
            let body = try #require(block, "expected an HTML block")
            #expect(body.contains("<???>"))
        }
    }
}
