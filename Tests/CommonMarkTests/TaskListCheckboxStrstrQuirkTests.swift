/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Depth-first: the checked state of the first list item, or nil if there is none. File-scope +
// `borrowing MarkdownNode` to satisfy the noncopyable-borrow rules (see code-conventions: use
// file-scope helpers, don't capture the borrow across the tree walk).
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

/// cmark-gfm's tasklist extension (`open_tasklist_item`, `extensions/tasklist.c`) sets a task item's
/// CHECKED state with `strstr(input, "[x]") || strstr(input, "[X]")` over the checkbox's own line — from
/// the checkbox position to the end of that first physical line — NOT from the leading checkbox token. So
/// any `[x]`/`[X]` substring anywhere on the first line flips the item checked, even when the leading
/// token is `[ ]` (`- [ ] [x]` → CHECKED). The leading token still determines WHERE the checkbox is and
/// whether the item is a task item at all; only the checked/unchecked STATE carries the bug.
///
/// The shipped deliverable (flag OFF) stays spec-correct — the checked state comes
/// from the leading token alone.
@Suite("GFM task-list checkbox strstr-over-the-line quirk")
struct TaskListCheckboxStrstrQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = [.tasklist]

    private func checkedState(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Bool? {
        let state: Bool?? = MarkdownDocument.withParsedDocument(src, options: options) { doc -> Bool?? in
            firstItemChecked(doc.root)
        }
        // Fixture-sanity: a list item must exist, so a checked/unchecked claim can't pass vacuously
        // against a tree with no item at all.
        return try #require(state, "no list item parsed")
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (leading token only)

    @Test("flag OFF: `- [ ] [x]` is UNCHECKED (leading token only)")
    func flagOffLeadingTokenOnly() throws {
        #expect(try checkedState("- [ ] [x]", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [ ] x [x] y` is UNCHECKED")
    func flagOffSubstringIgnored() throws {
        #expect(try checkedState("- [ ] x [x] y", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [ ] [X]` is UNCHECKED")
    func flagOffUppercaseIgnored() throws {
        #expect(try checkedState("- [ ] [X]", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [x] [ ]` is CHECKED (leading token)")
    func flagOffCheckedToken() throws {
        #expect(try checkedState("- [x] [ ]", options: Self.flagOff) == true)
    }

    @Test("flag OFF: `- [x] foo` is CHECKED (leading token)")
    func flagOffCheckedWithContent() throws {
        #expect(try checkedState("- [x] foo", options: Self.flagOff) == true)
    }

    /// The checked state comes from the task list item marker alone (GFM task list items), where cmark's line-wide
    /// `strstr` finds the later `[x]` and checks the item.
    @Test("flag OFF: `- [ ]   foo [x]` is UNCHECKED (multi-space marker)")
    func flagOffMultiSpaceMarker() throws {
        #expect(try checkedState("- [ ]   foo [x]", options: Self.flagOff) == false)
    }

    /// The checked state comes from the task list item marker alone (GFM task list items), where cmark's line-wide
    /// `strstr` finds the later `[X]` and checks the item.
    @Test("flag OFF: `- [ ] a [X] b` is UNCHECKED")
    func flagOffUppercaseMidLine() throws {
        #expect(try checkedState("- [ ] a [X] b", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [ ] [x` is UNCHECKED")
    func flagOffNoClosingBracket() throws {
        #expect(try checkedState("- [ ] [x", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [ ] (x)` is UNCHECKED")
    func flagOffParens() throws {
        #expect(try checkedState("- [ ] (x)", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [ ] ]x[` is UNCHECKED")
    func flagOffReversedBrackets() throws {
        #expect(try checkedState("- [ ] ]x[", options: Self.flagOff) == false)
    }

    @Test("flag OFF: continuation-line `[x]` does NOT flip checked")
    func flagOffContinuationLineExcluded() throws {
        #expect(try checkedState("- [ ] a\n  [x]", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [ ] [ ]` is UNCHECKED")
    func flagOffBothUnchecked() throws {
        #expect(try checkedState("- [ ] [ ]", options: Self.flagOff) == false)
    }

    @Test("flag OFF: `- [x] [x]` is CHECKED")
    func flagOffBothChecked() throws {
        #expect(try checkedState("- [x] [x]", options: Self.flagOff) == true)
    }

    @Test("flag OFF: `- [ ] x` is UNCHECKED (plain content)")
    func flagOffPlainContent() throws {
        #expect(try checkedState("- [ ] x", options: Self.flagOff) == false)
    }
}
