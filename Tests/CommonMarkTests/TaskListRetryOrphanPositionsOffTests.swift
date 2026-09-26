/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Literals of every `.htmlInline` node in the tree, in document order. File-scope + `borrowing MarkdownNode`
// to satisfy the noncopyable-borrow rules.
private func inlineHTMLLiterals(_ node: borrowing MarkdownNode) -> [String] {
    var literals: [String] = []
    if case .htmlInline = node.kind {
        literals.append(node.literal() ?? "")
    }
    node.children.forEach { child in
        literals += inlineHTMLLiterals(child)
    }
    return literals
}

/// A lazy tasklist-retry line's orphaned continuation byte ends cmark's UTF-8-validating processing
/// instruction scan whether or not source positions are tracked. Without positions a tab-expanded first line
/// is accumulated as a materialized buffer, so the orphan-led line lands inside it; with them it stays a
/// source range. A NUL elsewhere in the paragraph flattens either representation into one arena chunk.
/// Ground truth is cmark-gfm's `- >a<?` LF `  2` NUL ` [x] ` (`TaskListRetryLazyOrphanRawHTMLTests`), whose
/// PI takes the orphan and the space after it as its unverified `?>`.
@Suite("Tasklist-retry orphan with and without source positions")
struct TaskListRetryOrphanPositionsOffTests {

    private static let positionStates: [MarkdownDocument.ParseOptions] = [
        [.cmarkBugCompatibility, .tasklist],
        [.cmarkBugCompatibility, .tasklist, .sourcePosition],
    ]

    private func htmlLiterals(_ src: String, options: MarkdownDocument.ParseOptions) throws -> [String] {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> [String] in
            inlineHTMLLiterals(doc.root)
        }
    }

    @Test("an orphan-led line appended to a tab-expanded first line", arguments: positionStates)
    func orphanAfterTabExpandedFirstLine(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("- >\ta<?\n  2\u{0} [x] \n", options: options) == ["<?\n\u{FFFD} "])
    }

    @Test("an orphan-led line in a paragraph flattened for a NUL", arguments: positionStates)
    func orphanInFlattenedParagraph(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("- >\ta\u{0}<?\n  2\u{0} [x] \n", options: options) == ["<?\n\u{FFFD} "])
        #expect(try htmlLiterals("- >a\u{0}<?\n  2\u{0} [x] \n", options: options) == ["<?\n\u{FFFD} "])
    }
}
