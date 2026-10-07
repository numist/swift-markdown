/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A link reference definition allows whitespace after its colon, between its destination and title, and
/// after its destination or title on its last line, and line tabulation (U+000B) and form feed (U+000C) are
/// whitespace characters (spec "Link reference definitions", "Characters and lines").
struct LinkReferenceDefinitionWhitespaceTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    /// The title of the first link in the last block of `markdown`.
    private func title(_ markdown: String) -> String? {
        let document = Document(parsing: markdown)
        return document.child(at: document.childCount - 1)?.child(at: 0).flatMap { $0 as? Link }?.title
    }

    @Test func lineTabulationAfterDestination() {
        #expect(tree("[a]: b\u{0B}\nc\n\n[a]") == """
            Document @1:1-4:4
            ├─ Paragraph @2:1-2:2
            │  └─ Text @2:1-2:2 "c"
            └─ Paragraph @4:1-4:4
               └─ Link @4:1-4:4 destination: "b"
                  └─ Text @4:2-4:3 "a"
            """)
    }

    @Test func formFeedAfterTitle() {
        let markdown = "[a]: b \"t\"\u{0C}\nc\n\n[a]"
        #expect(tree(markdown) == """
            Document @1:1-4:4
            ├─ Paragraph @2:1-2:2
            │  └─ Text @2:1-2:2 "c"
            └─ Paragraph @4:1-4:4
               └─ Link @4:1-4:4 destination: "b"
                  └─ Text @4:2-4:3 "a"
            """)
        #expect(title(markdown) == "t")
    }

    @Test func lineTabulationAfterColon() {
        #expect(tree("[a]:\u{0B}b\n\n[a]") == """
            Document @1:1-3:4
            └─ Paragraph @3:1-3:4
               └─ Link @3:1-3:4 destination: "b"
                  └─ Text @3:2-3:3 "a"
            """)
    }

    @Test func formFeedBetweenDestinationAndTitle() {
        let markdown = "[a]: b\u{0C}\"t\"\n\n[a]"
        #expect(tree(markdown) == """
            Document @1:1-3:4
            └─ Paragraph @3:1-3:4
               └─ Link @3:1-3:4 destination: "b"
                  └─ Text @3:2-3:3 "a"
            """)
        #expect(title(markdown) == "t")
    }

    @Test func lineTabulationAndFormFeedAroundLineEndingBeforeTitle() {
        let markdown = "[a]: b\u{0B}\n\u{0C}\"t\"\n\n[a]"
        #expect(tree(markdown) == """
            Document @1:1-4:4
            └─ Paragraph @4:1-4:4
               └─ Link @4:1-4:4 destination: "b"
                  └─ Text @4:2-4:3 "a"
            """)
        #expect(title(markdown) == "t")
    }

    @Test func nonWhitespaceAfterLineTabulationIsNoDefinition() {
        #expect(tree("[a]: b\u{0B}c\n\n[a]") == """
            Document @1:1-3:4
            ├─ Paragraph @1:1-1:9
            │  └─ Text @1:1-1:9 "[a]: b\u{0B}c"
            └─ Paragraph @3:1-3:4
               └─ Text @3:1-3:4 "[a]"
            """)
    }
}
