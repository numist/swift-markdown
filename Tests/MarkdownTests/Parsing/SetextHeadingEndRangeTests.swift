/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A setext heading's source range ends at the end of its underline line, whatever line closes it.
struct SetextHeadingEndRangeTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func headingFollowedByParagraph() {
        #expect(tree("foo\n===  \nbar") == """
            Document @1:1-3:4
            ├─ Heading @1:1-2:6 level: 1
            │  └─ Text @1:1-1:4 "foo"
            └─ Paragraph @3:1-3:4
               └─ Text @3:1-3:4 "bar"
            """)
    }

    @Test func headingInBlockQuoteFollowedByParagraph() {
        #expect(tree("> foo\n> ---\n> bar") == """
            Document @1:1-3:6
            └─ BlockQuote @1:1-3:6
               ├─ Heading @1:3-2:6 level: 2
               │  └─ Text @1:3-1:6 "foo"
               └─ Paragraph @3:3-3:6
                  └─ Text @3:3-3:6 "bar"
            """)
    }

    @Test func headingAtEndOfInput() {
        #expect(tree("foo\n---") == """
            Document @1:1-2:4
            └─ Heading @1:1-2:4 level: 2
               └─ Text @1:1-1:4 "foo"
            """)
    }
}
