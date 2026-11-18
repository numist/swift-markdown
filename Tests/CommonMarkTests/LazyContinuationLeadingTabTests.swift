/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

// A paragraph's raw content has each line's initial whitespace removed (Paragraphs), so a code span or raw HTML that
// crosses a line ending holds no tab from the next line.
@Suite("Leading tab of a lazy continuation line in literal inlines")
struct LazyContinuationLeadingTabTests {

    private static let options: MarkdownDocument.ParseOptions = [.sourcePosition]

    @Test("a code span across a lazy continuation line drops the leading tab")
    func codeSpanAcrossLazyLineDropsTab() {
        #expect(TreeDump.dump(">`\n\t`", options: Self.options, sourceRanges: true) == """
            document @1:1-2:3
              block_quote @1:1-2:3
                paragraph @1:2-2:3
                  code " " @1:2-2:3

            """)
    }

    @Test("a raw HTML tag across a lazy continuation line drops the leading tab")
    func htmlTagAcrossLazyLineDropsTab() {
        #expect(TreeDump.dump("><i\n\t>", options: Self.options, sourceRanges: true) == """
            document @1:1-2:3
              block_quote @1:1-2:3
                paragraph @1:2-2:3
                  html_inline "<i\\n>" @1:2-2:3

            """)
    }

    @Test("a raw HTML comment across a lazy continuation line drops the leading tab")
    func htmlCommentAcrossLazyLineDropsTab() {
        #expect(TreeDump.dump(">0<!--\n\t-->", options: Self.options, sourceRanges: true) == """
            document @1:1-2:5
              block_quote @1:1-2:5
                paragraph @1:2-2:5
                  text "0" @1:2-1:3
                  html_inline "<!--\\n-->" @1:3-2:5

            """)
    }

    @Test("a top-level code span across a line ending drops the leading tab")
    func codeSpanTopLevelDropsTab() {
        #expect(TreeDump.dump("`\n\t`", options: Self.options, sourceRanges: true) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                code " " @1:1-2:3

            """)
    }

    @Test("a top-level raw HTML tag across a line ending drops the leading tab")
    func htmlTagTopLevelDropsTab() {
        #expect(TreeDump.dump("<i\n\t>", options: Self.options, sourceRanges: true) == """
            document @1:1-2:3
              paragraph @1:1-2:3
                html_inline "<i\\n>" @1:1-2:3

            """)
    }

    @Test("a top-level raw HTML comment across a line ending drops the leading tab")
    func htmlCommentTopLevelDropsTab() {
        #expect(TreeDump.dump("0<!--\n\t-->", options: Self.options, sourceRanges: true) == """
            document @1:1-2:5
              paragraph @1:1-2:5
                text "0" @1:1-1:2
                html_inline "<!--\\n-->" @1:2-2:5

            """)
    }

    @Test("text on a lazy continuation line drops the leading tab")
    func plainTextLazyBlockquoteTabDropped() {
        #expect(TreeDump.dump(">a\n\tb", options: Self.options, sourceRanges: true) == """
            document @1:1-2:3
              block_quote @1:1-2:3
                paragraph @1:2-2:3
                  text "a" @1:2-1:3
                  softbreak @-
                  text "b" @2:2-2:3

            """)
    }
}
