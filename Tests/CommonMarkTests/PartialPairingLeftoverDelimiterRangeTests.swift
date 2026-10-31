/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The delimiters a partially paired run leaves unused remain text (Emphasis and strong emphasis), and that text's
/// source range covers only those delimiters, so it doesn't overlap the emphasis or strong emphasis beside it.
@Suite("Leftover delimiter text source ranges")
struct PartialPairingLeftoverDelimiterRangeTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// Every node's kind, literal text and source range, depth-first.
    private func nodes(in src: String) -> [String] {
        MarkdownDocument.withParsedDocument(src, options: [.sourcePosition]) { doc -> [String] in
            var out: [(kind: MarkdownNode.Kind, text: String?)] = []
            dfsKindsAndText(doc.root, into: &out)
            var ranges: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &ranges)
            return zip(out, ranges).map { node, ranged in
                let range = ranged.range.map { "\($0.lowerBound.line):\($0.lowerBound.column)-\($0.upperBound.line):\($0.upperBound.column)" } ?? "-"
                return "\(node.kind) \(node.text ?? "") \(range)"
            }
        }
    }

    @Test("an unused closing delimiter's text follows the emphasis")
    func leftoverCloser() {
        #expect(nodes(in: "*o**") == [
            "document  1:1-1:5",
            "paragraph  1:1-1:5",
            "emphasis  1:1-1:4",
            "text o 1:2-1:3",
            "text * 1:4-1:5",
        ])
        #expect(nodes(in: "**o***") == [
            "document  1:1-1:7",
            "paragraph  1:1-1:7",
            "strong  1:1-1:6",
            "text o 1:3-1:4",
            "text * 1:6-1:7",
        ])
    }

    @Test("an unused opening delimiter's text precedes the emphasis")
    func leftoverOpener() {
        #expect(nodes(in: "**o*") == [
            "document  1:1-1:5",
            "paragraph  1:1-1:5",
            "text * 1:1-1:2",
            "emphasis  1:2-1:5",
            "text o 1:3-1:4",
        ])
        #expect(nodes(in: "***o**") == [
            "document  1:1-1:7",
            "paragraph  1:1-1:7",
            "text * 1:1-1:2",
            "strong  1:2-1:7",
            "text o 1:4-1:5",
        ])
    }

    @Test("an opening run paired twice leaves text covering its one unused delimiter")
    func openerPairedTwice() {
        #expect(nodes(in: "****a*b**") == [
            "document  1:1-1:10",
            "paragraph  1:1-1:10",
            "text * 1:1-1:2",
            "strong  1:2-1:10",
            "emphasis  1:4-1:7",
            "text a 1:5-1:6",
            "text b 1:7-1:8",
        ])
    }

    /// The run of three closes the first emphasis with its first delimiter and opens the second with its last.
    @Test("a run paired as a closer and then as an opener")
    func closerThenOpener() {
        #expect(nodes(in: "*a***b*") == [
            "document  1:1-1:8",
            "paragraph  1:1-1:8",
            "emphasis  1:1-1:4",
            "text a 1:2-1:3",
            "text * 1:4-1:5",
            "emphasis  1:5-1:8",
            "text b 1:6-1:7",
        ])
    }

    @Test("leftover delimiters in link text")
    func leftoverInLinkText() {
        #expect(nodes(in: "[**o*](u)") == [
            "document  1:1-1:10",
            "paragraph  1:1-1:10",
            "link  1:1-1:10",
            "text * 1:2-1:3",
            "emphasis  1:3-1:6",
            "text o 1:4-1:5",
        ])
    }

    /// Leftover delimiter text merges with the text beside it, and the merged node runs from the first part's start to the last part's end.
    @Test("leftover delimiters merged with adjacent text")
    func leftoverMergedWithText() {
        #expect(nodes(in: "a **o*") == [
            "document  1:1-1:7",
            "paragraph  1:1-1:7",
            "text a * 1:1-1:4",
            "emphasis  1:4-1:7",
            "text o 1:5-1:6",
        ])
        #expect(nodes(in: "*o** b") == [
            "document  1:1-1:7",
            "paragraph  1:1-1:7",
            "emphasis  1:1-1:4",
            "text o 1:2-1:3",
            "text * b 1:4-1:7",
        ])
    }
}
