/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// The spaces and tabs removed before a soft or hard line break are not part of the preceding text
/// node, so its source range ends at its last content byte.
struct LineBreakTextRangeTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func textBeforeSoftBreakEndsAtItsContent() {
        #expect(tree("foo \nbar") == """
            Document @1:1-2:4
            └─ Paragraph @1:1-2:4
               ├─ Text @1:1-1:4 "foo"
               ├─ SoftBreak
               └─ Text @2:1-2:4 "bar"
            """)
    }

    @Test func textBeforeTabAndSoftBreakEndsAtItsContent() {
        #expect(tree("a\t\nb") == """
            Document @1:1-2:2
            └─ Paragraph @1:1-2:2
               ├─ Text @1:1-1:2 "a"
               ├─ SoftBreak
               └─ Text @2:1-2:2 "b"
            """)
    }

    @Test func textBeforeHardBreakEndsAtItsContent() {
        #expect(tree("a  \nb") == """
            Document @1:1-2:2
            └─ Paragraph @1:1-2:2
               ├─ Text @1:1-1:2 "a"
               ├─ LineBreak
               └─ Text @2:1-2:2 "b"
            """)
    }
}
