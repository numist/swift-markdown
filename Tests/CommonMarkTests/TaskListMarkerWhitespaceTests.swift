/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// GFM task-list marker whitespace: cmark's tasklist extension advances past the `[x]`/`[ ]` checkbox
/// (3 bytes) and lets the paragraph's normal first-non-space logic strip the following whitespace, so
/// the item's content begins at the first non-space/tab after the checkbox — ALL of it is stripped,
/// not just one separator. The rewrite consumed a fixed `[x] ` (checkbox + one space), leaking any
/// extra whitespace into the content ("- [x]  a" → " a" instead of "a"). A trailing whitespace
/// separator is still REQUIRED (cmark's `scan_tasklist`): `[x]a` with no space stays literal text.
/// Spec-aligned `[fix]`.
@Suite("Task-list marker whitespace")
struct TaskListMarkerWhitespaceTests {

    private static let opts: MarkdownDocument.ParseOptions = [.tasklist]

    /// (found a list item?, its checked state — nil for a non-task item, first text literal in DFS order).
    private func parse(_ source: String) -> (foundItem: Bool, checked: Bool?, firstText: String?) {
        MarkdownDocument.withParsedDocument(source, options: Self.opts) { doc -> (Bool, Bool?, String?) in
            var foundItem = false
            var checked: Bool? = nil
            var firstText: String? = nil
            func walk(_ node: borrowing MarkdownNode) {
                if case .item(let c) = node.kind, !foundItem {
                    foundItem = true
                    checked = c
                }
                if firstText == nil, node.kind == .text, let lit = node.literal() {
                    firstText = lit
                }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return (foundItem, checked, firstText)
        }
    }

    // MARK: - FIX: all whitespace after the checkbox is stripped

    @Test("two spaces after the checkbox are all stripped")
    func twoSpaces() {
        let (found, checked, text) = parse("- [x]  a")
        #expect(found && checked == true)     // recognized as a checked task item
        #expect(text == "a")                  // not " a"
    }

    @Test("three spaces after an unchecked checkbox are all stripped")
    func threeSpacesUnchecked() {
        let (found, checked, text) = parse("- [ ]   a")
        #expect(found && checked == false)
        #expect(text == "a")                  // not "  a"
    }

    @Test("a tab separator strips to the content")
    func tabSeparator() {
        // cmark accepts a tab after the checkbox and the content is "a" (tab stripped).
        let (found, checked, text) = parse("- [x]\ta")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    @Test("ordered-list task item strips all trailing whitespace too")
    func orderedTaskItem() {
        let (found, checked, text) = parse("2. [x]  a")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    // MARK: - LEAVE: guards

    @Test("a single space is stripped (unchanged)")
    func singleSpace() {
        let (found, checked, text) = parse("- [x] a")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    @Test("no whitespace after the checkbox is not a task item")
    func noSeparatorIsLiteral() {
        // `- [x]a` : cmark's scan_tasklist requires trailing whitespace, so the checkbox stays literal.
        let (found, checked, text) = parse("- [x]a")
        #expect(found && checked == nil)      // an ordinary (non-task) list item
        #expect(text == "[x]a")
    }

    @Test("a multi-line multi-space task item strips only the first line's marker whitespace")
    func multiLineContinuation() {
        // `- [x]  a` / `     b` : line 1 content is "a" (all post-checkbox whitespace stripped); the
        // lazy continuation "b" is unaffected. cmark yields text nodes "a" and "b".
        let texts = MarkdownDocument.withParsedDocument("- [x]  a\n     b", options: Self.opts) { doc -> [String] in
            var out: [String] = []
            func walk(_ node: borrowing MarkdownNode) {
                if node.kind == .text, let lit = node.literal() { out.append(lit) }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return out
        }
        #expect(texts == ["a", "b"])
    }

    // MARK: - A vertical-tab / form-feed gap BEFORE the checkbox

    // The paragraph's initial whitespace, which includes line tabulation and form feed, is removed (spec
    // "Paragraphs"), so the paragraph begins with the checkbox and its content is what follows it.

    @Test("a vertical-tab gap before an unchecked checkbox is recognized")
    func vertTabGapUnchecked() {
        let (found, checked, text) = parse("- \u{0B}[ ] a")
        #expect(found && checked == false)
        #expect(text == "a")
    }

    @Test("a vertical-tab gap before a checked checkbox is recognized")
    func vertTabGapChecked() {
        let (found, checked, text) = parse("- \u{0B}[x] a")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    @Test("a form-feed gap before the checkbox is recognized too")
    func formFeedGap() {
        let (found, checked, text) = parse("- \u{0C}[ ] a")
        #expect(found && checked == false)
        #expect(text == "a")
    }

    @Test("a non-whitespace char before the checkbox is not a task item")
    func nonWhitespaceBeforeCheckboxIsLiteral() {
        let (found, checked, text) = parse("- a[ ] b")
        #expect(found && checked == nil)     // an ordinary (non-task) list item
        #expect(text == "a[ ] b")
    }

    @Test("a mixed VT+space gap before the checkbox is recognized")
    func mixedVertTabSpaceGap() {
        let (found, checked, text) = parse("- \u{0B} [ ] a")
        #expect(found && checked == false)
        #expect(text == "a")
    }

    @Test("a two-VT gap before the checkbox is recognized")
    func twoVertTabGap() {
        let (found, checked, text) = parse("- \u{0B}\u{0B}[ ] a")
        #expect(found && checked == false)
        #expect(text == "a")
    }
}
