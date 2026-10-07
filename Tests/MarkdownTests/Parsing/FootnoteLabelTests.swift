/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(Footnotes) import Markdown
import Testing

/// Footnote labels follow the link label rules (spec "Links"): unescaped square brackets are not
/// allowed inside them, and a reference matches a definition when their labels are equal after
/// normalization, which collapses whitespace, line endings included.
struct FootnoteLabelTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown, options: .footnotes).debugDescription(options: .printSourceLocations)
    }

    @Test func definitionLabelWithUnescapedBracketIsText() {
        #expect(tree("[^[]:[^[]]") == """
            Document @1:1-1:11
            └─ Paragraph @1:1-1:11
               └─ Text @1:1-1:11 "[^[]:[^[]]"
            """)
    }

    @Test func definitionLabelWithEscapedBracket() {
        #expect(tree("[^\\]]: x\n\n[^\\]]") == """
            Document @1:1-3:6
            ├─ Paragraph @3:1-3:6
            │  └─ FootnoteReference @3:1-3:6 label: "\\]" index: 1
            └─ FootnoteDefinition @1:1-2:1 label: "\\]"
               └─ Paragraph @1:8-1:9
                  └─ Text @1:8-1:9 "x"
            """)
    }

    @Test func referenceLabelSpanningLineEnding() {
        #expect(tree("[^\na]\n\n[^a]: x") == """
            Document @1:1-4:8
            ├─ Paragraph @1:1-2:3
            │  └─ FootnoteReference @1:1-2:3 label: "a" index: 1
            └─ FootnoteDefinition @4:1-4:8 label: "a"
               └─ Paragraph @4:7-4:8
                  └─ Text @4:7-4:8 "x"
            """)
    }

    @Test func unresolvedReferenceLabelSpanningLineEndingIsText() {
        #expect(tree("[^\na]") == """
            Document @1:1-2:3
            └─ Paragraph @1:1-2:3
               ├─ Text @1:1-1:3 "[^"
               ├─ SoftBreak
               └─ Text @2:1-2:3 "a]"
            """)
    }
}
