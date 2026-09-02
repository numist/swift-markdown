/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Flag-ON coverage that a re-indented, multi-segment paragraph continuation whose surviving content
/// maps *within* its own physical line keeps its byte-projected source range.
///
/// Flag-ON re-indent maps a paragraph continuation line's surviving content to the block's content
/// column (`BlockParser.addLineSegment`). When that mapping stays within the line (the common,
/// non-overshooting case) the content's inline nodes byte-project onto their re-indented columns, the
/// same as any source-backed run. This is the guardrail that the re-indent mapping doesn't disturb a
/// non-overshooting continuation run.
@Suite("Arena text-node end in multi-segment content (cmark bug-compatible)")
struct ArenaTextEndRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Source positions on, smart punctuation on, cmark bug-compatibility ON - the differential-fuzzer
    /// configuration that exercises the re-indent.
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
