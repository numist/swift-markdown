/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Lines that open or continue many nested block quotes (Block quotes).
///
/// Each `>` is placed by its column, which a tab before it makes depend on the whole line before it (Tabs): after `>>`
/// and a tab, two more spaces leave a `>` three columns in, still a block quote marker, while after `>` and a tab they
/// leave it four columns in, the start of an indented code block. A line of 40,000 nested block quotes, separated by
/// tabs or not, and a later line continuing them all, parse well within the time limit.
@Suite("Lines of nested block quote markers")
struct NestedBlockQuoteMarkerLineTests {

    struct Node: Equatable, CustomStringConvertible {
        let kind: MarkdownNode.Kind
        var literal: String? = nil
        var range: String? = nil

        var description: String {
            "\(kind)" + (literal.map { " \"\($0)\"" } ?? "") + (range.map { " @\($0)" } ?? "")
        }
    }

    /// The number of block quotes nested from the root's first child, then the innermost block quote, its first child
    /// and that child's children.
    private static func nesting(_ markdown: String, options: MarkdownDocument.ParseOptions) -> (quotes: Int, innermost: [Node]) {
        MarkdownDocument.withParsedDocument(markdown, options: options) { doc in
            func node(_ node: borrowing MarkdownNode) -> Node {
                Node(kind: node.kind, literal: node.literal(), range: node.sourceRange.map {
                    "\($0.lowerBound.line):\($0.lowerBound.column)-\($0.upperBound.line):\($0.upperBound.column)"
                })
            }
            var quotes = 0
            var innermostQuote: Node?
            var innermost: [Node] = []
            var current = doc.root.firstChild
            while let candidate = current {
                guard case .blockQuote = candidate.kind else {
                    innermost.append(node(candidate))
                    candidate.children.forEach { innermost.append(node($0)) }
                    break
                }
                quotes += 1
                innermostQuote = node(candidate)
                current = candidate.firstChild
            }
            return (quotes, (innermostQuote.map { [$0] } ?? []) + innermost)
        }
    }

    @Test
    func markerThreeColumnsAfterTabIsBlockQuote() {
        #expect(TreeDump.dump(">>\t  > a", options: []) == """
            document
              block_quote
                block_quote
                  block_quote
                    paragraph
                      text "a"

            """)
    }

    @Test
    func markerFourColumnsAfterTabIsIndentedCode() {
        #expect(TreeDump.dump(">\t  > a", options: []) == """
            document
              block_quote
                code_block "" "> a\\n"

            """)
    }

    /// A block quote begins at its `>`, whatever the tab before it expands to.
    @Test
    func blockQuotesAfterTabsBeginAtMarkers() {
        #expect(TreeDump.dump(">\t>\t> a", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-1:8
              block_quote @1:1-1:8
                block_quote @1:3-1:8
                  block_quote @1:5-1:8
                    paragraph @1:7-1:8
                      text "a" @1:7-1:8

            """)
    }

    @Test(.timeLimit(.minutes(1)))
    func blockQuotesOpeningOnOneLine() {
        let nesting = Self.nesting(String(repeating: ">", count: 40_000) + " a", options: [])
        #expect(nesting.quotes == 40_000)
        #expect(nesting.innermost == [Node(kind: .blockQuote), Node(kind: .paragraph), Node(kind: .text, literal: "a")])
    }

    @Test(.timeLimit(.minutes(1)))
    func blockQuotesContinuingOnLaterLine() {
        let markers = String(repeating: "> ", count: 40_000)
        let nesting = Self.nesting(markers + "a\n" + markers + "b", options: [])
        #expect(nesting.quotes == 40_000)
        #expect(nesting.innermost == [
            Node(kind: .blockQuote), Node(kind: .paragraph),
            Node(kind: .text, literal: "a"), Node(kind: .softBreak), Node(kind: .text, literal: "b"),
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func blockQuotesSeparatedByTabs() {
        let nesting = Self.nesting(String(repeating: ">\t", count: 40_000) + "a", options: [])
        #expect(nesting.quotes == 40_000)
        #expect(nesting.innermost == [Node(kind: .blockQuote), Node(kind: .paragraph), Node(kind: .text, literal: "a")])
    }

    @Test(.timeLimit(.minutes(1)))
    func blockQuotesSeparatedByTabsBeginAtMarkers() {
        let nesting = Self.nesting(String(repeating: ">\t", count: 40_000) + "a", options: .sourcePosition)
        #expect(nesting.quotes == 40_000)
        #expect(nesting.innermost == [
            Node(kind: .blockQuote, range: "1:79999-1:80002"),
            Node(kind: .paragraph, range: "1:80001-1:80002"),
            Node(kind: .text, literal: "a", range: "1:80001-1:80002"),
        ])
    }
}
