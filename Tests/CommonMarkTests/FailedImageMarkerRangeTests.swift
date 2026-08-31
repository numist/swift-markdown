/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Materialize the literal of the first `.text` node in DFS order, or nil if there is none.
// File-scope + `borrowing MarkdownNode` for the noncopyable-borrow rules (see SourcePositionTests.dfsRanges).
@available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
internal func firstTextLiteral(_ node: borrowing MarkdownNode) -> String? {
    switch node.content {
    case .text(let segments):
        var joined = ""
        segments.forEach { span in joined += String(copying: span) }
        return joined
    default:
        var found: String? = nil
        node.children.forEach { child in
            if found == nil { found = firstTextLiteral(child) }
        }
        return found
    }
}

/// A failed image marker `![` at the start of a text run keeps its full literal AND its columns.
///
/// When `![` opens an image that never resolves (no matching reference definition, no inline
/// destination), the `![` collapses into literal text. The resulting text node's range must cover
/// its whole literal, starting at the `!` - not after the `![`, which would leave the range and
/// literal inconsistent. This is the spec-correct default (cmark-gfm stamps `@1:1`); the
/// `.cmarkBugCompatibility` flag is not involved. The `imgstart-*` fuzzer regression pairs cover
/// the flag-on surface; this is the flag-off guardrail.
@Suite("Failed image-marker literal source range (spec-correct)")
struct FailedImageMarkerRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped configuration: source positions on, cmark bug-compatibility deliberately OFF.
    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    @Test("failed `![` image marker keeps its full literal and starts at the `!` column")
    func failedImageMarkerStartsAtBang() throws {
        // `![foo]` has no matching reference definition, so the `![` never forms an image and the
        // whole run is literal text. cmark-gfm reports one text node `![foo]` @1:1-1:7 (6 bytes,
        // half-open end at col 7). The bug stamped the run starting at col 3 (after the `![`).
        try MarkdownDocument.withParsedDocument("![foo]", options: Self.specOptions) { doc in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)

            let texts = ranges.filter { $0.kind == .text }
            #expect(texts.count == 1, "the failed `![` must consolidate into a single text run")
            let range = try #require(texts.first?.range)
            #expect(range.lowerBound == Pos(line: 1, column: 1))   // the `!`, not the `f` after `![`
            #expect(range.upperBound == Pos(line: 1, column: 7))   // just past the `]` (6 bytes)

            // The single run's literal is the whole `![foo]`, proving the range covers the full text.
            if #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
                #expect(firstTextLiteral(doc.root) == "![foo]")
            }
        }
    }
}
