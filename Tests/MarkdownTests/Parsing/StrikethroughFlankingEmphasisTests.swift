/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A `~` is a punctuation character (Characters and lines), so a delimiter run beside a `~` run is classified
/// against the `~`, not against the character past it.
@Suite struct StrikethroughFlankingEmphasisTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func closerAfterPunctuationBeforeTilde() {
        #expect(tree("*-*~a") == """
            Document @1:1-1:6
            └─ Paragraph @1:1-1:6
               ├─ Emphasis @1:1-1:4
               │  └─ Text @1:2-1:3 "-"
               └─ Text @1:4-1:6 "~a"
            """)
        #expect(tree("*.*~~a") == """
            Document @1:1-1:7
            └─ Paragraph @1:1-1:7
               ├─ Emphasis @1:1-1:4
               │  └─ Text @1:2-1:3 "."
               └─ Text @1:4-1:7 "~~a"
            """)
    }

    @Test func openerAfterTildeBeforePunctuation() {
        #expect(tree("a~*-x*") == """
            Document @1:1-1:7
            └─ Paragraph @1:1-1:7
               ├─ Text @1:1-1:3 "a~"
               └─ Emphasis @1:3-1:7
                  └─ Text @1:4-1:6 "-x"
            """)
    }
}
