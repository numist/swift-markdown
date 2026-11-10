/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A link label holds at least one non-whitespace character (Links), so a whitespace-only `[ ]` after a
/// shortcut reference whose text spans a line ending is not a link label: the shortcut reference forms and
/// `[ ]` stays text, in a paragraph, a block quote and a list item alike.
struct WhitespaceOnlySecondLabelAcrossLinesTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func linkInParagraph() {
        #expect(tree("[foo\nbar][ ]\n\n[foo bar]: /url") == """
            Document @1:1-4:16
            └─ Paragraph @1:1-2:8
               ├─ Link @1:1-2:5 destination: "/url"
               │  ├─ Text @1:2-1:5 "foo"
               │  ├─ SoftBreak
               │  └─ Text @2:1-2:4 "bar"
               └─ Text @2:5-2:8 "[ ]"
            """)
    }

    @Test func imageInParagraph() {
        #expect(tree("![foo\nbar][ ]\n\n[foo bar]: /url") == """
            Document @1:1-4:16
            └─ Paragraph @1:1-2:8
               ├─ Image @1:1-2:5 source: "/url"
               │  ├─ Text @1:3-1:6 "foo"
               │  ├─ SoftBreak
               │  └─ Text @2:1-2:4 "bar"
               └─ Text @2:5-2:8 "[ ]"
            """)
    }

    @Test func linkInBlockQuote() {
        #expect(tree("> [foo\n> bar][ ]\n\n[foo bar]: /url") == """
            Document @1:1-4:16
            └─ BlockQuote @1:1-2:10
               └─ Paragraph @1:3-2:10
                  ├─ Link @1:3-2:7 destination: "/url"
                  │  ├─ Text @1:4-1:7 "foo"
                  │  ├─ SoftBreak
                  │  └─ Text @2:3-2:6 "bar"
                  └─ Text @2:7-2:10 "[ ]"
            """)
    }

    @Test func imageInBlockQuote() {
        #expect(tree("> ![foo\n> bar][ ]\n\n[foo bar]: /url") == """
            Document @1:1-4:16
            └─ BlockQuote @1:1-2:10
               └─ Paragraph @1:3-2:10
                  ├─ Image @1:3-2:7 source: "/url"
                  │  ├─ Text @1:5-1:8 "foo"
                  │  ├─ SoftBreak
                  │  └─ Text @2:3-2:6 "bar"
                  └─ Text @2:7-2:10 "[ ]"
            """)
    }

    @Test func linkInListItem() {
        #expect(tree("- [foo\n  bar][ ]\n\n[foo bar]: /url") == """
            Document @1:1-4:16
            └─ UnorderedList @1:1-2:10
               └─ ListItem @1:1-2:10
                  └─ Paragraph @1:3-2:10
                     ├─ Link @1:3-2:7 destination: "/url"
                     │  ├─ Text @1:4-1:7 "foo"
                     │  ├─ SoftBreak
                     │  └─ Text @2:3-2:6 "bar"
                     └─ Text @2:7-2:10 "[ ]"
            """)
    }

    @Test func imageInListItem() {
        #expect(tree("- ![foo\n  bar][ ]\n\n[foo bar]: /url") == """
            Document @1:1-4:16
            └─ UnorderedList @1:1-2:10
               └─ ListItem @1:1-2:10
                  └─ Paragraph @1:3-2:10
                     ├─ Image @1:3-2:7 source: "/url"
                     │  ├─ Text @1:5-1:8 "foo"
                     │  ├─ SoftBreak
                     │  └─ Text @2:3-2:6 "bar"
                     └─ Text @2:7-2:10 "[ ]"
            """)
    }

    @Test func imageInBlockQuoteWithSeveralSpaces() {
        #expect(tree("> ![foo\n> bar][   ]\n\n[foo bar]: /url") == """
            Document @1:1-4:16
            └─ BlockQuote @1:1-2:12
               └─ Paragraph @1:3-2:12
                  ├─ Image @1:3-2:7 source: "/url"
                  │  ├─ Text @1:5-1:8 "foo"
                  │  ├─ SoftBreak
                  │  └─ Text @2:3-2:6 "bar"
                  └─ Text @2:7-2:12 "[   ]"
            """)
    }
}
