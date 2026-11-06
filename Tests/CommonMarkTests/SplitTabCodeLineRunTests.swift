/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Indented code lines in a list item whose indent splits a tab.
///
/// The list item's content starts at column 2, so the second tab of each `\t\tx` line contributes two columns of the
/// four an indented code block strips and leaves two spaces of content (Tabs). Each such line costs time in proportion
/// to its own length, so two million of them, about 8 MB of source, parse well within the time limit.
@Suite("Runs of indented code lines whose indent splits a tab")
struct SplitTabCodeLineRunTests {

    @Test(.timeLimit(.minutes(1)))
    func manySplitTabCodeLines() throws {
        let markdown = "- a\n\n" + String(repeating: "\t\tx\n", count: 2_000_000)
        let literal = try MarkdownDocument.withParsedDocument(markdown) { doc in
            var literals: [String] = []
            doc.root.children.forEach { list in
                list.children.forEach { item in
                    item.children.forEach { if case .codeBlock = $0.kind, let literal = $0.literal() { literals.append(literal) } }
                }
            }
            try #require(literals.count == 1)
            return literals[0]
        }
        #expect(literal.utf8.count == 8_000_000)
        #expect(literal.hasPrefix("  x\n  x\n"))
        #expect(literal.hasSuffix("  x\n  x\n"))
    }
}
