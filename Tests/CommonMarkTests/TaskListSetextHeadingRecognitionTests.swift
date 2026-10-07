/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// GFM task-list checkbox recognition is anchored to the list item's OPENING line and is independent of
/// what that item's content later becomes. cmark-gfm recognizes and strips the checkbox in
/// `open_tasklist_item` (`extensions/tasklist.c`), an open-block callback that fires as the ITEM opens:
/// it scans the opening line (`scan_tasklist`), advances past the checkbox, and records the checked
/// state — all before the paragraph body is built. When a later line is a setext underline, the item's
/// content becomes a heading, but the checkbox was already consumed at open time, so it stays recognized
/// and its marker never appears in the heading text.
///
/// The rewrite consumes the checkbox at finalize (`runParagraphMatchers`, #65), which fires only for the
/// `.paragraph` finalize path. A line-anchored task item whose first-child paragraph is transformed into
/// a setext heading (`processLine` PHASE 2c) never reaches that path, so before this fix the checkbox was
/// neither reflected in the item's `.item(checked:)` state nor stripped from the heading text.
///
/// These assertions parse without `.sourcePosition`.
///
/// Regression for the fuzzer divergence minimized from `- [ ] v\n  -` (option-independent).
@Suite("GFM task-list checkbox recognition when the item content is a setext heading")
struct TaskListSetextHeadingRecognitionTests {

    private static let flagOff: MarkdownDocument.ParseOptions = [.tasklist]

    /// A flattened view of the first list item and the first heading in a parsed document.
    private struct Shape {
        /// `nil` = no `.item` node at all; `.some(nil)` = an ordinary bullet item; `.some(x)` = a task
        /// item with checked state `x`.
        var itemChecked: Bool??
        /// The first heading's level, or `nil` if the tree has no heading.
        var headingLevel: Int?
        /// The first heading's concatenated text literals, or `nil` if the tree has no heading.
        var headingText: String?
        /// Every text literal in the document, in DFS order — used to prove the marker was stripped.
        var allTexts: [String]
    }

    private func shape(
        _ source: String, options: MarkdownDocument.ParseOptions
    ) -> Shape {
        MarkdownDocument.withParsedDocument(source, options: options) { doc -> Shape in
            var result = Shape(itemChecked: nil, headingLevel: nil, headingText: nil, allTexts: [])
            // Collect a heading's own text (its direct/indirect text descendants) once we enter it.
            func collectText(_ node: borrowing MarkdownNode, into out: inout String) {
                if node.kind == .text, let lit = node.literal() {
                    out += lit
                }
                node.children.forEach { collectText($0, into: &out) }
            }
            func walk(_ node: borrowing MarkdownNode) {
                if case .item(let checked) = node.kind, result.itemChecked == nil {
                    result.itemChecked = .some(checked)
                }
                if case .heading(let level) = node.kind, result.headingLevel == nil {
                    result.headingLevel = level
                    var text = ""
                    collectText(node, into: &text)
                    result.headingText = text
                }
                if node.kind == .text, let lit = node.literal() {
                    result.allTexts.append(lit)
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return result
        }
    }

    // MARK: - Shipped parser

    /// A task list item's first block must be a paragraph (spec "Task list items (extension)"), so an item
    /// whose first block is a setext heading is an ordinary item and the heading keeps `[ ]` as text.
    @Test("`- [ ] v\\n  -` is an ordinary item with a level-2 heading `[ ] v`")
    func taskItemSetextHeadingNotRecognizedFlagOff() throws {
        let shape = shape("- [ ] v\n  -", options: Self.flagOff)
        let checked = try #require(shape.itemChecked, "no list item parsed")
        try #require(shape.headingLevel != nil, "no heading parsed")
        #expect(checked == nil)
        #expect(shape.headingLevel == 2)
        #expect(shape.headingText == "[ ] v")
    }

    // MARK: - Controls (guard against over-correction)

    @Test("flag OFF control: `- [ ] v` (no underline) is an UNCHECKED task item with a paragraph `v`")
    func openingLineOnlyIsStillTaskFlagOff() throws {
        let shape = shape("- [ ] v", options: Self.flagOff)
        let checked = try #require(shape.itemChecked, "no list item parsed")
        #expect(checked == .some(false))
        #expect(shape.headingLevel == nil)
        #expect(shape.allTexts == ["v"])
    }

    @Test("flag OFF control: `- v\\n  -` is an ORDINARY item with a level-2 heading `v`")
    func plainItemSetextHeadingNotTaskFlagOff() throws {
        let shape = shape("- v\n  -", options: Self.flagOff)
        let checked = try #require(shape.itemChecked, "no list item parsed")
        try #require(shape.headingLevel != nil, "no heading parsed")
        #expect(checked == .some(nil))
        #expect(shape.headingLevel == 2)
        #expect(shape.headingText == "v")
    }
}
