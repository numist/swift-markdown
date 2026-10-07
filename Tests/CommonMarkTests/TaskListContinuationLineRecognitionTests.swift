/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the checked state of the first list item — `.some(nil)` = an ordinary bullet item,
// `.some(.some(x))` = a task list item (unchecked/checked), outer `nil` = no item at all.
// File-scope because a recursive walk over `borrowing MarkdownNode` can't capture the borrow in a closure.
private func firstItemChecked(_ node: borrowing MarkdownNode) -> Bool?? {
    if case .item(let checked) = node.kind {
        return .some(checked)
    }
    var found: Bool?? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstItemChecked(child)
        }
    }
    return found
}

/// A task list item marker begins the item's first paragraph (Task list items (extension)), so it may sit
/// on the line after a list marker with no content.
@Suite("Task list item marker on a continuation line")
struct TaskListContinuationLineRecognitionTests {

    private static let tasklist: MarkdownDocument.ParseOptions = [.tasklist]

    private func firstChecked(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Bool? {
        let state: Bool?? = MarkdownDocument.withParsedDocument(src, options: options) { doc -> Bool?? in
            firstItemChecked(doc.root)
        }
        return try #require(state, "no list item parsed")
    }

    @Test("`-\\n  [x] foo` is a checked task list item")
    func checkboxOnContinuationLine() throws {
        #expect(try firstChecked("-\n  [x] foo", options: Self.tasklist) == true)
    }

    @Test("`- [x] foo` is a checked task list item")
    func checkboxOnOpeningLine() throws {
        #expect(try firstChecked("- [x] foo", options: Self.tasklist) == true)
    }

    @Test("`- [x] a\\n  [x] b` is a checked task list item")
    func checkboxOnOpeningLineWithContinuation() throws {
        #expect(try firstChecked("- [x] a\n  [x] b", options: Self.tasklist) == true)
    }
}
