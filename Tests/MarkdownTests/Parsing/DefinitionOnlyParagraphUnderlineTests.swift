/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A paragraph made only of link reference definitions stays open while the next line is examined, so a
/// setext-underline-shaped line that cannot interrupt a paragraph continues it. Once the definitions are removed, that
/// line is the first line of a paragraph, or the header row of a table when a delimiter row follows it (Tables
/// (extension)).
struct DefinitionOnlyParagraphUnderlineTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    /// An empty list item cannot interrupt a paragraph (List items), so `-` continues the
    /// paragraph.
    @Test func loneDashIsParagraphText() {
        #expect(tree("[o]:o\n-") == """
            Document @1:1-2:2
            └─ Paragraph @2:1-2:2
               └─ Text @2:1-2:2 "-"
            """)
    }

    @Test func loneDashAfterMultilineDefinitionIsParagraphText() {
        #expect(tree("[f]:\n \"\n-") == """
            Document @1:1-3:2
            └─ Paragraph @3:1-3:2
               └─ Text @3:1-3:2 "-"
            """)
    }

    @Test func loneDashInListItemIsParagraphText() {
        #expect(tree("- [o]:o\n  -") == """
            Document @1:1-2:4
            └─ UnorderedList @1:1-2:4
               └─ ListItem @1:1-2:4
                  └─ Paragraph @2:3-2:4
                     └─ Text @2:3-2:4 "-"
            """)
    }

    /// A thematic break can interrupt a paragraph (Thematic breaks).
    @Test(arguments: [
        ("[o]:o\n---", """
            Document @1:1-2:4
            └─ ThematicBreak @2:1-2:4
            """),
        ("[a]: /u\n---\nx", """
            Document @1:1-3:2
            ├─ ThematicBreak @2:1-2:4
            └─ Paragraph @3:1-3:2
               └─ Text @3:1-3:2 "x"
            """),
    ])
    func thematicBreakInterrupts(_ markdown: String, _ expected: String) {
        #expect(tree(markdown) == expected)
    }

    @Test func pipeDefinitionWithDashIsNotTable() {
        #expect(tree("[o]:o|\n-") == """
            Document @1:1-2:2
            └─ Paragraph @2:1-2:2
               └─ Text @2:1-2:2 "-"
            """)
    }

    @Test(arguments: [
        ("[a]:/u\n  ===\nh|i\n-|-", """
            Document @1:1-4:4
            ├─ Paragraph @2:3-2:6
            │  └─ Text @2:3-2:6 "==="
            └─ Table @3:1-4:4 alignments: |-|-|
               ├─ Head @3:1-3:4
               │  ├─ Cell @3:1-3:2
               │  │  └─ Text @3:1-3:2 "h"
               │  └─ Cell @3:3-3:4
               │     └─ Text @3:3-3:4 "i"
               └─ Body
            """),
        ("[r]:o\n=\nfoo\n|-", """
            Document @1:1-4:3
            ├─ Paragraph @2:1-2:2
            │  └─ Text @2:1-2:2 "="
            └─ Table @3:1-4:3 alignments: |-|
               ├─ Head @3:1-3:4
               │  └─ Cell @3:1-3:4
               │     └─ Text @3:1-3:4 "foo"
               └─ Body
            """),
    ])
    func underlineBeforeTableIsPrecedingParagraph(_ markdown: String, _ expected: String) {
        #expect(tree(markdown) == expected)
    }

    @Test func underlineIsTableHeaderRow() {
        #expect(tree("[r]:o\n=\n|-") == """
            Document @1:1-3:3
            └─ Table @2:1-3:3 alignments: |-|
               ├─ Head @2:1-2:2
               │  └─ Cell @2:1-2:2
               │     └─ Text @2:1-2:2 "="
               └─ Body
            """)
    }

    @Test func underlineAfterMultilineDefinitionIsTableHeaderRow() {
        #expect(tree("[f]:\n \"\n=\n|-") == """
            Document @1:1-4:3
            └─ Table @3:1-4:3 alignments: |-|
               ├─ Head @3:1-3:2
               │  └─ Cell @3:1-3:2
               │     └─ Text @3:1-3:2 "="
               └─ Body
            """)
    }

    @Test func underlineInBlockQuoteIsTableHeaderRow() {
        #expect(tree("> [r]:o\n> =\n> |-") == """
            Document @1:1-3:5
            └─ BlockQuote @1:1-3:5
               └─ Table @2:3-3:5 alignments: |-|
                  ├─ Head @2:3-2:4
                  │  └─ Cell @2:3-2:4
                  │     └─ Text @2:3-2:4 "="
                  └─ Body
            """)
    }

    /// Once the definitions are removed there is no content to underline, so no setext heading forms (Setext
    /// headings). Each block starts at its first content byte.
    @Test(arguments: [
        ("[o]:o\n==\nx", """
            Document @1:1-3:2
            └─ Paragraph @2:1-3:2
               ├─ Text @2:1-2:3 "=="
               ├─ SoftBreak
               └─ Text @3:1-3:2 "x"
            """),
        ("[a]: /u\n===\nx", """
            Document @1:1-3:2
            └─ Paragraph @2:1-3:2
               ├─ Text @2:1-2:4 "==="
               ├─ SoftBreak
               └─ Text @3:1-3:2 "x"
            """),
        ("[r]:o\n=\nx", """
            Document @1:1-3:2
            └─ Paragraph @2:1-3:2
               ├─ Text @2:1-2:2 "="
               ├─ SoftBreak
               └─ Text @3:1-3:2 "x"
            """),
    ])
    func equalsUnderlineAfterDefinitionIsParagraphText(_ markdown: String, _ expected: String) {
        #expect(tree(markdown) == expected)
    }

    /// The link reference definition before `===` defines `[foo]`, so the later `[foo]` is a link.
    @Test func definitionBeforeEqualsUnderlineIsDefined() {
        #expect(tree("[foo]: /url\n===\n[foo]") == """
            Document @1:1-3:6
            └─ Paragraph @2:1-3:6
               ├─ Text @2:1-2:4 "==="
               ├─ SoftBreak
               └─ Link @3:1-3:6 destination: "/url"
                  └─ Text @3:2-3:5 "foo"
            """)
    }

    /// Content before the underline forms a setext heading, and the link reference definition after it is
    /// removed from the next paragraph.
    @Test func contentBeforeUnderlineIsSetextHeading() {
        #expect(tree("z\n===\n[a]: /u\nx") == """
            Document @1:1-4:2
            ├─ Heading @1:1-2:4 level: 1
            │  └─ Text @1:1-1:2 "z"
            └─ Paragraph @4:1-4:2
               └─ Text @4:1-4:2 "x"
            """)
    }
}
