/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import Testing

/// An inline attribute is `^[text](attributes)` or `^[text][label]` where `label` names an attribute
/// definition. As with a full reference link whose label matches no definition (spec "Links"), a
/// following `[label]` that names no attribute definition is not part of the construct and stays text.
struct InlineAttributeUnresolvedLabelTests {
    private func tree(_ markdown: String) -> String {
        Document(parsing: markdown).debugDescription(options: .printSourceLocations)
    }

    @Test func emptyTextBeforeEmptyBrackets() {
        #expect(tree("^[][]") == """
            Document @1:1-1:6
            └─ Paragraph @1:1-1:6
               └─ Text @1:1-1:6 "^[][]"
            """)
    }

    @Test func inlineFormFollowedByUnresolvedLabel() {
        #expect(tree("^[](x)[undef]") == """
            Document @1:1-1:14
            └─ Paragraph @1:1-1:14
               ├─ InlineAttributes @1:1-1:7 attributes: `x`
               └─ Text @1:7-1:14 "[undef]"
            """)
    }

    @Test func inlineFormFollowedByUnresolvedLabelAndText() {
        #expect(tree("^[](x)[undef]y") == """
            Document @1:1-1:15
            └─ Paragraph @1:1-1:15
               ├─ InlineAttributes @1:1-1:7 attributes: `x`
               └─ Text @1:7-1:15 "[undef]y"
            """)
    }

    @Test func unresolvedLabelSpanningLineEnding() {
        #expect(tree("[^[][\n]]") == """
            Document @1:1-2:3
            └─ Paragraph @1:1-2:3
               ├─ Text @1:1-1:6 "[^[]["
               ├─ SoftBreak
               └─ Text @2:1-2:3 "]]"
            """)
    }

    @Test func resolvedLabel() {
        #expect(tree("^[a][k]\n\n^[k]: x") == """
            Document @1:1-3:8
            └─ Paragraph @1:1-1:8
               └─ InlineAttributes @1:1-1:8 attributes: `x`
                  └─ Text @1:3-1:4 "a"
            """)
    }
}
