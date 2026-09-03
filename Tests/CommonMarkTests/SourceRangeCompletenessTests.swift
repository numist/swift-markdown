/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
@testable import CommonMark

// DFS-collect each node's kind, source range, and leaf-ness. File-scope + `borrowing
// MarkdownNode` to satisfy the noncopyable-borrow rules (see SourcePositionTests.dfsRanges).
internal func dfsCompleteness(
    _ node: borrowing MarkdownNode,
    into out: inout [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)]
) {
    out.append((node.kind, node.sourceRange, node.isLeaf))
    node.children.forEach { child in
        dfsCompleteness(child, into: &out)
    }
}

@Suite("Source range completeness")
struct SourceRangeCompletenessTests {

    private static func loadSpec() throws -> [SpecExample] {
        let here = URL(fileURLWithPath: #filePath)
        let resource = here.deletingLastPathComponent().appendingPathComponent("spec.txt")
        let text = try String(contentsOf: resource, encoding: .utf8)
        return SpecParser.parse(text)
    }

    /// The qualified comparison surface: the GFM extensions the rewrite is being qualified
    /// against, plus source-position tracking. Applied uniformly to every example rather than
    /// the per-example spec annotations, so the invariant covers the whole surface. Deliberately
    /// excludes `.gfmAutolink` and `.footnotes`, which are outside the qualified surface.
    private static let options: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// Every node the parser produces on the qualified surface carries a valid source range -
    /// present, and not inverted (`lowerBound <= upperBound`) - except for a small, justified
    /// exempt set that is position-less on BOTH the rewrite and the cmark-gfm reference:
    ///
    /// - `.softBreak` / `.lineBreak`: cmark never stamps a position on a break, and the rewrite
    ///   matches (all 104 breaks in the corpus are nil, none carries a stray range).
    /// - Empty GFM table filler cells: a `.tableCell` with no children pads a short body row out
    ///   to the header's column count. It has no content, and cmark creates it with start_column
    ///   0 (see `extensions/table.c`, the body-row padding loop), which swift-markdown's converter
    ///   maps to a nil range. So it is genuinely position-less on both sides.
    ///
    /// This is a presence/ordering ratchet, not a value check: known wrong-but-stamped ranges
    /// (e.g. multi-line link end columns, single-range continuation paragraphs) do not trip it,
    /// because they produce a stamped range, not nil. A nil range on any other node - an
    /// out-of-order range collapses to nil upstream (see the ordering note below) - is a
    /// genuinely unstamped case and a regression.
    @Test("every non-exempt node carries a valid source range")
    func everyNonExemptNodeHasValidRange() throws {
        let examples = try Self.loadSpec()
        #expect(examples.count > 600)

        var totalNodes = 0
        var exemptFillerCells = 0
        var failures: [String] = []

        for ex in examples {
            var nodes: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
            try MarkdownDocument.withParsedDocument(ex.markdown, options: Self.options) { doc in
                dfsCompleteness(doc.root, into: &nodes)
            }
            totalNodes += nodes.count

            for node in nodes {
                // Breaks are position-less on both sides.
                switch node.kind {
                case .softBreak, .lineBreak:
                    continue
                default:
                    break
                }

                guard let range = node.range else {
                    // An empty table filler cell (a childless .tableCell) pads a short body row out
                    // to the header's column count; it is position-less on both sides. Every other
                    // nil range is an unstamped regression.
                    if case .tableCell = node.kind, node.isLeaf {
                        exemptFillerCells += 1
                        continue
                    }
                    failures.append("#\(ex.number) [\(ex.section)] \(node.kind): nil sourceRange; input=\(ex.markdown.debugDescription)")
                    continue
                }
                // A non-nil range is well-ordered by construction: `MarkdownNode.sourceRange` (via
                // StorageView) collapses any start > end to nil, and Swift's half-open Range cannot
                // represent inversion. So an out-of-order range surfaces as nil and is caught above;
                // this restates the requirement's `lowerBound <= upperBound` invariant defensively,
                // in case that upstream contract ever changes.
                if range.lowerBound > range.upperBound {
                    failures.append("#\(ex.number) [\(ex.section)] \(node.kind): inverted range \(range); input=\(ex.markdown.debugDescription)")
                }
            }
        }

        // Fixture sanity: the corpus and the walk must both be substantial, so a vacuous setup
        // (empty corpus, or a walk that never descends into children) fails loudly.
        #expect(totalNodes > 3000)
        // Pin the filler-cell exemption to its verified population (the two padding cells in the
        // GFM tables section). Because an out-of-order range collapses to nil, a childless
        // .tableCell going nil when it should carry a range would otherwise be silently exempted;
        // asserting the exact count makes the ratchet trip if that population ever changes shape,
        // forcing a re-triage against the reference.
        #expect(exemptFillerCells == 2)
        #expect(failures.isEmpty, Comment(rawValue: failures.prefix(25).joined(separator: "\n")))
    }
}
