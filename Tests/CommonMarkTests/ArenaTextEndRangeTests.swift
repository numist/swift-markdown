/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// Source range for a text node on a MATCHED, multi-segment paragraph continuation line.
///
/// A matched continuation line (indented to the block's content column) already sits at that column,
/// so its surviving content byte-projects onto its true source column - the same as any source-backed
/// run. This is the deliverable (spec-correct) guardrail that a matched continuation's inline nodes
/// keep their byte-projected range; it is flag-independent (flag-ON `.cmarkBugCompatibility` produces
/// the same range for this matched node, since the re-indent maps it to the column it already holds).
@Suite("Arena text-node end in multi-segment content")
struct ArenaTextEndRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Source positions on, smart punctuation on (the shipped default; bug-compatibility off).
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart]

    /// DFS-collect every text node's literal and source range.
    private func textNodes(in src: String) throws -> [(literal: String?, range: Range<Pos>?)] {
        var out: [(literal: String?, range: Range<Pos>?)] = []
        try MarkdownDocument.withParsedDocument(src, options: Self.specOptions) { doc in
            collectText(doc.root, into: &out)
        }
        return out
    }

    @Test("a matched continuation text node keeps its byte-projected column")
    func matchedContinuationKeepsByteProjectedColumn() throws {
        // " - b" then "   c" (3-space MATCHED continuation, no smart-punct rewrite → a single plain
        // source text node) then "  d". The matched continuation `c` sits at the block content column,
        // so it byte-projects to its true @2:4-2:5 on its own physical line.
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
