/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

// Depth-first: the checked state of the first list item, or nil if there is none. File-scope because a
// recursive walk over `borrowing MarkdownNode` can't capture the borrow in a closure.
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

/// A task list item's checked state comes from its leading checkbox alone (Task list items (extension)); a
/// later `[x]` on the same line is paragraph text.
@Suite("Task list item checked state")
struct TaskListCheckedStateTests {

    private static let tasklist: MarkdownDocument.ParseOptions = [.tasklist]

    private func checkedState(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Bool? {
        let state: Bool?? = MarkdownDocument.withParsedDocument(src, options: options) { doc -> Bool?? in
            firstItemChecked(doc.root)
        }
        return try #require(state, "no list item parsed")
    }

    @Test("`- [ ] [x]` is unchecked")
    func laterCheckedBoxIgnored() throws {
        #expect(try checkedState("- [ ] [x]", options: Self.tasklist) == false)
    }

    @Test("`- [ ] x [x] y` is unchecked")
    func midLineCheckedBoxIgnored() throws {
        #expect(try checkedState("- [ ] x [x] y", options: Self.tasklist) == false)
    }

    @Test("`- [ ] [X]` is unchecked")
    func laterUppercaseCheckedBoxIgnored() throws {
        #expect(try checkedState("- [ ] [X]", options: Self.tasklist) == false)
    }

    @Test("`- [x] [ ]` is checked")
    func leadingCheckedBoxBeforeUncheckedBox() throws {
        #expect(try checkedState("- [x] [ ]", options: Self.tasklist) == true)
    }

    @Test("`- [x] foo` is checked")
    func checkedWithContent() throws {
        #expect(try checkedState("- [x] foo", options: Self.tasklist) == true)
    }

    @Test("`- [ ]   foo [x]` is unchecked with several spaces after the checkbox")
    func multiSpaceAfterCheckbox() throws {
        #expect(try checkedState("- [ ]   foo [x]", options: Self.tasklist) == false)
    }

    @Test("`- [ ] a [X] b` is unchecked")
    func uppercaseMidLineIgnored() throws {
        #expect(try checkedState("- [ ] a [X] b", options: Self.tasklist) == false)
    }

    @Test("`- [ ] [x` is unchecked")
    func noClosingBracket() throws {
        #expect(try checkedState("- [ ] [x", options: Self.tasklist) == false)
    }

    @Test("`- [ ] (x)` is unchecked")
    func parens() throws {
        #expect(try checkedState("- [ ] (x)", options: Self.tasklist) == false)
    }

    @Test("`- [ ] ]x[` is unchecked")
    func reversedBrackets() throws {
        #expect(try checkedState("- [ ] ]x[", options: Self.tasklist) == false)
    }

    @Test("continuation-line `[x]` does not check the item")
    func continuationLineCheckedBoxIgnored() throws {
        #expect(try checkedState("- [ ] a\n  [x]", options: Self.tasklist) == false)
    }

    @Test("`- [ ] [ ]` is unchecked")
    func bothUnchecked() throws {
        #expect(try checkedState("- [ ] [ ]", options: Self.tasklist) == false)
    }

    @Test("`- [x] [x]` is checked")
    func bothChecked() throws {
        #expect(try checkedState("- [x] [x]", options: Self.tasklist) == true)
    }

    @Test("`- [ ] x` is unchecked")
    func plainContent() throws {
        #expect(try checkedState("- [ ] x", options: Self.tasklist) == false)
    }
}
