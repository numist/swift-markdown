/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark


/// The checked state of every `.item` node, in document (DFS) order. `.some(false)` = unchecked task
/// item, `.some(true)` = checked, `nil` = an ordinary (non-task) list item.
private func itemCheckStates(_ node: borrowing MarkdownNode, into out: inout [Bool?]) {
    if case .item(let checked) = node.kind {
        out.append(checked)
    }
    node.children.forEach { child in
        itemCheckStates(child, into: &out)
    }
}

/// Every text node's literal, in document (DFS) order.
private func textLiterals(_ node: borrowing MarkdownNode, into out: inout [String?]) {
    if node.kind == .text {
        out.append(node.literal())
    }
    node.children.forEach { child in
        textLiterals(child, into: &out)
    }
}

/// Recognition of a task list item with content after its checkbox, at the top level and nested.
///
/// A task list item is a list item whose first block is a paragraph beginning with a task list item
/// marker (spec "Task list items (extension)"). That depends only on the item's own first paragraph, so
/// an item is recognized however deeply it is nested and whatever container markers precede it on its
/// line.
@Suite("Task list items with content")
struct ContentTaskItemStructureTests {

    private static let options: MarkdownDocument.ParseOptions =
        [.tasklist, .sourcePosition]

    private func analyze(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> (checks: [Bool?], texts: [String?]) {
        MarkdownDocument.withParsedDocument(src, options: options) {
            doc -> (checks: [Bool?], texts: [String?]) in
            var checks: [Bool?] = []
            var texts: [String?] = []
            itemCheckStates(doc.root, into: &checks)
            textLiterals(doc.root, into: &texts)
            return (checks, texts)
        }
    }

    // MARK: - Top-level items

    @Test("a top-level task list item is recognized and its checkbox is not text")
    func topLevelContentTaskRecognized() throws {
        let (checks, texts) = analyze("- [ ] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(false))
        #expect(texts.contains("x"))
        #expect(!texts.contains { $0?.contains("[ ]") == true })
    }

    @Test("indented top-level content task item is recognized")
    func indentedTopLevelContentTaskRecognized() throws {
        // Three spaces is the most indentation a list item may have without becoming indented code (List items).
        let (checks, texts) = analyze("   - [ ] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(false))
        #expect(texts.contains("x"))
        #expect(!texts.contains { $0?.contains("[ ]") == true })
    }

    @Test("top-level checked content task item is recognized")
    func topLevelCheckedContentTaskRecognized() throws {
        let (checks, texts) = analyze("- [x] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(true))
        #expect(texts.contains("x"))
    }

    @Test("a top-level task list item whose checkbox is followed by a tab is recognized")
    func topLevelTabSeparatorContentTaskRecognized() throws {
        let (checks, _) = analyze("- [ ]\tx", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(false))
    }

    // MARK: - Nested / block-quoted items

    @Test("task list item in a block quote is recognized")
    func blockQuotedContentTaskRecognized() throws {
        let (checks, texts) = analyze("> - [ ] x", options: Self.options)
        try #require(checks.count == 1, "expected exactly one list item, got \(checks)")
        #expect(checks[0] == .some(false))
        #expect(texts == ["x"])
    }

    @Test("task list item sharing its line with an outer list marker is recognized")
    func nestedContentTaskRecognized() throws {
        let (checks, texts) = analyze("- - [ ] x", options: Self.options)
        try #require(checks.count == 2, "expected outer + inner items, got \(checks)")
        #expect(checks == [nil, .some(false)])
        #expect(texts == ["x"])
    }

    @Test("task list item nested three deep is recognized")
    func threeDeepNestedContentTaskRecognized() throws {
        let (checks, texts) = analyze("- - - [ ] x", options: Self.options)
        try #require(checks.count == 3, "expected three nested items, got \(checks)")
        #expect(checks == [nil, nil, .some(false)])
        #expect(texts == ["x"])
    }

    @Test("task list item in a block quote in a list item is recognized")
    func taskInBlockQuoteInListRecognized() throws {
        let (checks, texts) = analyze("- > - [ ] x", options: Self.options)
        try #require(checks.count == 2, "expected outer + inner items, got \(checks)")
        #expect(checks == [nil, .some(false)])
        #expect(texts == ["x"])
    }

    @Test("task list item nested in an ordered list item is recognized")
    func orderedNestedContentTaskRecognized() throws {
        let (checks, texts) = analyze("1. - [ ] x", options: Self.options)
        try #require(checks.count == 2, "expected outer ordered + inner bullet items, got \(checks)")
        #expect(checks == [nil, .some(false)])
        #expect(texts == ["x"])
    }

    // MARK: - Nested on its own line

    @Test("task list item in a sublist on its own line is recognized")
    func sublistItemOnOwnLineIsRecognized() throws {
        let (checks, texts) = analyze("- a\n  - [ ] b", options: Self.options)
        try #require(checks.count == 2, "expected outer `a` + nested `b` items, got \(checks)")
        #expect(checks == [nil, false])
        #expect(texts.contains("b"))
        #expect(!texts.contains { $0?.contains("[ ]") == true })
    }
}
