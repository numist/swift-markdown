/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// Nested block-quote markers separated by raw tabs, on a line whose tabs reach block parsing unexpanded
/// because the previous line left a fenced code block open.
///
/// Ground truth is cmark-gfm, whose `S_advance_offset(..., columns: true)` (blocks.c) consumes a tab in
/// columns: the optional column after `>` fully consumes a tab that ends one column later (a tab starting
/// at column 3 mod 4) and only partially consumes a wider one. Every tab stop, depth, and marker spacing
/// must nest and strip indentation exactly as the same line would parse on its own. The expected trees
/// follow CommonMark's tab-stop rules, which cmark implements here, so both flag states must agree.
/// Position-free compare surface.
class BlockQuoteTabColumnMatrixTests: XCTestCase {
    private static let listFence = "Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ CodeBlock language: none\n\n"

    private enum Leaf {
        case none
        case paragraph(String)
        case code(String)
    }

    /// `depth` nested block quotes under `head`, the innermost holding `leaf`.
    private func quotes(_ depth: Int, _ leaf: Leaf, head: String = listFence) -> String {
        var lines: [String] = []
        for level in 0..<depth {
            lines.append(String(repeating: " ", count: 3 * level) + "└─ BlockQuote")
        }
        let pad = String(repeating: " ", count: 3 * depth)
        switch leaf {
        case .none:
            break
        case .paragraph(let text):
            lines.append(pad + "└─ Paragraph")
            lines.append(pad + "   └─ Text \"\(text)\"")
        case .code(let literal):
            lines.append(pad + "└─ CodeBlock language: none")
            lines.append(pad + "   " + literal)
        }
        return head + lines.joined(separator: "\n")
    }

    private func assertSurface(_ expected: String, _ markdown: String, file: StaticString = #filePath, line: UInt = #line) {
        for flag in [true, false] {
            var options = ParseOptions(rawValue: 0)
            if flag { options.insert(.cmarkBugCompatibility) }
            let actual = Document(parsing: markdown, options: options).debugDescription(options: [])
            XCTAssertEqual(expected, actual, "cmarkBugCompatibility: \(flag), input: \(markdown.debugDescription)", file: file, line: line)
        }
    }

    /// `>`×k TAB `>`: the tab after the k-th marker is consumed (fully at k ≡ 3 mod 4, partially
    /// otherwise), leaving the final `>` within three columns, so it always opens quote k+1.
    func testTabBeforeMarkerAtEveryTabStop() {
        for k in 1...8 {
            assertSurface(quotes(k + 1, .none), "- ```\n" + String(repeating: ">", count: k) + "\t>")
        }
    }

    /// Spaced markers put the tab at other columns: `> >` puts it at column 3, `> > >` at column 5.
    func testSpacedMarkersThenTabBeforeMarker() {
        assertSurface(quotes(3, .none), "- ```\n> >\t>")
        assertSurface(quotes(4, .none), "- ```\n> > >\t>")
        assertSurface(quotes(4, .none), "- ```\n>> >\t>")
        assertSurface(quotes(3, .none), "- ```\n >>\t>")
        assertSurface(quotes(3, .none), "- ```\n>  >\t>")
    }

    /// `>`×k TAB `x`: the tab is the marker's optional column; `x` is paragraph content.
    func testTabBeforeParagraphContent() {
        for k in 1...5 {
            assertSurface(quotes(k, .paragraph("x")), "- ```\n" + String(repeating: ">", count: k) + "\tx")
        }
    }

    /// `>`×k TAB 4 spaces `x`: indented code. The four code-indent columns are stripped from the column
    /// the marker's optional column reached, so the tab's remaining columns (if any) count toward them
    /// and the unstripped spaces remain content: k=1 → 2 left, k=2 → 1, k=3 → 0 (tab fully consumed),
    /// k=4 → 3, k=5 → 2.
    func testTabThenIndentedCodeAtEveryTabStop() {
        let leftover = [1: "  x", 2: " x", 3: "x", 4: "   x", 5: "  x"]
        for k in 1...5 {
            assertSurface(quotes(k, .code(leftover[k]!)), "- ```\n" + String(repeating: ">", count: k) + "\t    x")
        }
    }

    /// Two tabs after the markers: indent reaches four columns, so the rest is indented code whose
    /// content keeps the second tab's unconsumed columns (as spaces when that tab is split).
    func testTwoTabsBeforeMarker() {
        assertSurface(quotes(1, .code("  >")), "- ```\n>\t\t>")
        assertSurface(quotes(3, .code(">")), "- ```\n>>>\t\t>")
    }

    /// Continuation markers of already-open quotes on a fenced-code body line: a quote whose `>` follows
    /// a tab its parent's optional column partially consumed measures its indent from that column.
    func testContinuationMarkerAfterPartiallyConsumedTab() {
        assertSurface(quotes(2, .code("x"), head: "Document\n"), "> > ```\n>\t>x")
        assertSurface(quotes(2, .code("x"), head: "Document\n"), "> > ```\n>\t> x")
        // Control: a paragraph line has its prefix tabs expanded before block parsing.
        assertSurface("Document\n└─ BlockQuote\n   └─ BlockQuote\n      └─ Paragraph\n         ├─ Text \"a\"\n         ├─ SoftBreak\n         └─ Text \"x\"", "> > a\n>\t> x")
    }

    /// A continuation marker after a tab its parent's optional column fully consumed (column 3).
    func testContinuationMarkerAfterFullyConsumedTab() {
        assertSurface(quotes(4, .code("x"), head: "Document\n"), ">>>> ```\n>>>\t>x")
        assertSurface(quotes(3, .code("\tx"), head: "Document\n"), ">>> ```\n>>>\t\tx")
    }

    /// A list item's continuation indent after a quote marker is measured in columns from the column
    /// that marker reached: a tab there spans only to the next tab stop (two columns from column 2), so
    /// it falls short of the `1. ` item's three-column content indent and the item closes.
    func testItemContinuationIndentAfterQuoteMarker() {
        let closed = "Document\n└─ BlockQuote\n   ├─ OrderedList\n   │  └─ ListItem\n   │     └─ CodeBlock language: none\n\n   └─ Paragraph\n      └─ Text \"x\""
        assertSurface(closed, "> 1. ```\n> \tx")
        assertSurface(closed, "> 1. ```\n>\tx")
    }

    /// A tab that exactly reaches a `- ` item's content column is fully consumed by the item, so a
    /// following `>` continues the item's nested quote.
    func testItemContinuationConsumesTabThenQuoteMarker() {
        let continued = "Document\n└─ BlockQuote\n   └─ UnorderedList\n      └─ ListItem\n         └─ BlockQuote\n            └─ CodeBlock language: none\n               x"
        assertSurface(continued, "> - > ```\n>\t>x")
        assertSurface(continued, "> - > ```\n> \t>x")
    }
}
