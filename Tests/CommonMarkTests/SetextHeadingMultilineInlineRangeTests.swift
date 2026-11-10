/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges of emphasis, strong emphasis and links that span a soft line break inside a
/// multi-line setext heading with an indented first line. Each ends just past its closing delimiter on
/// that delimiter's own line, before the underline.
@Suite("Source ranges of emphasis and links across the lines of a setext heading")
struct SetextHeadingMultilineInlineRangeTests {

    @Test("emphasis spanning lines ends on the closer's line, not the underline line")
    func emphasisEndsOnCloserLine() {
        #expect(TreeDump.dump("  Foo *bar\nbaz*\n====", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:5
              heading 1 @1:3-3:5
                text "Foo " @1:3-1:7
                emph @1:7-2:5
                  text "bar" @1:8-1:11
                  softbreak @-
                  text "baz" @2:1-2:4

            """)
    }

    @Test("strong emphasis spanning lines ends on the closer's line, not the underline line")
    func strongEmphasisEndsOnCloserLine() {
        #expect(TreeDump.dump("  Foo **bar\nbaz**\n====", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:5
              heading 1 @1:3-3:5
                text "Foo " @1:3-1:7
                strong @1:7-2:6
                  text "bar" @1:9-1:12
                  softbreak @-
                  text "baz" @2:1-2:4

            """)
    }

    @Test("link spanning lines ends on the closer's line, not the underline line")
    func linkEndsOnCloserLine() {
        #expect(TreeDump.dump("  Foo [bar\nbaz](/u)\n====", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:5
              heading 1 @1:3-3:5
                text "Foo " @1:3-1:7
                link "/u" "" @1:7-2:9
                  text "bar" @1:8-1:11
                  softbreak @-
                  text "baz" @2:1-2:4

            """)
    }
}
