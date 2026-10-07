/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// The lines before a table's header row form a paragraph of their own, so link reference definitions at its
/// start are removed (spec "Link reference definitions"), and in a list item it is the paragraph a task list
/// item marker begins (spec "Task list items (extension)").
struct TableSplitParagraphDefinitionTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription()
    }


    @Test func definitionBeforeTableIsRemoved() {
        #expect(tree("[a]: /u\nfoo\nx|y\n-|-\n\n[a]") == """
            Document
            ├─ Paragraph
            │  └─ Text "foo"
            ├─ Table alignments: |-|-|
            │  ├─ Head
            │  │  ├─ Cell
            │  │  │  └─ Text "x"
            │  │  └─ Cell
            │  │     └─ Text "y"
            │  └─ Body
            └─ Paragraph
               └─ Link destination: "/u"
                  └─ Text "a"
            """)
    }

    @Test func onlyDefinitionsBeforeTableInBlockQuote() {
        #expect(tree("> [a]: /u\n> x|y\n> -|-") == """
            Document
            └─ BlockQuote
               └─ Table alignments: |-|-|
                  ├─ Head
                  │  ├─ Cell
                  │  │  └─ Text "x"
                  │  └─ Cell
                  │     └─ Text "y"
                  └─ Body
            """)
    }

    @Test func taskMarkerAfterDefinitionBeforeTable() {
        #expect(tree("- [a]: /u\n  [ ] foo\n  x|y\n  -|-") == """
            Document
            └─ UnorderedList
               └─ ListItem checkbox: [ ]
                  ├─ Paragraph
                  │  └─ Text "foo"
                  └─ Table alignments: |-|-|
                     ├─ Head
                     │  ├─ Cell
                     │  │  └─ Text "x"
                     │  └─ Cell
                     │     └─ Text "y"
                     └─ Body
            """)
    }

    @Test func lineTabulationSeparatedMarkerBeforeTable() {
        #expect(tree("- [ ]\u{0B}\n  x|y\n  -|-") == """
            Document
            └─ UnorderedList
               └─ ListItem checkbox: [ ]
                  └─ Table alignments: |-|-|
                     ├─ Head
                     │  ├─ Cell
                     │  │  └─ Text "x"
                     │  └─ Cell
                     │     └─ Text "y"
                     └─ Body
            """)
    }
}
