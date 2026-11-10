/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// List items nest to any depth (List items), so every list marker on a line opens a list in the item the marker
/// before it opened, below any number of block quotes.
///
/// The content after each marker in such a line begins a block, so the rest of the line can be a thematic break
/// (Thematic breaks), and tab stops count from the line's first column however deep the marker is (Tabs).
@Suite("Deep list nesting")
struct DeepListNestingTests {

    struct Node: Equatable, CustomStringConvertible {
        let kind: String
        var literal: String? = nil
        var range: String? = nil

        var description: String {
            kind + (literal.map { " \($0.debugDescription)" } ?? "") + (range.map { " @\($0)" } ?? "")
        }
    }

    /// The root and each node's only child down to a leaf, kinds as `TreeDump.describe` gives them, or `nil` when a
    /// node has a sibling.
    private static func chain(_ markdown: String, options: MarkdownDocument.ParseOptions = []) -> [Node]? {
        MarkdownDocument.withParsedDocument(markdown, options: options) { doc -> [Node]? in
            var nodes: [Node] = []
            var node = doc.root
            while true {
                nodes.append(Node(kind: TreeDump.describe(node.kind), literal: node.literal(), range: node.sourceRange.map {
                    "\($0.lowerBound.line):\($0.lowerBound.column)-\($0.upperBound.line):\($0.upperBound.column)"
                }))
                if node.next != nil {
                    return nil
                }
                guard let child = node.firstChild else {
                    return nodes
                }
                node = child
            }
        }
    }

    private static func nodes(_ kinds: [String], repeated count: Int) -> [Node] {
        Array(repeating: kinds.map { Node(kind: $0) }, count: count).flatMap { $0 }
    }

    private static let document = [Node(kind: "document")]
    private static let hyphenItems = ["list bullet '-' tight", "item"]

    @Test
    func bulletListBelowBlockQuotes() {
        #expect(Self.chain(String(repeating: ">", count: 150) + "- ")
            == Self.document + Self.nodes(["block_quote"], repeated: 150) + Self.nodes(Self.hyphenItems, repeated: 1))
    }

    @Test
    func orderedListBelowBlockQuotes() {
        #expect(Self.chain(String(repeating: ">", count: 150) + "1. ")
            == Self.document + Self.nodes(["block_quote"], repeated: 150)
                + Self.nodes(["list ordered start=1 delim=period tight", "item"], repeated: 1))
    }

    @Test(arguments: [
        ("- ", "list bullet '-' tight"),
        ("+ ", "list bullet '+' tight"),
        ("* ", "list bullet '*' tight"),
        ("-\t", "list bullet '-' tight"),
        ("1. ", "list ordered start=1 delim=period tight"),
        ("1.\t", "list ordered start=1 delim=period tight"),
        ("10) ", "list ordered start=10 delim=paren tight"),
    ])
    func markersOnOneLine(marker: String, list: String) {
        #expect(Self.chain(String(repeating: marker, count: 150) + "x")
            == Self.document + Self.nodes([list, "item"], repeated: 150)
                + [Node(kind: "paragraph"), Node(kind: "text", literal: "x")])
    }

    @Test
    func alternatingBulletMarkers() {
        #expect(Self.chain(String(repeating: "* - ", count: 75) + "x")
            == Self.document + Self.nodes(["list bullet '*' tight", "item", "list bullet '-' tight", "item"], repeated: 75)
                + [Node(kind: "paragraph"), Node(kind: "text", literal: "x")])
    }

    @Test
    func blockQuoteAfterEachMarker() {
        #expect(Self.chain(String(repeating: "- > ", count: 150) + "x")
            == Self.document + Self.nodes(["list bullet '-' tight", "item", "block_quote"], repeated: 150)
                + [Node(kind: "paragraph"), Node(kind: "text", literal: "x")])
    }

    @Test
    func listMarkerAfterEachBlockQuote() {
        #expect(Self.chain(String(repeating: "> - ", count: 150) + "x")
            == Self.document + Self.nodes(["block_quote", "list bullet '-' tight", "item"], repeated: 150)
                + [Node(kind: "paragraph"), Node(kind: "text", literal: "x")])
    }

    /// Each list and item starts at its marker's byte, however many columns the tabs before it span.
    @Test
    func markersSeparatedByTabsBeginAtTheirBytes() {
        #expect(Self.chain(String(repeating: "-\t", count: 150) + "x", options: .sourcePosition)
            == [Node(kind: "document", range: "1:1-1:302")]
                + (0..<150).flatMap { marker in
                    Self.hyphenItems.map { Node(kind: $0, range: "1:\(2 * marker + 1)-1:302") }
                }
                + [
                    Node(kind: "paragraph", range: "1:301-1:302"),
                    Node(kind: "text", literal: "x", range: "1:301-1:302"),
                ])
    }

    /// After 150 two-column markers, `12.` ends at column 303 and the tab after it spans one column, so with two spaces
    /// the item's content is three columns in: a paragraph.
    @Test
    func tabAfterDeepMarkerReachingItsStopInOneColumn() {
        #expect(Self.chain(String(repeating: "- ", count: 150) + "12.\t  z")
            == Self.document + Self.nodes(Self.hyphenItems, repeated: 150)
                + Self.nodes(["list ordered start=12 delim=period tight", "item"], repeated: 1)
                + [Node(kind: "paragraph"), Node(kind: "text", literal: "z")])
    }

    /// After 151 two-column markers, `12.` ends at column 305 and the tab after it spans three columns, so with two
    /// spaces the content is five columns in: one column is the marker's padding, and the other four begin an indented
    /// code block.
    @Test
    func tabAfterDeepMarkerReachingItsStopInThreeColumns() {
        #expect(Self.chain(String(repeating: "- ", count: 151) + "12.\t  z")
            == Self.document + Self.nodes(Self.hyphenItems, repeated: 151)
                + Self.nodes(["list ordered start=12 delim=period tight", "item"], repeated: 1)
                + [Node(kind: "code_block indented fence=none length=0 offset=0", literal: "z\n")])
    }

    @Test(arguments: ["* * *", "*\t*\t*", "_ _ _", "***"])
    func thematicBreakInDeepItem(tail: String) {
        #expect(Self.chain(String(repeating: "- ", count: 150) + tail)
            == Self.document + Self.nodes(Self.hyphenItems, repeated: 150) + [Node(kind: "thematic_break")])
    }

    @Test
    func thematicBreakAfterTabSeparatedMarkers() {
        #expect(Self.chain(String(repeating: "-\t", count: 150) + "*\t*\t*")
            == Self.document + Self.nodes(Self.hyphenItems, repeated: 150) + [Node(kind: "thematic_break")])
    }

    /// The last `*` is followed by three `-`, which are a thematic break in the item it opens.
    @Test
    func thematicBreakAfterAlternatingMarkers() {
        #expect(Self.chain(String(repeating: "* - ", count: 75) + "- -")
            == Self.document + Self.nodes(["list bullet '*' tight", "item", "list bullet '-' tight", "item"], repeated: 74)
                + Self.nodes(["list bullet '*' tight", "item"], repeated: 1) + [Node(kind: "thematic_break")])
    }

    @Test
    func lineOfHyphenMarkersIsThematicBreak() {
        #expect(Self.chain(String(repeating: "- ", count: 150) + "-") == Self.document + [Node(kind: "thematic_break")])
    }

    @Test
    func hyphensBeforeTextAreMarkers() {
        #expect(Self.chain(String(repeating: "- ", count: 150) + "- - x")
            == Self.document + Self.nodes(Self.hyphenItems, repeated: 152)
                + [Node(kind: "paragraph"), Node(kind: "text", literal: "x")])
    }

    /// Two `*` are too few for a thematic break: each opens a list, the second's item empty.
    @Test
    func twoAsterisksAfterDeepMarkersAreMarkers() {
        #expect(Self.chain(String(repeating: "- ", count: 150) + "* *")
            == Self.document + Self.nodes(Self.hyphenItems, repeated: 150)
                + Self.nodes(["list bullet '*' tight", "item"], repeated: 2))
    }

    @Test
    func checkboxInDeepItem() {
        #expect(Self.chain(String(repeating: "- ", count: 150) + "[ ] x", options: .tasklist)
            == Self.document + Self.nodes(Self.hyphenItems, repeated: 149)
                + Self.nodes(["list bullet '-' tight", "tasklist unchecked"], repeated: 1)
                + [Node(kind: "paragraph"), Node(kind: "text", literal: "x")])
    }
}
