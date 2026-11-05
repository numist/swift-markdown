/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Adjacent text produced by character escapes, entities and smart punctuation is merged into one text node whose
/// content is a run of the stored segments, with no new segments when the pieces are already adjacent.
@Suite("Merging adjacent text stores few segments")
struct TextMergeSegmentCountTests {

    /// How many segments each further copy of `source` adds to a paragraph of one to five copies separated by spaces.
    private static func segmentsAddedPerCopy(_ source: String, options: MarkdownDocument.ParseOptions) -> [Int] {
        let counts = (1...5).map { copies in
            MarkdownDocument.withParsedDocument(Array(repeating: source, count: copies).joined(separator: " "), options: options) { $0._segmentCount }
        }
        return zip(counts.dropFirst(), counts).map { $0 - $1 }
    }

    /// For one to five copies of `source` in a paragraph, separated by spaces: the number of text nodes, and the number
    /// of stored segments that no text node holds.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    private static func textNodesAndUnheldSegments(_ source: String, options: MarkdownDocument.ParseOptions) -> (textNodes: [Int], unheld: [Int]) {
        var textNodes: [Int] = []
        var unheld: [Int] = []
        for copies in 1...5 {
            MarkdownDocument.withParsedDocument(Array(repeating: source, count: copies).joined(separator: " "), options: options) { doc in
                var nodes = 0
                var held = 0
                func visit(_ node: borrowing MarkdownNode) {
                    switch node.content {
                    case .text(let segments) where node.kind == .text:
                        nodes += 1
                        held += segments.count
                    default:
                        break
                    }
                    node.children.forEach { visit($0) }
                }
                visit(doc.root)
                textNodes.append(nodes)
                unheld.append(doc._segmentCount - held)
            }
        }
        return (textNodes, unheld)
    }

    @Test(arguments: [
        "a &amp; b &lt; c",
        "a\\*b\\*c",
        "a&amp;b&amp;c&amp;d",
        "[a] [b] [c] it's",
        "*a **b *c",
        "a _b *c_ d* e",
    ])
    func segmentsGrowByTheSameCountPerCopy(_ source: String) {
        let added = Self.segmentsAddedPerCopy(source, options: [])
        #expect(added == Array(repeating: added[0], count: 4))
    }

    @Test(arguments: [
        "x ... y ... z",
        "*a* it's b",
    ])
    func smartSegmentsGrowByTheSameCountPerCopy(_ source: String) {
        let added = Self.segmentsAddedPerCopy(source, options: [.smart])
        #expect(added == Array(repeating: added[0], count: 4))
    }

    /// Copies that merge into one text node add segments only to that node.
    @Test(arguments: [
        ("a &amp; b &lt; c", []),
        ("a\\*b\\*c", []),
        ("a&amp;b&amp;c&amp;d", []),
        ("[a] [b] [c] it's", []),
        ("*a **b *c", []),
        ("x ... y ... z", [.smart]),
    ] as [(String, MarkdownDocument.ParseOptions)])
    func mergedCopiesAddSegmentsOnlyToTheirTextNode(_ source: String, _ options: MarkdownDocument.ParseOptions) {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let (textNodes, unheld) = Self.textNodesAndUnheldSegments(source, options: options)
        #expect(textNodes == [1, 1, 1, 1, 1])
        #expect(unheld == Array(repeating: unheld[0], count: 5))
    }
}
