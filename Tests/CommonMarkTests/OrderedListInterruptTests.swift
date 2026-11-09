/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An ordered list can interrupt a paragraph only when its start number is 1 (List items); otherwise the
/// marker is paragraph continuation text. The rule applies at every nesting level.
@Suite("Ordered list paragraph interruption")
struct OrderedListInterruptTests {

    @Test("nested ordered start != 1 stays paragraph text; ordered-1 and bullets interrupt", arguments: [
        ("- a\n  2. b", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "2. b"

            """),
        ("- a\n  1. b", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                  list ordered start=1 delim=period tight
                    item
                      paragraph
                        text "b"

            """),
        ("- a\n  - b", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                  list bullet '-' tight
                    item
                      paragraph
                        text "b"

            """),
    ])
    func nestedInterruptRequiresOrderedStartOne(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: []) == tree)
    }

    /// `2. b` is not indented into the first item, so it starts a sibling item rather than
    /// interrupting the item's paragraph.
    @Test("a sibling ordered marker (start != 1) at the list level opens a new item")
    func siblingOrderedMarkerOpensNewItem() {
        #expect(TreeDump.dump("1. a\n2. b", options: []) == """
            document
              list ordered start=1 delim=period tight
                item
                  paragraph
                    text "a"
                item
                  paragraph
                    text "b"

            """)
    }

    @Test("nested ordered start 10 (multi-digit, != 1) stays paragraph text")
    func multiDigitStartDoesNotInterrupt() {
        #expect(TreeDump.dump("- a\n  10. b", options: []) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "10. b"

            """)
    }

    @Test("nested ordered start != 1 with a paren delimiter stays paragraph text")
    func parenDelimiterStartTwoDoesNotInterrupt() {
        #expect(TreeDump.dump("- a\n  2) b", options: []) == """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "a"
                    softbreak
                    text "2) b"

            """)
    }

    @Test("ordered-1 interrupts a paragraph at a deeper nesting level")
    func orderedOneInterruptsAtDeeperLevel() {
        #expect(TreeDump.dump("- - a\n    1. b", options: []) == """
            document
              list bullet '-' tight
                item
                  list bullet '-' tight
                    item
                      paragraph
                        text "a"
                      list ordered start=1 delim=period tight
                        item
                          paragraph
                            text "b"

            """)
    }

    @Test("ordered start != 1 as the first block forms a list")
    func orderedStartTwoAsFirstBlockFormsList() {
        #expect(TreeDump.dump("2. a", options: []) == """
            document
              list ordered start=2 delim=period tight
                item
                  paragraph
                    text "a"

            """)
    }
}
