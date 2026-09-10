/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Concatenate every TEXT node's literal content, depth-first, and count how many were seen. File-scope
// + `borrowing MarkdownNode` and `inout` accumulators to satisfy the noncopyable-borrow rules (see the
// b4b pattern in `TaskListCheckboxStrstrQuirkTests`): the borrow can't be captured across the walk.
private func collectText(_ node: borrowing MarkdownNode, into out: inout String, count: inout Int) {
    if case .text = node.kind, case .text(let literal) = node.stringContent {
        out += literal
        count += 1
    }
    node.children.forEach { child in
        collectText(child, into: &out, count: &count)
    }
}

/// cmark-gfm decodes numeric character references through `houdini_unescape_ent` (swift-cmark
/// `src/houdini_html_u.c`), which `handle_entity` (`src/inlines.c`) calls directly — the stricter
/// `_scan_entity` grammar (`src/scanners.re`, decimal `[0-9]{1,7}` / hex `[Xx][A-Fa-f0-9]{1,6}`) is
/// never consulted for inline entities. That decoder's shared gate is `num_digits >= 1 && num_digits
/// <= 8` for BOTH the decimal and hex branches, so cmark accepts up to 8 decimal digits and up to 8 hex
/// digits — looser than CommonMark §6.5's 7-decimal / 6-hex limits. An out-of-range value (`> 0x10FFFF`)
/// still decodes to U+FFFD, so an 8-digit decimal ref such as `&#98665435;` becomes U+FFFD in cmark
/// while the spec (and the rewrite) leaves it literal.
///
/// This is a `[ref-b4b]` quirk: reproduced ONLY under `.cmarkBugCompatibility` (adopted by the
/// differential fuzzer). The shipped deliverable (flag OFF) stays spec-correct — an 8+-digit decimal
/// ref, or a 7+-digit hex ref, stays literal. Valid 1–7-digit decimal / 1–6-digit hex refs decode
/// identically under both flags.
@Suite("Numeric character reference digit-limit quirk")
struct NumericEntityDigitLimitQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []
    private static let flagOn: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]

    private static let replacement = "\u{FFFD}"
    private static let maxScalar = "\u{10FFFF}"

    private func text(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> String {
        let (out, count): (String, Int) = try MarkdownDocument.withParsedDocument(src, options: options) { doc -> (String, Int) in
            var out = ""
            var count = 0
            collectText(doc.root, into: &out, count: &count)
            return (out, count)
        }
        // Fixture-sanity: at least one text node must exist, so a content claim can't pass vacuously
        // against a tree that parsed to no text at all.
        try #require(count >= 1, "no text node parsed")
        return out
    }

    // MARK: Flag ON — reproduce cmark's looser 8-digit acceptance

    @Test("flag ON: `&#98665435;` (8 decimal digits) decodes to U+FFFD")
    func flagOnDecimalEightDigitsFinding() throws {
        #expect(try text("&#98665435;", options: Self.flagOn) == Self.replacement)
    }

    @Test("flag ON: `&#12345678;` (8 decimal digits) decodes to U+FFFD")
    func flagOnDecimalEightDigits() throws {
        #expect(try text("&#12345678;", options: Self.flagOn) == Self.replacement)
    }

    @Test("flag ON: `&#x1234567;` (7 hex digits) decodes to U+FFFD")
    func flagOnHexSevenDigits() throws {
        #expect(try text("&#x1234567;", options: Self.flagOn) == Self.replacement)
    }

    @Test("flag ON: `&#x12345678;` (8 hex digits) decodes to U+FFFD")
    func flagOnHexEightDigits() throws {
        #expect(try text("&#x12345678;", options: Self.flagOn) == Self.replacement)
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (7 decimal / 6 hex)

    @Test("flag OFF: `&#98665435;` (8 decimal digits) stays literal")
    func flagOffDecimalEightDigitsFinding() throws {
        #expect(try text("&#98665435;", options: Self.flagOff) == "&#98665435;")
    }

    @Test("flag OFF: `&#12345678;` (8 decimal digits) stays literal")
    func flagOffDecimalEightDigits() throws {
        #expect(try text("&#12345678;", options: Self.flagOff) == "&#12345678;")
    }

    @Test("flag OFF: `&#x1234567;` (7 hex digits) stays literal")
    func flagOffHexSevenDigits() throws {
        #expect(try text("&#x1234567;", options: Self.flagOff) == "&#x1234567;")
    }

    @Test("flag OFF: `&#x12345678;` (8 hex digits) stays literal")
    func flagOffHexEightDigits() throws {
        #expect(try text("&#x12345678;", options: Self.flagOff) == "&#x12345678;")
    }

    // MARK: Agreeing controls — decode identically under both flags

    @Test("controls: valid 1–7 decimal / 1–6 hex refs and 9+-digit rejects agree under both flags")
    func agreeingControls() throws {
        for options in [Self.flagOff, Self.flagOn] {
            // In-range values decode to their scalar.
            #expect(try text("&#65;", options: options) == "A")
            #expect(try text("&#x41;", options: options) == "A")
            // Max scalar, at the digit-count boundaries the spec allows (7 decimal / 6 hex).
            #expect(try text("&#1114111;", options: options) == Self.maxScalar)
            #expect(try text("&#x10FFFF;", options: options) == Self.maxScalar)
            // Out-of-range values within the spec digit limits decode to U+FFFD.
            #expect(try text("&#0;", options: options) == Self.replacement)
            #expect(try text("&#1234567;", options: options) == Self.replacement)
            #expect(try text("&#xFFFFFF;", options: options) == Self.replacement)
            // Surrogate codepoints (U+D800…U+DFFF) also map to U+FFFD, decimal and hex alike.
            #expect(try text("&#55296;", options: options) == Self.replacement)
            #expect(try text("&#xDFFF;", options: options) == Self.replacement)
            // 9+ digits exceed even cmark's looser cap of 8, so they stay literal under both flags
            // (the hex case also guards against integer overflow while accumulating the codepoint).
            #expect(try text("&#123456789;", options: options) == "&#123456789;")
            #expect(try text("&#x123456789;", options: options) == "&#x123456789;")
        }
    }
}
