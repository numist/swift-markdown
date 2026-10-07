/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A task list item's first block must be a paragraph (Task list items (extension)), so an item whose
/// first block is a setext heading has no checkbox and the heading keeps `[ ]` as text.
@Suite("Task list item marker in a setext heading")
struct TaskListSetextHeadingRecognitionTests {

    private static let tasklist: MarkdownDocument.ParseOptions = [.tasklist]

    /// A flattened view of the first list item and the first heading in a parsed document.
    private struct Shape {
        /// `nil` = no `.item` node at all; `.some(nil)` = an item without a checkbox; `.some(x)` = a task
        /// list item with checked state `x`.
        var itemChecked: Bool??
        /// The first heading's level, or `nil` if the tree has no heading.
        var headingLevel: Int?
        /// The first heading's concatenated text literals, or `nil` if the tree has no heading.
        var headingText: String?
        /// Every text literal in the document, in DFS order.
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

    @Test("`- [ ] v\\n  -` is an item without a checkbox, holding a level-2 heading `[ ] v`")
    func taskItemSetextHeadingNotRecognized() throws {
        let shape = shape("- [ ] v\n  -", options: Self.tasklist)
        let checked = try #require(shape.itemChecked, "no list item parsed")
        try #require(shape.headingLevel != nil, "no heading parsed")
        #expect(checked == nil)
        #expect(shape.headingLevel == 2)
        #expect(shape.headingText == "[ ] v")
    }

    // MARK: - Without a checkbox or an underline

    @Test("`- [ ] v` (no underline) is an unchecked task list item with a paragraph `v`")
    func openingLineOnlyIsTaskListItem() throws {
        let shape = shape("- [ ] v", options: Self.tasklist)
        let checked = try #require(shape.itemChecked, "no list item parsed")
        #expect(checked == .some(false))
        #expect(shape.headingLevel == nil)
        #expect(shape.allTexts == ["v"])
    }

    @Test("`- v\\n  -` is an item without a checkbox, holding a level-2 heading `v`")
    func plainItemSetextHeading() throws {
        let shape = shape("- v\n  -", options: Self.tasklist)
        let checked = try #require(shape.itemChecked, "no list item parsed")
        try #require(shape.headingLevel != nil, "no heading parsed")
        #expect(checked == .some(nil))
        #expect(shape.headingLevel == 2)
        #expect(shape.headingText == "v")
    }
}
