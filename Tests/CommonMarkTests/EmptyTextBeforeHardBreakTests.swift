/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The two or more spaces before a hard line break belong to the break (Hard line breaks), so they
/// produce no text node and are not part of a preceding text node's source range.
@Suite("Trailing spaces before a hard line break")
struct EmptyTextBeforeHardBreakTests {

    private static let options: MarkdownDocument.ParseOptions =
        [.tables, .strikethrough, .tasklist, .tableSpans, .sourcePosition, .smart]

    @Test("literal ] before a hard line break keeps its 1-character range")
    func bracketLiteral() {
        #expect(TreeDump.dump("]  \n]", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "]" @1:1-1:2
                linebreak @-
                text "]" @2:1-2:2

            """)
    }

    @Test("emphasis + trailing spaces + hard line break: no empty text node")
    func emphasis() {
        #expect(TreeDump.dump("*x*  \ny", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                emph @1:1-1:4
                  text "x" @1:2-1:3
                linebreak @-
                text "y" @2:1-2:2

            """)
    }

    @Test("inline code + trailing spaces + hard line break: no empty text node")
    func inlineCode() {
        #expect(TreeDump.dump("`c`  \ny", options: Self.options, sourceRanges: true) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                code "c" @1:1-1:4
                linebreak @-
                text "y" @2:1-2:2

            """)
        let kinds = MarkdownDocument.withParsedDocument("`c`  \ny", options: Self.options) {
            dfs($0).map { TreeDump.describe($0.kind) }
        }
        #expect(kinds == ["document", "paragraph", "code backticks=1", "linebreak", "text"])
    }

    @Test("link + trailing spaces + hard line break: no empty text node")
    func link() {
        #expect(TreeDump.dump("[foo]  \n[]\n\n[foo]: /url \"title\"", options: Self.options, sourceRanges: true) == """
            document @1:1-4:20
              paragraph @1:1-2:3
                link "/url" "title" @1:1-1:6
                  text "foo" @1:2-1:5
                linebreak @-
                text "[]" @2:1-2:3

            """)
    }
}
