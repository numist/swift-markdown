/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A line without a `>` continues the innermost paragraph as a lazy continuation line (Block quotes), however many
/// block quotes hold it. 40,000 nested quotes followed by 40,000 lazy lines, about 240 KB of source, parse within the
/// time limit.
@Suite("Lazy continuation under deep block-quote nesting")
struct DeepBlockQuoteLazyContinuationTests {

    @Test(.timeLimit(.minutes(1)), arguments: [MarkdownDocument.ParseOptions(), [.sourcePosition]])
    func lazyLinesJoinTheInnermostParagraph(options: MarkdownDocument.ParseOptions) {
        let depth = 40_000
        let markdown = String(repeating: ">", count: depth) + " a\n" + String(repeating: "lazy\n", count: depth)
        let (quotes, innermostKinds) = MarkdownDocument.withParsedDocument(markdown, options: options) { doc in
            var quotes = 0
            var innermostKinds: [MarkdownNode.Kind] = []
            var node = doc.root.firstChild
            while let current = node {
                guard case .blockQuote = current.kind else {
                    innermostKinds.append(current.kind)
                    current.children.forEach { innermostKinds.append($0.kind) }
                    break
                }
                quotes += 1
                node = current.firstChild
            }
            return (quotes, innermostKinds)
        }

        #expect(quotes == 40_000)
        #expect(innermostKinds.count == 80_002)
        #expect(innermostKinds.first == .paragraph)
        #expect(innermostKinds.filter { $0 == .softBreak }.count == 40_000)
        #expect(innermostKinds.filter { $0 == .text }.count == 40_001)
    }
}
