/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// A link label holds at least one non-whitespace character (spec "Links"), so a whitespace-only `[ ]`
/// after a shortcut reference is neither a link label nor `[]`, and stays text.
struct WhitespaceOnlySecondLabelTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func spaceOnlyLabel() {
        #expect(tree("[x][ ]\n\n[x]: /u") == """
            Document @1:1-3:8
            └─ Paragraph @1:1-1:7
               ├─ Link @1:1-1:4 destination: "/u"
               │  └─ Text @1:2-1:3 "x"
               └─ Text @1:4-1:7 "[ ]"
            """)
    }

    @Test func lineEndingOnlyLabel() {
        #expect(tree("[az]:|\n\n*[az][\n ]") == """
            Document @1:1-4:3
            └─ Paragraph @3:1-4:3
               ├─ Text @3:1-3:2 "*"
               ├─ Link @3:2-3:6 destination: "|"
               │  └─ Text @3:3-3:5 "az"
               ├─ Text @3:6-3:7 "["
               ├─ SoftBreak
               └─ Text @4:2-4:3 "]"
            """)
    }

    @Test func collapsedReference() {
        #expect(tree("[x][]\n\n[x]: /u") == """
            Document @1:1-3:8
            └─ Paragraph @1:1-1:6
               └─ Link @1:1-1:6 destination: "/u"
                  └─ Text @1:2-1:3 "x"
            """)
    }
}
