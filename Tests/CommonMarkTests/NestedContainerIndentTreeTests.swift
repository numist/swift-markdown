/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Items nested one level inside the previous one by indentation alone, and footnote definitions indented by four spaces.
///
/// A line is tested against every open container in turn, each consuming its own content column from the line's
/// leading whitespace, so the tree for these shapes depends on how that whitespace is shared out among the containers.
@Suite("Nested container indentation")
struct NestedContainerIndentTreeTests {

    static let options: MarkdownDocument.ParseOptions = [.sourcePosition, .footnotes]

    @Test
    func bulletItemsNestedByTwoSpaces() {
        let source = "- a\n  - b\n    - c\n      - d\n"
        #expect(TreeDump.dump(source, options: Self.options, sourceRanges: true) == """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:10
                item @1:1-4:10
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  list bullet '-' tight @2:3-4:10
                    item @2:3-4:10
                      paragraph @2:5-2:6
                        text "b" @2:5-2:6
                      list bullet '-' tight @3:5-4:10
                        item @3:5-4:10
                          paragraph @3:7-3:8
                            text "c" @3:7-3:8
                          list bullet '-' tight @4:7-4:10
                            item @4:7-4:10
                              paragraph @4:9-4:10
                                text "d" @4:9-4:10

            """)
    }

    @Test
    func bulletItemsNestedByTabs() {
        let source = "- a\n\t- b\n\t\t- c\n\t\t\t- d\n"
        #expect(TreeDump.dump(source, options: Self.options, sourceRanges: true) == """
            document @1:1-5:1
              list bullet '-' tight @1:1-4:7
                item @1:1-4:7
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  list bullet '-' tight @2:2-4:7
                    item @2:2-4:7
                      paragraph @2:4-2:5
                        text "b" @2:4-2:5
                      list bullet '-' tight @3:3-4:7
                        item @3:3-4:7
                          paragraph @3:5-3:6
                            text "c" @3:5-3:6
                          list bullet '-' tight @4:4-4:7
                            item @4:4-4:7
                              paragraph @4:6-4:7
                                text "d" @4:6-4:7

            """)
    }

    @Test
    func linesInDeepestItemAfterShallowerLines() {
        let source = "- a\n  - b\n    - c\n    c2\n  b2\n\n      - d\n    e\n   f\n"
        #expect(TreeDump.dump(source, options: Self.options, sourceRanges: true) == """
            document @1:1-10:1
              list bullet '-' tight @1:1-9:5
                item @1:1-9:5
                  paragraph @1:3-1:4
                    text "a" @1:3-1:4
                  list bullet '-' tight @2:3-9:5
                    item @2:3-9:5
                      paragraph @2:5-2:6
                        text "b" @2:5-2:6
                      list bullet '-' loose @3:5-9:5
                        item @3:5-9:5
                          paragraph @3:7-5:5
                            text "c" @3:7-3:8
                            softbreak @-
                            text "c2" @4:5-4:7
                            softbreak @-
                            text "b2" @5:3-5:5
                          list bullet '-' tight @7:7-9:5
                            item @7:7-9:5
                              paragraph @7:9-9:5
                                text "d" @7:9-7:10
                                softbreak @-
                                text "e" @8:5-8:6
                                softbreak @-
                                text "f" @9:4-9:5

            """)
    }

    @Test
    func orderedItemsNestedByMarkerWidth() {
        let source = "1. a\n   1. b\n      1. c\n         1. d\n\n        e\n"
        #expect(TreeDump.dump(source, options: Self.options, sourceRanges: true) == """
            document @1:1-7:1
              list ordered start=1 delim=period tight @1:1-6:10
                item @1:1-6:10
                  paragraph @1:4-1:5
                    text "a" @1:4-1:5
                  list ordered start=1 delim=period loose @2:4-6:10
                    item @2:4-6:10
                      paragraph @2:7-2:8
                        text "b" @2:7-2:8
                      list ordered start=1 delim=period tight @3:7-4:14
                        item @3:7-4:14
                          paragraph @3:10-3:11
                            text "c" @3:10-3:11
                          list ordered start=1 delim=period tight @4:10-4:14
                            item @4:10-4:14
                              paragraph @4:13-4:14
                                text "d" @4:13-4:14
                      paragraph @6:9-6:10
                        text "e" @6:9-6:10

            """)
    }

    @Test
    func footnoteDefinitionsIndentedByFourSpaces() {
        let source = "[^a][^b][^c]\n\n[^a]: a\n    [^b]: b\n        [^c]: c\n            more\n    b2\n"
        #expect(TreeDump.dump(source, options: Self.options, sourceRanges: true) == """
            document @1:1-8:1
              paragraph @1:1-1:13
                footnote_reference "1" @1:1-1:5
                footnote_reference "2" @1:5-1:9
                footnote_reference "3" @1:9-1:13
              footnote_definition "a" @3:1-7:7
                paragraph @3:7-3:8
                  text "a" @3:7-3:8
              footnote_definition "b" @4:5-7:7
                paragraph @4:11-4:12
                  text "b" @4:11-4:12
              footnote_definition "c" @5:9-7:7
                paragraph @5:15-7:7
                  text "c" @5:15-5:16
                  softbreak @-
                  text "more" @6:13-6:17
                  softbreak @-
                  text "b2" @7:5-7:7

            """)
    }
}
