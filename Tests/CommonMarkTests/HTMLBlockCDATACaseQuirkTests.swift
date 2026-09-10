/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// CommonMark HTML block start condition 5 begins with the literal string `<![CDATA[`, matched
/// case-SENSITIVELY (uppercase `CDATA`). So `<![CDAtA[` / `<![cdata[` are NOT type-5 starts, and
/// `<![` is not a type-4 start either (type 4 needs `<!` followed by an uppercase ASCII letter, and
/// `[` is not a letter), so per spec they are ordinary paragraphs. The deliverable (flag OFF) keeps
/// that spec-correct behavior.
///
/// cmark-gfm matches the opener loosely: `_scan_html_block_start` (swift-cmark `src/scanners.re`)
/// scans the single-quoted re2c pattern `'<![CDATA['`, and re2c compiles a single-quoted string to a
/// case-INSENSITIVE matcher — the generated `scanners.c` accepts either case at every letter state
/// (state `yy318` onward: `if (yych=='C') ... if (yych=='c')`, and likewise D/A/T/A). So cmark opens a
/// type-5 HTML block for `<![cdata[`, `<![CDAtA[`, … The trailing `[` is a literal bracket (only `[`
/// reaches `return 5`), so `<![CDATAx` — no second bracket — stays a paragraph in cmark too.
///
/// This is a `[ref-b4b]` quirk reproduced ONLY under `.cmarkBugCompatibility` (adopted by the
/// differential fuzzer). HTML-block recognition is STRUCTURAL (an `.htmlBlock` node vs a `.paragraph`
/// of literal text), so it is gated on the flag alone; these tests parse without `.sourcePosition`.
@Suite("HTML block type-5 CDATA case-insensitive start quirk")
struct HTMLBlockCDATACaseQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []
    private static let flagOn: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]

    /// Concatenated literal content of `node` and its descendants (DFS). For a single-line HTML block
    /// this is the block body; for a paragraph it is the run of text.
    private func allText(_ node: borrowing MarkdownNode) -> String {
        var out = ""
        if let lit = node.literal() { out += lit }
        node.children.forEach { out += allText($0) }
        return out
    }

    /// The document's first block: its kind plus its full literal text, with a single trailing newline
    /// removed. cmark newline-terminates every HTML-block body (so `<![CDATA[` yields the body
    /// `"<![CDATA[\n"`) while paragraph text has none; stripping one trailing `\n` lets each test compare
    /// the block's meaningful content against the source it was given, uniformly across both kinds. The
    /// fixture-sanity `#require` fails loudly on a degenerate (childless) tree so no case passes vacuously.
    private func firstBlock(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> (kind: MarkdownNode.Kind, text: String) {
        let found: (MarkdownNode.Kind, String)? =
            try MarkdownDocument.withParsedDocument(src, options: options) { doc in
                var first: (MarkdownNode.Kind, String)? = nil
                doc.root.children.forEach { child in
                    if first == nil { first = (child.kind, allText(child)) }
                }
                return first
            }
        let block = try #require(found, "fixture vacuous: no block parsed for \(src.debugDescription)")
        let text = block.1.hasSuffix("\n") ? String(block.1.dropLast()) : block.1
        return (block.0, text)
    }

    // MARK: Flag ON — reproduce cmark's case-insensitive CDATA opener

    @Test("flag ON: `<![CDAtA[` (lowercase t) opens an HTML block")
    func flagOnMixedCase() throws {
        let block = try firstBlock("<![CDAtA[", options: Self.flagOn)
        #expect(block.kind == .htmlBlock)
        #expect(block.text == "<![CDAtA[")
    }

    @Test("flag ON: `<![cdata[` (all lowercase) opens an HTML block")
    func flagOnAllLowercase() throws {
        let block = try firstBlock("<![cdata[", options: Self.flagOn)
        #expect(block.kind == .htmlBlock)
        #expect(block.text == "<![cdata[")
    }

    @Test("flag ON control: exact `<![CDATA[` still opens an HTML block")
    func flagOnExact() throws {
        let block = try firstBlock("<![CDATA[", options: Self.flagOn)
        #expect(block.kind == .htmlBlock)
        #expect(block.text == "<![CDATA[")
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (case-sensitive CDATA)

    @Test("flag OFF: `<![CDAtA[` (lowercase t) is a paragraph")
    func flagOffMixedCase() throws {
        let block = try firstBlock("<![CDAtA[", options: Self.flagOff)
        #expect(block.kind == .paragraph)
        #expect(block.text == "<![CDAtA[")
    }

    @Test("flag OFF: `<![cdata[` (all lowercase) is a paragraph")
    func flagOffAllLowercase() throws {
        let block = try firstBlock("<![cdata[", options: Self.flagOff)
        #expect(block.kind == .paragraph)
        #expect(block.text == "<![cdata[")
    }

    @Test("flag OFF control: exact `<![CDATA[` opens an HTML block (unchanged)")
    func flagOffExact() throws {
        let block = try firstBlock("<![CDATA[", options: Self.flagOff)
        #expect(block.kind == .htmlBlock)
        #expect(block.text == "<![CDATA[")
    }

    // MARK: Agreeing controls under BOTH flags (guard against over-broadening)

    /// `<![CDATAx` has no second `[`. cmark's scanner requires the literal trailing `[` (only `[`
    /// reaches `return 5`; anything else backtracks to `return 0`), so it is a paragraph in cmark, and
    /// case-insensitivity must not change that. Verified from `scanners.c` state `yy451` (`if (yych=='[')`).
    @Test("both flags: `<![CDATAx` (no trailing bracket) is a paragraph")
    func noTrailingBracket() throws {
        for options in [Self.flagOff, Self.flagOn] {
            let block = try firstBlock("<![CDATAx", options: options)
            #expect(block.kind == .paragraph)
            #expect(block.text == "<![CDATAx")
        }
    }

    /// `<!x` (lowercase letter after `<!`) is not a start for any HTML block type: type 4 needs an
    /// uppercase letter (`'<!' [A-Z]`, a case-SENSITIVE character class, not loosened by the flag) and
    /// the CDATA branch needs `<![`. So it is a paragraph in cmark under both flags. Verified from
    /// `scanners.c` state `yy297` (lowercase falls through to `return 0`).
    @Test("both flags: `<!x` (lowercase after `<!`) is a paragraph")
    func lowercaseAfterBang() throws {
        for options in [Self.flagOff, Self.flagOn] {
            let block = try firstBlock("<!x", options: options)
            #expect(block.kind == .paragraph)
            #expect(block.text == "<!x")
        }
    }

    /// `<!DOCTYPE html>` is a type-4 start (`<!` + uppercase `D`) in cmark and the deliverable alike,
    /// so it opens an HTML block under both flags — the CDATA change must not disturb type 4.
    @Test("both flags: `<!DOCTYPE html>` opens an HTML block (type 4 unchanged)")
    func type4Declaration() throws {
        for options in [Self.flagOff, Self.flagOn] {
            let block = try firstBlock("<!DOCTYPE html>", options: options)
            #expect(block.kind == .htmlBlock)
            #expect(block.text == "<!DOCTYPE html>")
        }
    }
}
