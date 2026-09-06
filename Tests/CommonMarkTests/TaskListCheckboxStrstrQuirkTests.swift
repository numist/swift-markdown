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
/// This is a `[ref-b4b]` quirk: reproduced ONLY under `.cmarkBugCompatibility` (adopted by the
/// differential fuzzer). The shipped deliverable (flag OFF) stays spec-correct — the checked state comes
/// from the leading token alone. The quirk is STRUCTURAL (the checked flag prints in `debugDescription`
/// as `ListItem checkbox: [x]`/`[ ]`), so it is gated on `.cmarkBugCompatibility` alone, with no positions
/// dependency; these tests parse without `.sourcePosition`.
@Suite("GFM task-list checkbox strstr-over-the-line quirk")
struct TaskListCheckboxStrstrQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = [.tasklist]
    private static let flagOn: MarkdownDocument.ParseOptions = [.tasklist, .cmarkBugCompatibility]

    private func checkedState(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Bool? {
        let state: Bool?? = try MarkdownDocument.withParsedDocument(src, options: options) { doc -> Bool?? in
            firstItemChecked(doc.root)
        }
        // Fixture-sanity: a list item must exist, so a checked/unchecked claim can't pass vacuously
        // against a tree with no item at all.
        return try #require(state, "no list item parsed")
    }

    // MARK: Flag ON — reproduce cmark's bug

    @Test("flag ON: `- [ ] [x]` is CHECKED (later token flips it)")
    func flagOnLaterTokenFlipsChecked() throws {
        #expect(try checkedState("- [ ] [x]", options: Self.flagOn) == true)
    }

    @Test("flag ON: `- [ ] x [x] y` is CHECKED (substring anywhere on the line)")
    func flagOnSubstringMidLine() throws {
        #expect(try checkedState("- [ ] x [x] y", options: Self.flagOn) == true)
    }

    @Test("flag ON: `- [ ]   foo [x]` is CHECKED (multi-space marker)")
    func flagOnMultiSpaceMarker() throws {
        #expect(try checkedState("- [ ]   foo [x]", options: Self.flagOn) == true)
    }

    @Test("flag ON: `- [ ] a [X] b` is CHECKED (uppercase X counts)")
    func flagOnUppercaseMidLine() throws {
        #expect(try checkedState("- [ ] a [X] b", options: Self.flagOn) == true)
    }

    @Test("flag ON: `- [ ] [X]` is CHECKED (uppercase)")
    func flagOnUppercaseToken() throws {
        #expect(try checkedState("- [ ] [X]", options: Self.flagOn) == true)
    }

    @Test("flag ON: `- [ ] [x` is UNCHECKED (no closing bracket, no `[x]` substring)")
    func flagOnNoClosingBracket() throws {
        #expect(try checkedState("- [ ] [x", options: Self.flagOn) == false)
    }

    @Test("flag ON: `- [ ] (x)` is UNCHECKED (parens are not brackets)")
    func flagOnParens() throws {
        #expect(try checkedState("- [ ] (x)", options: Self.flagOn) == false)
    }

    @Test("flag ON: `- [ ] ]x[` is UNCHECKED (no `[x]` substring)")
    func flagOnReversedBrackets() throws {
        #expect(try checkedState("- [ ] ]x[", options: Self.flagOn) == false)
    }

    @Test("flag ON: continuation-line `[x]` does NOT flip checked (scan is line-scoped)")
    func flagOnContinuationLineExcluded() throws {
        // `- [ ] a` then a continuation line `  [x]` indented to the item's content column. cmark's
        // strstr only sees the checkbox's own (first) physical line, so the line-2 `[x]` is excluded.
        #expect(try checkedState("- [ ] a\n  [x]", options: Self.flagOn) == false)
    }

    // Agreeing controls (leading token already decides; strstr must not disagree).

    @Test("flag ON control: `- [x] [ ]` is CHECKED (leading token self-matches)")
    func flagOnControlCheckedToken() throws {
        #expect(try checkedState("- [x] [ ]", options: Self.flagOn) == true)
    }

    @Test("flag ON control: `- [ ] [ ]` is UNCHECKED")
    func flagOnControlBothUnchecked() throws {
        #expect(try checkedState("- [ ] [ ]", options: Self.flagOn) == false)
    }

    @Test("flag ON control: `- [x] [x]` is CHECKED")
    func flagOnControlBothChecked() throws {
        #expect(try checkedState("- [x] [x]", options: Self.flagOn) == true)
    }

    @Test("flag ON control: `- [ ] x` is UNCHECKED (plain content)")
    func flagOnControlPlainContent() throws {
        #expect(try checkedState("- [ ] x", options: Self.flagOn) == false)
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
}
