/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A lazy continuation line of a nested block quote whose outer `>` and its optional following space consume only part
/// of a tab (Tabs; Block quotes). The tab's remaining columns are leading whitespace of the paragraph line, which the
/// paragraph's raw content drops (Paragraphs), so neither the line's text nor a code span crossing onto it holds any of
/// it.
@Suite("Partially consumed tab on a lazy continuation line")
struct NestedBlockQuoteLazyLineSplitTabTests {

    // MARK: - Partially consumed tab

    @Test("every partially consumed tab shape strips to the line ending's space")
    func partiallyConsumedTabIsStripped() {
        // Line 2 of each shape is a lazy continuation line whose outer block quote marker consumes part of a tab:
        // after `> >`, after a tight `>>`, after longer content, before a second tab, and at depth 3.
        #expect(TreeDump.dump("> > `x\n>\ty`", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    code "x y"

            """)
        #expect(TreeDump.dump(">> `x\n>\ty`", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    code "x y"

            """)
        #expect(TreeDump.dump("> > `xx\n>\ty`", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    code "xx y"

            """)
        #expect(TreeDump.dump("> > `x\n>\t\ty`", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    code "x y"

            """)
        #expect(TreeDump.dump("> > > `x\n>>\ty`", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  block_quote
                    paragraph
                      code "x y"

            """)
    }

    // MARK: - No partially consumed tab

    @Test("no tab yields just the line ending's space")
    func noTab() {
        #expect(TreeDump.dump("> > `x\n>y`", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    code "x y"

            """)
    }

    @Test("a tab after `> ` is stripped")
    func tabAfterMarkerSpace() {
        #expect(TreeDump.dump("> > `x\n> \ty`", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    code "x y"

            """)
    }

    // MARK: - Text

    @Test("text after a soft line break drops the tab's remaining columns")
    func textAfterSoftBreak() {
        #expect(TreeDump.dump("> > x\n>\ty", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    text "x"
                    softbreak
                    text "y"

            """)
    }

    @Test("text after a backslash hard line break drops the tab's remaining columns")
    func textAfterBackslashHardBreak() {
        #expect(TreeDump.dump("> > x\\\n>\ty", options: [.sourcePosition]) == """
            document
              block_quote
                block_quote
                  paragraph
                    text "x"
                    linebreak
                    text "y"

            """)
    }
}
