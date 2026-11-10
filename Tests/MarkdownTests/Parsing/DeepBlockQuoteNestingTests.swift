/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// Block quotes nest without a depth limit (Block quotes), and a document of deeply nested block quotes dumps and
/// renders every level.
struct DeepBlockQuoteNestingTests {

    /// A line of `>` markers opens one block quote per marker; a following `>` line continues only the outermost.
    @Test func multiLineDeepBlockQuotesBuildFullTree() {
        let markdown = String(repeating: ">", count: 300) + "\n>"
        let document = Document(parsing: markdown)

        var depth = 0
        var node: Markup? = document.child(at: 0)
        while let blockQuote = node as? BlockQuote {
            depth += 1
            node = blockQuote.child(at: 0)
        }

        #expect(depth == 300)
    }

    @Test func deepTreeDebugDescriptionDoesNotOverflow() {
        let document = Document(parsing: String(repeating: ">", count: 300))
        let dump = document.debugDescription(options: .printSourceLocations)
        let blockQuoteLines = (1...300).map { level in
            "\n" + String(repeating: " ", count: 3 * (level - 1)) + "└─ BlockQuote @1:\(level)-1:301"
        }
        #expect(dump == "Document @1:1-1:301" + blockQuoteLines.joined())
    }

    @Test func deepTreeHTMLRenderRendersEveryLevel() {
        let document = Document(parsing: String(repeating: ">", count: 300))
        let html = HTMLFormatter.format(document)
        #expect(html == String(repeating: "<blockquote>\n", count: 300) + String(repeating: "</blockquote>\n", count: 300))
    }
}
