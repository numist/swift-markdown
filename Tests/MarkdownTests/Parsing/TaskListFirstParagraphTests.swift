/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

struct TaskListFirstParagraphTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func markerOnLineAfterBlankItemStart() {
        #expect(tree("-\n  [ ] foo") == """
            Document @1:1-2:10
            └─ UnorderedList @1:1-2:10
               └─ ListItem @1:1-2:10 checkbox: [ ]
                  └─ Paragraph @2:7-2:10
                     └─ Text @2:7-2:10 "foo"
            """)
    }

    @Test func checkedMarkerAfterTrailingSpaceItemStart() {
        #expect(tree("- \n  [x] foo") == """
            Document @1:1-2:10
            └─ UnorderedList @1:1-2:10
               └─ ListItem @1:1-2:10 checkbox: [x]
                  └─ Paragraph @2:7-2:10
                     └─ Text @2:7-2:10 "foo"
            """)
    }

    @Test func setextHeadingFirstBlockIsNoTaskItem() {
        #expect(tree("- [x] v\n  -") == """
            Document @1:1-2:4
            └─ UnorderedList @1:1-2:4
               └─ ListItem @1:1-2:4
                  └─ Heading @1:3-2:4 level: 2
                     └─ Text @1:3-1:8 "[x] v"
            """)
    }

    @Test func setextHeadingAfterCheckboxGapIsNoTaskItem() {
        #expect(tree("- [ ]  \tb\n  =\n") == """
            Document @1:1-3:1
            └─ UnorderedList @1:1-2:4
               └─ ListItem @1:1-2:4
                  └─ Heading @1:3-2:4 level: 1
                     └─ Text @1:3-1:10 "[ ]  \tb"
            """)
    }

    @Test func itemInBlockQuote() {
        #expect(tree("> - [x] foo") == """
            Document @1:1-1:12
            └─ BlockQuote @1:1-1:12
               └─ UnorderedList @1:3-1:12
                  └─ ListItem @1:3-1:12 checkbox: [x]
                     └─ Paragraph @1:9-1:12
                        └─ Text @1:9-1:12 "foo"
            """)
    }

    @Test func nestedItemOnSameLine() {
        #expect(tree("- - [ ] foo") == """
            Document @1:1-1:12
            └─ UnorderedList @1:1-1:12
               └─ ListItem @1:1-1:12
                  └─ UnorderedList @1:3-1:12
                     └─ ListItem @1:3-1:12 checkbox: [ ]
                        └─ Paragraph @1:9-1:12
                           └─ Text @1:9-1:12 "foo"
            """)
    }

    // The marker line is not blank, so it opens the item's paragraph, which the next line continues.
    @Test func markerOnlyLineIsContinuedLazily() {
        #expect(tree("- [ ] \nfoo") == """
            Document @1:1-2:4
            └─ UnorderedList @1:1-2:4
               └─ ListItem @1:1-2:4 checkbox: [ ]
                  └─ Paragraph @2:1-2:4
                     └─ Text @2:1-2:4 "foo"
            """)
    }

    @Test func markerOnlyItemHasNoParagraph() {
        #expect(tree("- [ ] ") == """
            Document @1:1-1:7
            └─ UnorderedList @1:1-1:6
               └─ ListItem @1:1-1:6 checkbox: [ ]
            """)
    }

    // A line ending is a whitespace character, so it can be the whitespace after the marker.
    @Test func markerBeforeLineEnding() {
        #expect(tree("- [ ]\nx") == """
            Document @1:1-2:2
            └─ UnorderedList @1:1-2:2
               └─ ListItem @1:1-2:2 checkbox: [ ]
                  └─ Paragraph @2:1-2:2
                     └─ Text @2:1-2:2 "x"
            """)
    }

    // The paragraph's initial whitespace, a line tabulation here, is removed (Paragraphs), so
    // the paragraph begins with the marker.
    @Test func lineTabulationBeforeMarker() {
        #expect(tree("- \u{0B}[x] \n`") == """
            Document @1:1-2:2
            └─ UnorderedList @1:1-2:2
               └─ ListItem @1:1-2:2 checkbox: [x]
                  └─ Paragraph @2:1-2:2
                     └─ Text @2:1-2:2 "`"
            """)
    }

    @Test func formFeedSeparatesMarker() {
        #expect(tree("- [ ]\u{0C}a") == """
            Document @1:1-1:8
            └─ UnorderedList @1:1-1:8
               └─ ListItem @1:1-1:8 checkbox: [ ]
                  └─ Paragraph @1:7-1:8
                     └─ Text @1:7-1:8 "a"
            """)
    }

    // Link reference definitions are removed from the paragraph's raw content before its marker is
    // considered; `[x] [a]: /u` does not begin with a definition.
    @Test func definitionAfterMarkerIsText() {
        #expect(tree("- [x] [a]: /u") == """
            Document @1:1-1:14
            └─ UnorderedList @1:1-1:14
               └─ ListItem @1:1-1:14 checkbox: [x]
                  └─ Paragraph @1:7-1:14
                     └─ Text @1:7-1:14 "[a]: /u"
            """)
    }

    // A definition counts as a block of its list item, so a marker after one doesn't begin the item's first block.
    @Test func markerAfterDefinitionIsText() {
        #expect(tree("- [a]: /u\n  [x] foo") == """
            Document @1:1-2:10
            └─ UnorderedList @1:1-2:10
               └─ ListItem @1:1-2:10
                  └─ Paragraph @2:3-2:10
                     └─ Text @2:3-2:10 "[x] foo"
            """)
    }

    @Test func tableFirstBlockIsNoTaskItem() {
        #expect(tree("- [ ] a|b\n  -|-") == """
            Document @1:1-2:6
            └─ UnorderedList @1:1-2:6
               └─ ListItem @1:1-2:6
                  └─ Table @1:3-2:6 alignments: |-|-|
                     ├─ Head @1:3-1:10
                     │  ├─ Cell @1:3-1:8
                     │  │  └─ Text @1:3-1:8 "[ ] a"
                     │  └─ Cell @1:9-1:10
                     │     └─ Text @1:9-1:10 "b"
                     └─ Body
            """)
    }

    // The table takes `a|b` as its header row, so the paragraph before it holds only the marker, and the item is a
    // task list item.
    @Test func checkboxLineBeforeTableMakesTaskItem() {
        #expect(tree("- [ ] \n  a|b\n  -|-") == """
            Document @1:1-3:6
            └─ UnorderedList @1:1-3:6
               └─ ListItem @1:1-3:6 checkbox: [ ]
                  └─ Table @2:3-3:6 alignments: |-|-|
                     ├─ Head @2:3-2:6
                     │  ├─ Cell @2:3-2:4
                     │  │  └─ Text @2:3-2:4 "a"
                     │  └─ Cell @2:5-2:6
                     │     └─ Text @2:5-2:6 "b"
                     └─ Body
            """)
    }
}
