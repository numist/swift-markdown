/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the checked state and direct-child count of the first list item, or nil if there is
// none. File-scope + `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see
// code-conventions: use file-scope helpers, don't capture the borrow across the tree walk).
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

/// Block structure of a GFM task-list item whose marker line holds only the checkbox and trailing
/// whitespace (`- [ ] ` / `- [x]\t`).
///
/// The marker line is not blank, so it opens the item's paragraph (spec "List items"), which a
/// following line continues, lazily or indented (spec "Paragraph continuation text"). The paragraph
/// begins with a task list item marker followed by whitespace, so the item is a task item (spec "Task
/// list items (extension)"); the marker is replaced by the checkbox, and a paragraph left with no
/// content is removed.
@Suite("Empty GFM task-list item block structure")
struct EmptyTaskItemStructureTests {

    private typealias Pos = MarkdownNode.SourcePosition

    /// The shipped default: tasklist + positions.
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

    @Test("a marker-only task item line is continued lazily by an unindented line")
    func emptyTaskItemLineContinuedLazily() throws {
        // "- [ ] " (checkbox, only trailing space) then "x" (unindented, a lazy continuation).
        let (nodes, item) = analyze("- [ ] \nx", options: Self.options)
        let firstItem = try #require(item, "no list item parsed")
        try #require(firstItem.checked == .some(false), "expected an UNCHECKED task item")
        #expect(firstItem.childCount == 1)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 2, column: 2))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 2))
    }

    @Test("empty task item followed by a blank line then text")
    func emptyTaskItemBeforeBlankThenText() throws {
        // "- [ ] " then a blank line then "x": the item is empty and runs to the blank line @1:1-2:1,
        // `x` a separate paragraph @3:1-3:2.
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

    @Test("empty task item as the last line (EOF)")
    func emptyTaskItemAtEOF() throws {
        // "- [ ] " with nothing after: item empty @1:1-1:7, no paragraph anywhere.
        let (nodes, item) = analyze("- [ ] ", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 1, column: 7))
        #expect(paragraphs(in: nodes).isEmpty)
    }

    @Test("empty task item followed by an INDENTED line continues the item")
    func emptyTaskItemContinuesOnIndentedLine() throws {
        // "- [ ] " then "  x" (indented to the item's content column): the item keeps its checkbox and
        // holds the paragraph @2:3-2:4; item spans @1:1-2:4.
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

    @Test("checked marker-only task item line with a TAB separator")
    func emptyCheckedTaskItemTabSeparator() throws {
        // "- [x]\t" (tab after the checkbox) then "x", a lazy continuation of the item's paragraph.
        let (nodes, item) = analyze("- [x]\t\nx", options: Self.options)
        let firstItem = try #require(item)
        try #require(firstItem.checked == .some(true), "expected a CHECKED task item")
        #expect(firstItem.childCount == 1)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 1)..<Pos(line: 2, column: 2))
        let paras = paragraphs(in: nodes)
        try #require(paras.count == 1)
        #expect(paras[0]?.lowerBound == Pos(line: 2, column: 1))
        #expect(paras[0]?.upperBound == Pos(line: 2, column: 2))
    }

    @Test("a block-quoted marker-only item is a task item")
    func blockQuotedEmptyCheckboxIsRecognized() throws {
        let (nodes, item) = analyze("> - [ ] ", options: Self.options)
        let firstItem = try #require(item, "no list item parsed")
        #expect(firstItem.checked == .some(false))
        #expect(firstItem.childCount == 0)
        #expect(itemRange(in: nodes) == Pos(line: 1, column: 3)..<Pos(line: 1, column: 9))
        #expect(paragraphs(in: nodes).isEmpty)
    }

    @Test("a nested marker-only item sharing its line with the outer marker is a task item")
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
