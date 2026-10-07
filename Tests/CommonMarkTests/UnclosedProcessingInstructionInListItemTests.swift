/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Literals of every `.htmlInline` node in the tree, in document order. File-scope because a recursive walk
// over `borrowing MarkdownNode` can't capture the borrow in a closure.
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

/// A processing instruction needs a closing `?>` (Raw HTML), so an unclosed `<?` in a block quote paragraph
/// whose lazy continuation line holds a NUL and a checkbox is text, with or without source positions.
@Suite("Unclosed processing instruction in a list item's block quote")
struct UnclosedProcessingInstructionInListItemTests {

    private static let positionModes: [MarkdownDocument.ParseOptions] = [
        [.tasklist],
        [.tasklist, .sourcePosition],
    ]

    private func htmlLiterals(_ src: String, options: MarkdownDocument.ParseOptions) -> [String] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> [String] in
            inlineHTMLLiterals(doc.root)
        }
    }

    @Test("an unclosed `<?` is not inline HTML", arguments: positionModes)
    func unclosedProcessingInstruction(options: MarkdownDocument.ParseOptions) {
        #expect(htmlLiterals("- >\ta<?\n  2\u{0} [x] \n", options: options) == [])
        #expect(htmlLiterals("- >\ta\u{0}<?\n  2\u{0} [x] \n", options: options) == [])
        #expect(htmlLiterals("- >a\u{0}<?\n  2\u{0} [x] \n", options: options) == [])
    }
}
