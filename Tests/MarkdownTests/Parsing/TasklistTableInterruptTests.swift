/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @testable import Markdown
import XCTest

/// A task item whose first paragraph is split by a table keeps its checkbox.
///
/// Ground truth is cmark-gfm. In the minimized fuzzer artifact the item `- [x] |` continues lazily with a
/// U+0001 line, which becomes the header row of a table opened by the `-|` delimiter row; the paragraph
/// left behind is `[x] |`. cmark recognizes the `[x]` checkbox (item `checkbox: [x]`, paragraph `|`).
/// Position-free compare surface.
class TasklistTableInterruptTests: XCTestCase {
    // The minimized artifact's markdown: "- [x] |" LF 0x01 LF "  -|" (options byte 0x7c).
    private static let bytes: [UInt8] = [
        0x2d, 0x20, 0x5b, 0x78, 0x5d, 0x20, 0x7c, 0x0a, 0x01, 0x0a, 0x20, 0x20, 0x2d, 0x7c,
    ]
    private static let fuzzedBits = ParseOptions(rawValue: UInt(0x7c & 0b11011111))

    private func surface(cmarkBugCompatible: Bool) -> String {
        var options = Self.fuzzedBits
        if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
        return Document(parsing: String(decoding: Self.bytes, as: UTF8.self), options: options)
            .debugDescription(options: [])
    }

    func testCheckboxSurvivesTableSplittingParagraph() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      ├─ Paragraph\n      │  └─ Text \"|\"\n      └─ Table alignments: |-|\n         ├─ Head\n         │  └─ Cell\n         │     └─ Text \"\u{1}\"\n         └─ Body"
        XCTAssertEqual(expected, surface(cmarkBugCompatible: true))
    }
    /// Every compare-surface variant a probe must agree on: both `.cmarkBugCompatibility` states, with
    /// source positions both off (the fuzzed `0x7c` options) and on (a different pending-content
    /// representation reaches the table split).
    private func surfaces(_ markdown: String) -> [String] {
        var result: [String] = []
        for cmarkBugCompatible in [true, false] {
            for positions in [false, true] {
                var options = Self.fuzzedBits
                if cmarkBugCompatible { options.insert(.cmarkBugCompatibility) }
                if positions { options.remove(.disableSourcePosOpts) }
                result.append(Document(parsing: markdown, options: options).debugDescription(options: []))
            }
        }
        return result
    }

    private func assertSurface(_ markdown: String, _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        for actual in surfaces(markdown) {
            XCTAssertEqual(expected, actual, file: file, line: line)
        }
    }

    /// A one-cell table (head `head`, optional body rows) as the item's child at `indent`.
    private static func table(head: String, body: [String] = [], indent: String) -> [String] {
        var lines = [
            "\(indent)└─ Table alignments: |-|",
            "\(indent)   ├─ Head",
            "\(indent)   │  └─ Cell",
            "\(indent)   │     └─ Text \"\(head)\"",
            "\(indent)   └─ Body",
        ]
        for (i, row) in body.enumerated() {
            let last = i == body.count - 1
            lines += [
                "\(indent)      \(last ? "└" : "├")─ Row",
                "\(indent)      \(last ? " " : "│")  └─ Cell",
                "\(indent)      \(last ? " " : "│")     └─ Text \"\(row)\"",
            ]
        }
        return lines
    }

    /// `Document > UnorderedList > ListItem checkbox > [Paragraph(text lines)] + one-cell Table`.
    private static func taskItemWithTable(checkbox: String, paragraph: [String], head: String, body: [String] = []) -> String {
        var lines = ["Document", "└─ UnorderedList", "   └─ ListItem checkbox: \(checkbox)", "      ├─ Paragraph"]
        for (i, text) in paragraph.enumerated() {
            if i > 0 { lines.append("      │  ├─ SoftBreak") }
            lines.append("      │  \(i == paragraph.count - 1 ? "└" : "├")─ Text \"\(text)\"")
        }
        return (lines + table(head: head, body: body, indent: "      ")).joined(separator: "\n")
    }

    // MARK: - A table splitting a task item's first paragraph

    func testFuzzedArtifactInEveryVariant() {
        assertSurface("- [x] |\n\u{1}\n  -|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["|"], head: "\u{1}"))
    }

    func testIndentedHeaderAndDelimiter() {
        assertSurface("- [x] a\n  b|\n  -|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["a"], head: "b"))
    }

    func testLazyHeaderIndentedDelimiter() {
        assertSurface("- [x] a\nb\n  |-|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["a"], head: "b"))
    }

    func testPipedTableWithBodyRow() {
        assertSurface("* [x] a\n  |b|\n  |-|\n  |c|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["a"], head: "b", body: ["c"]))
    }

    func testMultiLinePrecedingParagraph() {
        assertSurface("- [x] a\n  b\n  c|\n  -|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["a", "b"], head: "c"))
    }

    func testCRLFLineEndings() {
        assertSurface("- [x] a\r\n  b|\r\n  -|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["a"], head: "b"))
    }

    func testTabIndentedHeader() {
        assertSurface("- [x] a\n\tb|\n  -|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["a"], head: "b"))
    }

    /// The split-off paragraph is never finalized in cmark (`try_inserting_table_header_paragraph`), so a
    /// ref-def-shaped remainder after the checkbox stays literal text.
    func testRefDefShapedPrecedingParagraphStaysText() {
        assertSurface("- [x] [a]: /u\n  b|\n  -|", Self.taskItemWithTable(checkbox: "[x]", paragraph: ["[a]: /u"], head: "b"))
    }

    func testNestedTaskItem() {
        let expected = [
            "Document",
            "└─ UnorderedList",
            "   └─ ListItem",
            "      ├─ Paragraph",
            "      │  └─ Text \"a\"",
            "      └─ UnorderedList",
            "         └─ ListItem checkbox: [ ]",
            "            ├─ Paragraph",
            "            │  └─ Text \"b\"",
        ] + Self.table(head: "c", indent: "            ")
        assertSurface("- a\n  - [ ] b\n    c|\n    -|", expected.joined(separator: "\n"))
    }

    /// cmark sets the checked state by `strstr` over the opening line (`open_tasklist_item`), a quirk
    /// reproduced only under `.cmarkBugCompatibility`; the spec-correct state comes from the leading token.
    func testCheckedStateQuirkOnSplitOffLine() {
        let markdown = "- [ ] a [x]\n  b|\n  -|"
        let flagOn = Self.taskItemWithTable(checkbox: "[x]", paragraph: ["a [x]"], head: "b")
        let flagOff = Self.taskItemWithTable(checkbox: "[ ]", paragraph: ["a [x]"], head: "b")
        let actual = surfaces(markdown)
        XCTAssertEqual([flagOn, flagOn, flagOff, flagOff], actual)
    }

    /// The split-off paragraph's range and inlines start after the checkbox, on both the contiguous path
    /// (`- [x] a` / `  b|`) and the re-indented segment path (CRLF-joined lines).
    func testSplitOffParagraphPositions() {
        func paragraphLines(_ markdown: String) -> [String] {
            let dump = Document(parsing: markdown, options: []).debugDescription(options: [.printSourceLocations])
            return dump.split(separator: "\n").map(String.init).filter { $0.contains("Paragraph") || $0.contains("Text @") }
        }
        XCTAssertEqual([
            "      ├─ Paragraph @1:7-1:8",
            "      │  └─ Text @1:7-1:8 \"a\"",
        ], paragraphLines("- [x] a\n  b|\n  -|"))
        XCTAssertEqual([
            "      ├─ Paragraph @1:7-2:4",
            "      │  ├─ Text @1:7-1:8 \"a\"",
            "      │  └─ Text @2:3-2:4 \"b\"",
        ], paragraphLines("- [x] a\r\n  b\r\n  c|\r\n  -|"))
    }

    // MARK: - A setext underline after a task item's ref-def line

    /// cmark strips the checkbox at item open, so the setext scan's ref-def resolution sees `[a]: /u`,
    /// consumes it, and the heading holds only the remaining line.
    func testSetextHeadingAfterTaskItemRefDef() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Heading level: 1\n         └─ Text \"b\""
        assertSurface("- [x] [a]: /u\n  b\n  ===", expected)
    }

    /// Nothing but a ref-def precedes the underline, so no heading forms: cmark keeps the paragraph open
    /// and absorbs `===` as text; the spec-correct default redispatches `===` as a new paragraph. Both
    /// surface as a paragraph `===`.
    func testSetextUnderlineAfterTaskItemRefDefOnly() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         └─ Text \"===\""
        assertSurface("- [x] [a]: /u\n  ===", expected)
    }

    // MARK: - Guards (already matching cmark)

    func testLazyDelimiterRowStaysParagraph() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ Paragraph\n         ├─ Text \"a\"\n         ├─ SoftBreak\n         ├─ Text \"b|c\"\n         ├─ SoftBreak\n         └─ Text \"-|-\""
        assertSurface("- [x] a\nb|c\n-|-", expected)
    }

    func testCheckboxAfterBlockQuoteMarkerStaysLiteral() {
        let expected = [
            "Document",
            "└─ BlockQuote",
            "   └─ UnorderedList",
            "      └─ ListItem",
            "         ├─ Paragraph",
            "         │  └─ Text \"[x] a\"",
        ] + Self.table(head: "b", indent: "         ")
        assertSurface("> - [x] a\n>   b|\n>   -|", expected.joined(separator: "\n"))
    }

    func testTableIsWholeFirstParagraph() {
        let expected = ["Document", "└─ UnorderedList", "   └─ ListItem checkbox: [x]"] + Self.table(head: "a", indent: "      ")
        assertSurface("- [x] |a|\n  |-|", expected.joined(separator: "\n"))
    }

    func testTableAfterBlankTaskLine() {
        let expected = ["Document", "└─ UnorderedList", "   └─ ListItem checkbox: [x]"] + Self.table(head: "a", indent: "      ")
        assertSurface("- [x] \n  a|\n  -|", expected.joined(separator: "\n"))
    }

    func testSetextHeadingKeepsCheckbox() {
        let expected = "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [ ]\n      └─ Heading level: 2\n         ├─ Text \"a\"\n         ├─ SoftBreak\n         └─ Text \"b\""
        assertSurface("- [ ] a\n  b\n  ---", expected)
    }

    func testRefDefOnlyTaskItem() {
        assertSurface("- [x] [a]: /u", "Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]")
    }
}
