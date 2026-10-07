/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A bare link destination includes parentheses only when they are backslash-escaped or balanced, and
/// a `<…>` destination contains no line ending (spec "Links").
struct LinkDestinationSpecTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func unbalancedParenthesisIsNoDestination() {
        #expect(tree("[a]((\n'b')") == """
            Document @1:1-2:5
            └─ Paragraph @1:1-2:5
               ├─ Text @1:1-1:6 "[a](("
               ├─ SoftBreak
               └─ Text @2:1-2:5 "‘b’)"
            """)
    }

    @Test func escapedParenthesisIsDestination() {
        #expect(tree("[a](\\()") == """
            Document @1:1-1:8
            └─ Paragraph @1:1-1:8
               └─ Link @1:1-1:8 destination: "("
                  └─ Text @1:2-1:3 "a"
            """)
    }

    @Test func pointyDestinationWithBackslashBeforeLineEndingIsNoDestination() {
        #expect(tree("[a](<b\\\nc>)") == """
            Document @1:1-2:4
            └─ Paragraph @1:1-2:4
               ├─ Text @1:1-1:7 "[a](<b"
               ├─ LineBreak
               └─ Text @2:1-2:4 "c>)"
            """)
    }

    @Test func pointyDestinationWithEscapedAngleBracket() {
        #expect(tree("[a](<b\\>c>)") == """
            Document @1:1-1:12
            └─ Paragraph @1:1-1:12
               └─ Link @1:1-1:12 destination: "b>c"
                  └─ Text @1:2-1:3 "a"
            """)
    }
}
