/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// Deep block-quote nesting must build the full tree (cmark leaves block quotes uncapped) and must
/// render without overflowing the call stack, on any thread — including the small-stack worker
/// threads the test runner uses.
struct DeepBlockQuoteNestingTests {

    /// A single line of `>` markers opens one block quote per marker, and a following line keeps
    /// them open. Before block-quote nesting was uncapped, the per-line open-container walk threw a
    /// parsing-limit error once the chain crossed 256, and the whole document collapsed to empty.
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

    /// Dumping a deeply nested tree must not recurse one native stack frame per level.
    @Test func deepTreeDebugDescriptionDoesNotOverflow() {
        let document = Document(parsing: String(repeating: ">", count: 300))
        let dump = document.debugDescription(options: .printSourceLocations)
        #expect(dump.contains("BlockQuote"))
    }

    /// Rendering HTML for a deeply nested tree must likewise not overflow the stack.
    @Test func deepTreeHTMLRenderDoesNotOverflow() {
        let document = Document(parsing: String(repeating: ">", count: 300))
        let html = HTMLFormatter.format(document)
        #expect(html.contains("<blockquote>"))
    }
}
