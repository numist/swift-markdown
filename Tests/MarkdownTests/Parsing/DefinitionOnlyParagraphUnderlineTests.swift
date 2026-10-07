/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A paragraph made only of link reference definitions stays open while the next line is examined, so
/// a setext-underline-shaped line that cannot interrupt a paragraph continues it and, once the
/// definitions are removed, is the paragraph's text.
struct DefinitionOnlyParagraphUnderlineTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    /// An empty list item cannot interrupt a paragraph (spec "List items"), so `-` continues the
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

    @Test func equalsUnderlineIsParagraphText() {
        #expect(tree("[o]:o\n==\nx") == """
            Document @1:1-3:2
            └─ Paragraph @2:1-3:2
               ├─ Text @2:1-2:3 "=="
               ├─ SoftBreak
               └─ Text @3:1-3:2 "x"
            """)
    }

    /// A thematic break can interrupt a paragraph (spec "Thematic breaks").
    @Test func thematicBreakInterrupts() {
        #expect(tree("[o]:o\n---") == """
            Document @1:1-2:4
            └─ ThematicBreak @2:1-2:4
            """)
    }

    @Test func pipeDefinitionWithDashIsNotTable() {
        #expect(tree("[o]:o|\n-") == """
            Document @1:1-2:2
            └─ Paragraph @2:1-2:2
               └─ Text @2:1-2:2 "-"
            """)
    }

    @Test func indentedUnderlineBeforeTableIsPrecedingParagraph() {
        #expect(tree("[a]:/u\n  ===\nh|i\n-|-") == """
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
            """)
    }
}
