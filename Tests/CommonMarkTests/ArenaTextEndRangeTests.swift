/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// cmark bug-compatible (flag-ON) coverage for the source-range END of an arena-backed inline text
/// node (smart-punctuation en-dash) inside a re-indented, multi-segment paragraph continuation.
///
/// Flag-ON re-indent maps a *lazy* continuation line's surviving content to `residual + block_offset`
/// past the block's content column (`BlockParser.addLineSegment`). For ` - b\n  -- c\n  d` the line-2
/// content `-- c` maps to source offsets that spill past line 2's newline onto line 3's bytes. Smart
/// punctuation then SPLITS `-- c` into an arena `–` glyph node plus a following source ` c` fragment;
/// the fragment's start already maps onto line 3, so a start-line-anchored end guard used to miss the
/// overshoot and the fragment's byte end leaked through `consolidateTextNodes` as the merged node's
/// end (`– c @2:6-3:3`). `InlineParser.stampInline` now anchors the end on the run's base source line
/// (`sourceRunBase`), keeping the merged node on line 2 (`– c @2:6-2:10`) like cmark and like the
/// un-split single-node case. Covered flag-ON by the `arenaend-*` fuzzer pairs; this suite is the
/// focused CommonMark-level assertion.
@Suite("Arena text-node end in multi-segment content (cmark bug-compatible)")
struct ArenaTextEndRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Source positions on, smart punctuation on, cmark bug-compatibility ON - the differential-fuzzer
    /// configuration that exercises the re-indent + smart-punct split.
    private static let quirkOptions: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .cmarkBugCompatibility]

    /// DFS-collect every text node's literal and source range.
    private func textNodes(in src: String) throws -> [(literal: String?, range: Range<Pos>?)] {
        var out: [(literal: String?, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(src, options: Self.quirkOptions) { doc in
            collectText(doc.root, into: &out)
        }
        return out
    }

    @Test("en-dash text node ends on its own line, not the following continuation line")
    func enDashEndStaysOnOwnLine() throws {
        // " - b" (list item, content column 4), "  -- c" (2-space LAZY continuation → re-indent
        // shifts +5), "  d" (further continuation). Smart-punct rewrites `--`→`–`, splitting the
        // line-2 run into an arena `–` glyph plus a source ` c` fragment; consolidation merges them.
        // cmark reports the merged `– c` on line 2 at @2:6-2:10 - the end must NOT overshoot onto
        // line 3 (`  d`, where the byte projection lands at @3:3).
        let texts = try textNodes(in: " - b\n  -- c\n  d")
        try #require(texts.count == 3, "expected b / – c / d text nodes")

        // Fixture sanity: smart-punct actually produced the en-dash (not a literal `--`), so this
        // exercises the arena-split path rather than a plain source run.
        try #require(texts[1].literal == "\u{2013} c", "expected the en-dash arena run, got \(String(describing: texts[1].literal))")

        #expect(texts[0].range?.lowerBound == Pos(line: 1, column: 4))   // "b"
        #expect(texts[0].range?.upperBound == Pos(line: 1, column: 5))
        #expect(texts[1].range?.lowerBound == Pos(line: 2, column: 6))   // "– c" re-indented start
        #expect(texts[1].range?.upperBound == Pos(line: 2, column: 10))  // end stays on line 2
        #expect(texts[2].range?.lowerBound == Pos(line: 3, column: 6))   // "d"
        #expect(texts[2].range?.upperBound == Pos(line: 3, column: 7))
    }

    @Test("plain-text continuation is unaffected - matched continuation stays on its own line")
    func plainTextControlUnaffected() throws {
        // " - b" then "   c" (3-space MATCHED continuation, no smart-punct rewrite → a single plain
        // source text node) then "  d". The matched continuation maps within line 2 (no overshoot),
        // so the run-base end guard never fires and `c` keeps its byte-projected @2:4-2:5. This is
        // the guardrail that the fix touches only overshooting arena runs, not the plain path.
        let texts = try textNodes(in: " - b\n   c\n  d")
        try #require(texts.count == 3, "expected b / c / d text nodes")
        try #require(texts[1].literal == "c", "expected a plain `c` text node, got \(String(describing: texts[1].literal))")

        #expect(texts[1].range?.lowerBound == Pos(line: 2, column: 4))   // "c" at its own column
        #expect(texts[1].range?.upperBound == Pos(line: 2, column: 5))   // end on line 2
    }
}

// File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see `dfsRanges`).
private func collectText(
    _ node: borrowing MarkdownNode,
    into out: inout [(literal: String?, range: Range<MarkdownNode.SourcePosition>?)]
) {
    if node.kind == .text {
        out.append((node.literal(), node.sourceRange))
    }
    node.children.forEach { child in
        collectText(child, into: &out)
    }
}
