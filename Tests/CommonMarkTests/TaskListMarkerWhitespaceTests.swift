/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

/// A task list item marker must be followed by at least one whitespace character (Task list items
/// (extension)); all of that whitespace is removed from the item's content.
@Suite("Task list item marker whitespace")
struct TaskListMarkerWhitespaceTests {

    private static let opts: MarkdownDocument.ParseOptions = [.tasklist]

    /// (found a list item?, its checked state — nil without a checkbox, first text literal in DFS order).
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

    // MARK: - Whitespace after the checkbox

    @Test("two spaces after the checkbox are all stripped")
    func twoSpaces() {
        let (found, checked, text) = parse("- [x]  a")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    @Test("three spaces after an unchecked checkbox are all stripped")
    func threeSpacesUnchecked() {
        let (found, checked, text) = parse("- [ ]   a")
        #expect(found && checked == false)
        #expect(text == "a")
    }

    @Test("a tab separator strips to the content")
    func tabSeparator() {
        let (found, checked, text) = parse("- [x]\ta")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    @Test("ordered-list task list item strips all trailing whitespace")
    func orderedTaskItem() {
        let (found, checked, text) = parse("2. [x]  a")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    @Test("a single space is stripped")
    func singleSpace() {
        let (found, checked, text) = parse("- [x] a")
        #expect(found && checked == true)
        #expect(text == "a")
    }

    @Test("no whitespace after the checkbox is not a task list item")
    func noSeparatorIsLiteral() {
        let (found, checked, text) = parse("- [x]a")
        #expect(found && checked == nil)      // no checkbox
        #expect(text == "[x]a")
    }

    @Test("a multi-line multi-space task list item strips only the first line's marker whitespace")
    func multiLineContinuation() {
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

    // MARK: - Whitespace before the checkbox

    // The paragraph's initial whitespace, which includes line tabulation and form feed, is removed
    // (Paragraphs), so the paragraph begins with the checkbox and its content is what follows it.

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

    @Test("a form-feed gap before the checkbox is recognized")
    func formFeedGap() {
        let (found, checked, text) = parse("- \u{0C}[ ] a")
        #expect(found && checked == false)
        #expect(text == "a")
    }

    @Test("a non-whitespace char before the checkbox is not a task list item")
    func nonWhitespaceBeforeCheckboxIsLiteral() {
        let (found, checked, text) = parse("- a[ ] b")
        #expect(found && checked == nil)     // no checkbox
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
