/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The checked state and direct-child count of the first list item in depth-first order, or nil if
/// there is none.
private func firstListItem(
    _ node: borrowing MarkdownNode
) -> (checked: Bool?, childCount: Int)? {
    if case .item(let checked) = node.kind {
        var count = 0
        node.children.forEach { _ in count += 1 }
        return (checked, count)
    }
    var found: (checked: Bool?, childCount: Int)? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstListItem(child)
        }
    }
    return found
}

/// Block structure of a task list item whose first line holds only the checkbox and trailing
/// whitespace (`- [ ] ` / `- [x]\t`).
///
/// The line is not blank, so it opens the item's paragraph (List items), which a following line
/// continues as paragraph continuation text, indented or as a lazy continuation line. The paragraph
/// begins with a task list item marker followed by whitespace, so the item is a task list item (Task
/// list items (extension)); the marker becomes the checkbox, and a paragraph left with no content is
/// removed.
@Suite("Empty task list item block structure")
struct EmptyTaskItemStructureTests {

    private typealias Pos = MarkdownNode.SourcePosition

    private static let options: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition]

    private func analyze(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> (nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)],
                 firstItem: (checked: Bool?, childCount: Int)?) {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> (nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)],
                    firstItem: (checked: Bool?, childCount: Int)?) in
            var nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)] = []
            dfsRanges(doc.root, into: &nodes)
            return (nodes, firstListItem(doc.root))
        }
    }

    private func itemRange(
        in nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> Range<Pos>? {
        for entry in nodes {
            if case .item = entry.kind { return entry.range }
        }
        return nil
    }

    private func paragraphs(
        in nodes: [(kind: MarkdownNode.Kind, range: Range<Pos>?)]
    ) -> [Range<Pos>?] {
        nodes.filter { $0.kind == .paragraph }.map { $0.range }
    }

    @Test("a checkbox-only task list item line is continued by a lazy continuation line")
    func emptyTaskItemLineContinuedLazily() throws {
        let (nodes, item) = analyze("- [ ] \nx", options: Self.options)
        let firstItem = try #require(item, "no list item parsed")
        try #require(firstItem.checked == .some(false), "expected an unchecked task list item")
        #expect(firstItem.childCount == 1)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 2, column: 2))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 2))
    }

    @Test("empty task list item followed by a blank line then text")
    func emptyTaskItemBeforeBlankThenText() throws {
        let (nodes, item) = analyze("- [ ] \n\nx", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 2, column: 1))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 3, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 3, column: 2))
    }

    @Test("empty task list item as the last line")
    func emptyTaskItemAtEOF() throws {
        let (nodes, item) = analyze("- [ ] ", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 1, column: 7))
        #expect(paragraphs(in: nodes).isEmpty)
    }

    @Test("empty task list item followed by an indented line continues the item")
    func emptyTaskItemContinuesOnIndentedLine() throws {
        let (nodes, item) = analyze("- [ ] \n  x", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 1)   // the continuation paragraph
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 2, column: 4))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 3))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 4))
    }

    @Test("checked checkbox-only task list item line with a tab separator")
    func emptyCheckedTaskItemTabSeparator() throws {
        let (nodes, item) = analyze("- [x]\t\nx", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(true), "expected a checked task list item")
        #expect(firstItem.childCount == 1)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 2, column: 2))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 2))
    }

    @Test("a checkbox-only item in a block quote is a task list item")
    func blockQuotedEmptyCheckboxIsRecognized() throws {
        let (nodes, item) = analyze("> - [ ] ", options: Self.options)
        let firstItem = try #require(item, "no list item parsed")
        #expect(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 3)..<Pos(line: 1, column: 9))
        #expect(paragraphs(in: nodes).isEmpty)
    }

    @Test("a nested checkbox-only item on the outer item's first line is a task list item")
    func nestedEmptyCheckboxIsRecognized() {
        let (nodes, _) = analyze("- - [ ] ", options: Self.options)
        let checks = nodes.compactMap { entry -> Bool?? in
            if case .item(let checked) = entry.kind { return .some(checked) }
            return nil
        }
        #expect(checks == [nil, .some(false)])
        #expect(paragraphs(in: nodes).isEmpty)
    }
}
