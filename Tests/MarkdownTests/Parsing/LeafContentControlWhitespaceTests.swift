/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A paragraph's or setext heading's raw content has its initial and final whitespace removed (spec
/// "Paragraphs", "Setext headings"), and the spec's whitespace characters include line tabulation
/// (U+000B) and form feed (U+000C).
struct LeafContentControlWhitespaceTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func finalVerticalTabIsRemoved() {
        #expect(tree("foo\u{0B}") == """
            Document @1:1-1:5
            └─ Paragraph @1:1-1:5
               └─ Text @1:1-1:4 "foo"
            """)
    }

    @Test func initialFormFeedIsRemoved() {
        #expect(tree("\u{0C}foo") == """
            Document @1:1-1:5
            └─ Paragraph @1:2-1:5
               └─ Text @1:2-1:5 "foo"
            """)
    }

    @Test func rejectedDefinitionKeepsNoFinalVerticalTab() {
        #expect(tree("[?]:\u{0B}") == """
            Document @1:1-1:6
            └─ Paragraph @1:1-1:6
               └─ Text @1:1-1:5 "[?]:"
            """)
    }

    /// The line ending after an initial run of whitespace is itself whitespace, so it is removed too.
    @Test func initialWhitespaceLineIsRemoved() {
        #expect(tree("\u{0B}\nfoo") == """
            Document @1:1-2:4
            └─ Paragraph @2:1-2:4
               └─ Text @2:1-2:4 "foo"
            """)
    }

    @Test func blockQuoteParagraphTrimsVerticalTabs() {
        #expect(tree("> \u{0B}foo\n> bar\u{0B}") == """
            Document @1:1-2:7
            └─ BlockQuote @1:1-2:7
               └─ Paragraph @1:4-2:7
                  ├─ Text @1:4-1:7 "foo"
                  ├─ SoftBreak
                  └─ Text @2:3-2:6 "bar"
            """)
    }

    @Test func setextHeadingTrimsFormFeeds() {
        #expect(tree("\u{0C}foo\u{0C}\n===") == """
            Document @1:1-2:4
            └─ Heading @1:2-2:4 level: 1
               └─ Text @1:2-1:5 "foo"
            """)
    }

    /// A line holding only a vertical tab is not blank (spec "Blank lines": only spaces or tabs), so it
    /// is a paragraph, whose raw content is empty once its whitespace is removed.
    @Test func verticalTabOnlyLineIsEmptyParagraph() {
        #expect(tree("\u{0B}") == """
            Document @1:1-1:2
            └─ Paragraph @1:1-1:2
            """)
    }

    @Test func paragraphBeforeTableTrimsVerticalTab() {
        #expect(tree("\u{0B}foo\nh|i\n-|-") == """
            Document @1:1-3:4
            ├─ Paragraph @1:2-1:5
            │  └─ Text @1:2-1:5 "foo"
            └─ Table @2:1-3:4 alignments: |-|-|
               ├─ Head @2:1-2:4
               │  ├─ Cell @2:1-2:2
               │  │  └─ Text @2:1-2:2 "h"
               │  └─ Cell @2:3-2:4
               │     └─ Text @2:3-2:4 "i"
               └─ Body
            """)
    }

    @Test func blockQuoteParagraphBeforeTableTrimsVerticalTab() {
        #expect(tree("> \u{0B}foo\n> h|i\n> -|-") == """
            Document @1:1-3:6
            └─ BlockQuote @1:1-3:6
               ├─ Paragraph @1:4-1:7
               │  └─ Text @1:4-1:7 "foo"
               └─ Table @2:3-3:6 alignments: |-|-|
                  ├─ Head @2:3-2:6
                  │  ├─ Cell @2:3-2:4
                  │  │  └─ Text @2:3-2:4 "h"
                  │  └─ Cell @2:5-2:6
                  │     └─ Text @2:5-2:6 "i"
                  └─ Body
            """)
    }

    @Test func verticalTabOnlyLineBeforeTableIsEmptyParagraph() {
        #expect(tree("\u{0B}\nh|i\n-|-") == """
            Document @1:1-3:4
            ├─ Paragraph @1:1-1:2
            └─ Table @2:1-3:4 alignments: |-|-|
               ├─ Head @2:1-2:4
               │  ├─ Cell @2:1-2:2
               │  │  └─ Text @2:1-2:2 "h"
               │  └─ Cell @2:3-2:4
               │     └─ Text @2:3-2:4 "i"
               └─ Body
            """)
    }
}
