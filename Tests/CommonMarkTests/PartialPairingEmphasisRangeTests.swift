/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// When a delimiter run is longer than the run it pairs with, the unused delimiters remain text
/// (Emphasis and strong emphasis). The emphasis or strong emphasis source range covers only the
/// delimiters it uses and its content.
@Suite("Emphasis source ranges - partial pairing")
struct PartialPairingEmphasisRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let specOptions: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    /// The source range of the first node of `kind`, in DFS order.
    private func firstRange(of kind: MarkdownNode.Kind, in src: String) -> Range<Pos>? {
        let ranges = MarkdownDocument.withParsedDocument(src, options: Self.specOptions) {
            doc -> [(kind: MarkdownNode.Kind, range: Range<Pos>?)] in
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return ranges
        }
        return ranges.first { $0.kind == kind }?.range
    }

    @Test("partial pairing emphasis range excludes unused delimiters")
    func partialPairingExcludesUnusedDelimiters() {
        let leadingLeftover = firstRange(of: .emphasis, in: "**o*")
        #expect(leadingLeftover?.lowerBound == Pos(line: 1, column: 2))
        #expect(leadingLeftover?.upperBound == Pos(line: 1, column: 5))

        let trailingLeftover = firstRange(of: .emphasis, in: "*o**")
        #expect(trailingLeftover?.lowerBound == Pos(line: 1, column: 1))
        #expect(trailingLeftover?.upperBound == Pos(line: 1, column: 4))

        // The strong emphasis uses the inner two delimiters of each run, the emphasis the outer one.
        let outer = firstRange(of: .emphasis, in: "***o***")
        #expect(outer?.lowerBound == Pos(line: 1, column: 1))
        #expect(outer?.upperBound == Pos(line: 1, column: 8))
        let inner = firstRange(of: .strong, in: "***o***")
        #expect(inner?.lowerBound == Pos(line: 1, column: 2))
        #expect(inner?.upperBound == Pos(line: 1, column: 7))
    }
}
