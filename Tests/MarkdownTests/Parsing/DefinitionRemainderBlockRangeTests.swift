/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// Link reference definitions and attribute definitions at the start of a paragraph are removed from
/// it, so the paragraph or setext heading made of the remaining lines starts at its first remaining
/// content byte.
struct DefinitionRemainderBlockRangeTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func paragraphAfterReferenceDefinition() {
        #expect(tree("[f]:/u\nfoo") == """
            Document @1:1-2:4
            └─ Paragraph @2:1-2:4
               └─ Text @2:1-2:4 "foo"
            """)
    }

    @Test func paragraphAfterMultilineReferenceDefinition() {
        #expect(tree("[a]:u\n\"t\"\nfoo") == """
            Document @1:1-3:4
            └─ Paragraph @3:1-3:4
               └─ Text @3:1-3:4 "foo"
            """)
    }

    @Test func indentedLazyParagraphAfterReferenceDefinition() {
        #expect(tree("[o]:e\n ~") == """
            Document @1:1-2:3
            └─ Paragraph @2:2-2:3
               └─ Text @2:2-2:3 "~"
            """)
    }

    @Test func paragraphAfterAttributeDefinition() {
        #expect(tree("^[a]:b\nfoo") == """
            Document @1:1-2:4
            └─ Paragraph @2:1-2:4
               └─ Text @2:1-2:4 "foo"
            """)
    }

    @Test func listItemParagraphAfterReferenceDefinition() {
        #expect(tree("- [a]:u\n  foo") == """
            Document @1:1-2:6
            └─ UnorderedList @1:1-2:6
               └─ ListItem @1:1-2:6
                  └─ Paragraph @2:3-2:6
                     └─ Text @2:3-2:6 "foo"
            """)
    }

    @Test func setextHeadingAfterReferenceDefinition() {
        #expect(tree("[a]:u\nfoo\n===") == """
            Document @1:1-3:4
            └─ Heading @2:1-3:4 level: 1
               └─ Text @2:1-2:4 "foo"
            """)
    }

    @Test func blockQuoteSetextHeadingAfterReferenceDefinition() {
        #expect(tree("> [a]:u\n b\n>=") == """
            Document @1:1-3:3
            └─ BlockQuote @1:1-3:3
               └─ Heading @2:2-3:3 level: 1
                  └─ Text @2:2-2:3 "b"
            """)
    }
}
