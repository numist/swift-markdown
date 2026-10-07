/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A bare link destination contains no ASCII control character and includes parentheses only when they
/// are backslash-escaped or balanced, and a `<…>` destination contains no line ending (spec "Links").
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

    @Test func controlCharacterIsNoDestination() {
        #expect(tree("[a](b\u{1}c)") == """
            Document @1:1-1:9
            └─ Paragraph @1:1-1:9
               └─ Text @1:1-1:9 "[a](b\u{1}c)"
            """)
    }

    @Test func controlCharacterIsNoDefinitionDestination() {
        #expect(tree("[a]: b\u{7F}c\n\n[a]") == """
            Document @1:1-3:4
            ├─ Paragraph @1:1-1:9
            │  └─ Text @1:1-1:9 "[a]: b\u{7F}c"
            └─ Paragraph @3:1-3:4
               └─ Text @3:1-3:4 "[a]"
            """)
    }

    /// A NUL is replaced with U+FFFD (spec "Insecure characters"). A paragraph's leading link reference
    /// definitions are removed before a setext heading underline is considered (spec "Setext headings").
    @Test func nulIsReplacementCharacterInDefinitionDestination() {
        #expect(tree("[a]: b\u{0}c\n===\n\n[a]") == """
            Document @1:1-4:4
            ├─ Paragraph @2:1-2:4
            │  └─ Text @2:1-2:4 "==="
            └─ Paragraph @4:1-4:4
               └─ Link @4:1-4:4 destination: "b\u{FFFD}c"
                  └─ Text @4:2-4:3 "a"
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
