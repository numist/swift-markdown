/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Start condition 1 (HTML blocks) takes `script`, `pre` and `style`, followed by whitespace, `>` or the end of the
/// line, so a self-closing `<script/>` doesn't meet it. Start condition 7 excludes those tag names from its open tags,
/// so `<script/>` starts no HTML block. `textarea` is not a start condition 1 tag name, so `<textarea>` and
/// `<textarea/>` meet start condition 7.
@Suite("Self-closing type-1 tag names as HTML block starts")
struct HTMLBlockType1TagFallthroughTests {

    @Test("`<script/>` is a paragraph")
    func scriptSelfClosing() {
        #expect(TreeDump.dump("<script/>", options: []) == """
            document
              paragraph
                html_inline "<script/>"

            """)
    }

    @Test("`<pre/>`, `<style/>` are paragraphs", arguments: [
        ("<pre/>", """
            document
              paragraph
                html_inline "<pre/>"

            """),
        ("<style/>", """
            document
              paragraph
                html_inline "<style/>"

            """),
    ])
    func otherType1TagsSelfClosing(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: []) == tree)
    }

    // MARK: Start condition 1

    @Test("bare `<script>`/`<pre>`/`<style>` open HTML blocks (type 1)", arguments: [
        ("<script>", """
            document
              html_block "<script>\\n"

            """),
        ("<pre>", """
            document
              html_block "<pre>\\n"

            """),
        ("<style>", """
            document
              html_block "<style>\\n"

            """),
    ])
    func bareType1Tags(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: []) == tree)
    }

    @Test("`<script ` (trailing space) opens an HTML block (type 1)")
    func scriptTrailingSpace() {
        #expect(TreeDump.dump("<script ", options: []) == """
            document
              html_block "<script \\n"

            """)
    }

    // MARK: Start condition 7

    @Test("`<scripting>` opens an HTML block (type 7, tag name is not `script`)")
    func scriptingNearMiss() {
        #expect(TreeDump.dump("<scripting>", options: []) == """
            document
              html_block "<scripting>\\n"

            """)
    }

    @Test("`<textarea>` and `<textarea/>` open HTML blocks (type 7)", arguments: [
        ("<textarea>", """
            document
              html_block "<textarea>\\n"

            """),
        ("<textarea/>", """
            document
              html_block "<textarea/>\\n"

            """),
    ])
    func textareaOpensType7Block(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: []) == tree)
    }

    @Test("a `<textarea>` HTML block ends at a blank line (type 7)")
    func textareaBlockEndsAtBlankLine() {
        #expect(TreeDump.dump("<textarea>\n\nx</textarea>", options: []) == """
            document
              html_block "<textarea>\\n"
              paragraph
                text "x"
                html_inline "</textarea>"

            """)
    }

    @Test("a `</textarea>` doesn't end a type 1 HTML block")
    func textareaClosingTagDoesNotEndType1Block() {
        #expect(TreeDump.dump("<pre>\n</textarea>\nx", options: []) == """
            document
              html_block "<pre>\\n</textarea>\\nx\\n"

            """)
    }

    // MARK: Interrupting a paragraph

    @Test("`<textarea>` doesn't interrupt a paragraph")
    func textareaDoesNotInterruptParagraph() {
        #expect(TreeDump.dump("foo\n<textarea>", options: []) == """
            document
              paragraph
                text "foo"
                softbreak
                html_inline "<textarea>"

            """)
    }

    @Test("`<script/>` doesn't interrupt a paragraph")
    func selfClosingDoesNotInterruptParagraph() {
        #expect(TreeDump.dump("foo\n<script/>", options: []) == """
            document
              paragraph
                text "foo"
                softbreak
                html_inline "<script/>"

            """)
    }

    @Test("bare `<script>` interrupts a paragraph (type 1)")
    func bareTagInterruptsParagraph() {
        #expect(TreeDump.dump("foo\n<script>", options: []) == """
            document
              paragraph
                text "foo"
              html_block "<script>\\n"

            """)
    }
}
