/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Link reference definitions in a block quote or list item, whose paragraph lines are not contiguous in the source.
/// A definition's label, title, and the whitespace before its destination or title may span a line ending (Link
/// reference definitions).
@Suite("Definitions across the lines of a container's paragraph")
struct ContainerDefinitionLineJoinTests {

    @Test("a label, the whitespace before a destination, and a title each span a line ending")
    func labelWhitespaceAndTitleSpanLineEnding() {
        #expect(TreeDump.dump("> [a\n> b]: /u\n> [c]:\n> /v\n> 'T\n> t'\n> [a b] [c]", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-7:12
              block_quote @1:1-7:12
                paragraph @7:3-7:12
                  link "/u" "" @7:3-7:8
                    text "a b" @7:4-7:7
                  text " " @7:8-7:9
                  link "/v" "T\\nt" @7:9-7:12
                    text "c" @7:10-7:11

            """)
    }

    @Test("a title on the line after the destination belongs to the definition")
    func titleOnNextLine() {
        #expect(TreeDump.dump("- [a]: /u\n  \"t\"\n  [a]", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:6
              list bullet '-' tight @1:1-3:6
                item @1:1-3:6
                  paragraph @3:3-3:6
                    link "/u" "t" @3:3-3:6
                      text "a" @3:4-3:5

            """)
    }

    @Test("an unclosed title on the next line leaves the definition without it")
    func unclosedTitleOnNextLine() {
        #expect(TreeDump.dump("> [a]: /u\n> \"t\n> [a]", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @2:3-3:6
                  text "\\"t" @2:3-2:5
                  softbreak @-
                  link "/u" "" @3:3-3:6
                    text "a" @3:4-3:5

            """)
    }

    @Test("definitions on lines ending in CR LF")
    func carriageReturnLineFeedLines() {
        #expect(TreeDump.dump("> [a]: /u\r\n> [b]: /v 't'\r\n> [a][b]", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:9
              block_quote @1:1-3:9
                paragraph @3:3-3:9
                  link "/v" "t" @3:3-3:9
                    text "a" @3:4-3:5

            """)
    }

    @Test("the paragraph after a definition has the source ranges of its own bytes")
    func textAfterDefinitions() {
        #expect(TreeDump.dump("> [a]: /uuuuuuuu\n> *b* [a]\n> c", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:4
              block_quote @1:1-3:4
                paragraph @2:3-3:4
                  emph @2:3-2:6
                    text "b" @2:4-2:5
                  text " " @2:6-2:7
                  link "/uuuuuuuu" "" @2:7-2:10
                    text "a" @2:8-2:9
                  softbreak @-
                  text "c" @3:3-3:4

            """)
    }

    @Test("an inline link's destination and title begin on later lines")
    func inlineLinkAcrossLines() {
        #expect(TreeDump.dump("> [x](\n> /u\n> \"t\")", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-3:7
              block_quote @1:1-3:7
                paragraph @1:3-3:7
                  link "/u" "t" @1:3-3:7
                    text "x" @1:4-1:5

            """)
    }
}
