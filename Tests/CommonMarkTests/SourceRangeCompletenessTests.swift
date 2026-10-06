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
        let audit = try Self.audit(options: Self.options)

        // Fixture sanity: the corpus and the walk must both be substantial, so a vacuous setup
        // (empty corpus, or a walk that never descends into children) fails loudly.
        #expect(audit.totalNodes > 3000)
        // Pin the filler-cell exemption to its verified population (the two padding cells in the
        // GFM tables section). Because an out-of-order range collapses to nil, a childless
        // .tableCell going nil when it should carry a range would otherwise be silently exempted;
        // asserting the exact count makes the ratchet trip if that population ever changes shape,
        // forcing a re-triage against the reference.
        #expect(audit.exemptFillerCells == 2)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// The same ratchet with every `o` in every example replaced by a NUL. Block parsing materializes
    /// NUL-bearing content into the arena (each NUL becomes U+FFFD) instead of taking the zero-copy source
    /// slice, so this covers content that must map back to source through an arena run map: paragraphs,
    /// headings, table cells, and the inlines within them. A letter is replaced rather than a NUL inserted, so
    /// block markers and most inline syntax stay intact.
    @Test("every non-exempt node carries a valid source range when content contains NULs")
    func everyNonExemptNodeWithNULHasValidRange() throws {
        let audit = try Self.audit(options: Self.options) { $0.replacingOccurrences(of: "o", with: "\u{0}") }

        #expect(audit.totalNodes > 3000)
        #expect(audit.exemptFillerCells == 2)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// A NUL is one source byte, as an `o` is, so replacing each `o` with a NUL leaves every node's source range unchanged
    /// wherever it leaves the node tree unchanged: this checks the values, not just the presence, of the ranges
    /// that NUL-bearing content maps back to source through an arena run map.
    @Test("a NUL projects onto its one source byte")
    func nulReplacementPreservesRanges() throws {
        func nodes(_ markdown: String) -> [(kind: String, range: String)] {
            var nodes: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
            MarkdownDocument.withParsedDocument(markdown, options: Self.options) { doc in
                dfsCompleteness(doc.root, into: &nodes)
            }
            return nodes.map { ("\($0.kind)", String(describing: $0.range)) }
        }

        var compared = 0
        var failures: [String] = []
        for ex in try Self.loadSpec() {
            let original = nodes(ex.markdown)
            let withNUL = nodes(ex.markdown.replacingOccurrences(of: "o", with: "\u{0}"))
            // A NUL can change structure (an `o` in an entity or HTML tag name, U+FFFD's emphasis flanking), and then its ranges aren't comparable.
            guard ex.markdown.contains("o"), original.map(\.kind) == withNUL.map(\.kind) else { continue }
            compared += 1
            for (a, b) in zip(original, withNUL) where a.range != b.range {
                failures.append("#\(ex.number) [\(ex.section)] \(a.kind): \(a.range) became \(b.range); input=\(ex.markdown.debugDescription)")
            }
        }

        // Fixture sanity: most examples contain an `o` and keep their structure, so a substitution that broke structure wholesale fails loudly.
        #expect(compared > 500)
        #expect(failures.isEmpty, Comment(rawValue: failures.prefix(25).joined(separator: "\n")))
    }

    /// The same ratchet over inline-only parsing (`.inlineOnly`, and `.preserveWhitespace` which
    /// implies it), where each whole spec example becomes one paragraph of inline content. Each
    /// example also runs with CRLF line endings, which inline-only parsing normalizes through an
    /// arena copy rather than the zero-copy source slice the LF-only corpus takes.
    @Test("every non-exempt node carries a valid source range in inline-only parsing", arguments: [
        MarkdownDocument.ParseOptions.inlineOnly, .preserveWhitespace,
    ], ["\n", "\r\n"])
    func everyNonExemptInlineOnlyNodeHasValidRange(mode: MarkdownDocument.ParseOptions, lineEnding: String) throws {
        let audit = try Self.audit(options: Self.options.union(mode)) { $0.replacingOccurrences(of: "\n", with: lineEnding) }

        // Fixture sanity: every example yields at least a document, a paragraph, and a child.
        #expect(audit.totalNodes > 3000)
        // Inline-only parsing builds no tables, so there are no filler cells to exempt.
        #expect(audit.exemptFillerCells == 0)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// A container to nest every spec example in, by rewriting each of its lines.
    enum Container: String, CaseIterable, Sendable {
        /// Every line prefixed with `> `.
        case blockQuote
        /// The first line prefixed with `- `, the rest indented by two spaces.
        case listItem
        /// The first line prefixed with `> - `, the rest with `>   `.
        case listItemInBlockQuote
        /// Every line prefixed with `>` and a tab.
        case tabAfterBlockQuoteMarker
        /// The first line prefixed with `-` and a tab, the rest indented by a tab.
        case tabIndentedListItem
        /// A `> a` paragraph line first, then the example's first line unprefixed, so it is a lazy continuation of that
        /// paragraph wherever it is paragraph text, and the rest prefixed with `> `. A table's header line is then lazy.
        case lazyFirstLine

        func nest(_ markdown: String) -> String {
            var lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            // The example's final newline ends its last line; it is not a line of its own to prefix.
            let trailingNewline = lines.last == ""
            if trailingNewline { lines.removeLast() }
            let (first, rest): (String, String) = switch self {
            case .blockQuote: ("> ", "> ")
            case .listItem: ("- ", "  ")
            case .listItemInBlockQuote: ("> - ", ">   ")
            case .tabAfterBlockQuoteMarker: (">\t", ">\t")
            case .tabIndentedListItem: ("-\t", "\t")
            case .lazyFirstLine: ("", "> ")
            }
            let nested = lines.enumerated().map { ($0.offset == 0 ? first : rest) + $0.element }
            let lead = self == .lazyFirstLine ? "> a\n" : ""
            return lead + nested.joined(separator: "\n") + (trailingNewline ? "\n" : "")
        }
    }

    /// The ratchet with every spec example nested in each `Container`, in the shipped configuration and with
    /// `.cmarkBugCompatibility`. A nested block's lines aren't contiguous in the source (each carries its container's
    /// prefix), so this covers content that maps back to source line by line: notably the GFM tables section's
    /// tables, whose rows, cells and cell inlines must each be placed on their own source line.
    @Test("every non-exempt node carries a valid source range when nested in a container", arguments: Container.allCases, [
        MarkdownDocument.ParseOptions(), .cmarkBugCompatibility,
    ])
    func everyNonExemptNestedNodeHasValidRange(container: Container, compatibility: MarkdownDocument.ParseOptions) throws {
        let audit = try Self.audit(options: Self.options.union(compatibility), rewrite: container.nest)

        #expect(audit.totalNodes > 3000)
        #expect(audit.exemptFillerCells == 2)
        #expect(audit.failures.isEmpty, Comment(rawValue: audit.failures.prefix(25).joined(separator: "\n")))
    }

    /// Parse every spec example with `options`, its markdown passed through `rewrite`, and collect each
    /// node that lacks a valid source range, skipping the exempt set documented on
    /// `everyNonExemptNodeHasValidRange`.
    private static func audit(options: MarkdownDocument.ParseOptions, rewrite: (String) -> String = { $0 }) throws -> (totalNodes: Int, exemptFillerCells: Int, failures: [String]) {
        let examples = try Self.loadSpec()
        #expect(examples.count > 600)

        var totalNodes = 0
        var exemptFillerCells = 0
        var failures: [String] = []

        for ex in examples {
            var nodes: [(kind: MarkdownNode.Kind, range: Range<MarkdownNode.SourcePosition>?, isLeaf: Bool)] = []
            let markdown = rewrite(ex.markdown)
            MarkdownDocument.withParsedDocument(markdown, options: options) { doc in
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
                    failures.append("#\(ex.number) [\(ex.section)] \(node.kind): nil sourceRange; input=\(markdown.debugDescription)")
                    continue
                }
                // A non-nil range is well-ordered by construction: `MarkdownNode.sourceRange` (via
                // StorageView) collapses any start > end to nil, and Swift's half-open Range cannot
                // represent inversion. So an out-of-order range surfaces as nil and is caught above;
                // this restates the requirement's `lowerBound <= upperBound` invariant defensively,
                // in case that upstream contract ever changes.
                if range.lowerBound > range.upperBound {
                    failures.append("#\(ex.number) [\(ex.section)] \(node.kind): inverted range \(range); input=\(markdown.debugDescription)")
                }
            }
        }
        return (totalNodes, exemptFillerCells, failures)
    }
}
