/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Ordered-list marker followed by a tab")
struct OrderedMarkerTabExpansionTests {

    @Test("period marker: tab then spaces reaching the code threshold is a code block")
    func periodMarkerTabIsCodeBlock() {
        #expect(TreeDump.dump("1.\t   z", options: []) == """
            document
              list ordered start=1 delim=period tight
                item
                  code_block "" "z\\n"

            """)
        #expect(codeBlockKinds("1.\t   z") == ["code_block indented fence=none length=0 offset=0"])
    }

    @Test("paren marker: tab then spaces reaching the code threshold is a code block")
    func parenMarkerTabIsCodeBlock() {
        #expect(TreeDump.dump("1)\t   z", options: []) == """
            document
              list ordered start=1 delim=paren tight
                item
                  code_block "" "z\\n"

            """)
        #expect(codeBlockKinds("1)\t   z") == ["code_block indented fence=none length=0 offset=0"])
    }

    @Test("period marker: five literal spaces is a code block")
    func periodMarkerLiteralSpacesIsCodeBlock() {
        #expect(TreeDump.dump("1.     z", options: []) == """
            document
              list ordered start=1 delim=period tight
                item
                  code_block "" "z\\n"

            """)
        #expect(codeBlockKinds("1.     z") == ["code_block indented fence=none length=0 offset=0"])
    }

    @Test("period marker: tab-only gap stays a paragraph")
    func periodMarkerTabOnlyIsParagraph() {
        #expect(TreeDump.dump("1.\tz", options: []) == """
            document
              list ordered start=1 delim=period tight
                item
                  paragraph
                    text "z"

            """)
    }

    // The tab after `12.` spans one column, so the indentation is four columns.
    @Test("wide marker: tab plus three spaces stays a paragraph")
    func wideMarkerTabStaysParagraph() {
        #expect(TreeDump.dump("12.\t   z", options: []) == """
            document
              list ordered start=12 delim=period tight
                item
                  paragraph
                    text "z"

            """)
    }

    @Test("bullet marker: tab then spaces is a code block")
    func bulletMarkerTabIsCodeBlock() {
        #expect(TreeDump.dump("-\t   z", options: []) == """
            document
              list bullet '-' tight
                item
                  code_block "" " z\\n"

            """)
        #expect(codeBlockKinds("-\t   z") == ["code_block indented fence=none length=0 offset=0"])
    }

    @Test("ordered marker, tab, then nested bullet marker opens a nested list")
    func orderedMarkerTabThenNestedBullet() {
        #expect(TreeDump.dump("1.\t- x", options: []) == """
            document
              list ordered start=1 delim=period tight
                item
                  list bullet '-' tight
                    item
                      paragraph
                        text "x"

            """)
    }

    @Test("positions: an ordered item after a tab maps content back to source bytes")
    func positionsMapBackToSource() {
        #expect(TreeDump.dump("1.\t   z", options: [.sourcePosition], sourceRanges: true) == """
            document @1:1-1:8
              list ordered start=1 delim=period tight @1:1-1:8
                item @1:1-1:8
                  code_block "" "z\\n" @1:7-1:8

            """)
        #expect(codeBlockKinds("1.\t   z", options: [.sourcePosition]) == ["code_block indented fence=none length=0 offset=0"])
    }
}
