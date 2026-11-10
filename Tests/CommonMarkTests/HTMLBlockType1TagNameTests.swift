/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The type 1 start condition (HTML blocks) takes `script`, `pre` and `style`, followed by whitespace, `>` or the end
/// of the line, so a self-closing `<script/>` doesn't meet it. The type 7 start condition excludes those tag names
/// from its open tags, so `<script/>` starts no HTML block. The exclusion applies to open tags only, so a closing
/// `</script>` meets the type 7 start condition. `textarea` is not a type 1 tag name, so `<textarea>` and
/// `<textarea/>` meet the type 7 start condition.
@Suite("Self-closing type 1 tag names as HTML block starts")
struct HTMLBlockType1TagNameTests {

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

    // MARK: Type 1

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

    // MARK: Type 7

    @Test("`<scripting>` opens an HTML block (type 7, tag name is not `script`)")
    func scriptingNearMiss() {
        #expect(TreeDump.dump("<scripting>", options: []) == """
            document
              html_block "<scripting>\\n"

            """)
    }

    @Test("self-closing `<script/>`, `<PRE/>` and `<Style/>` are paragraphs (type 7 excludes them)", arguments: [
        ("<script/>", """
            document @1:1-1:10
              paragraph @1:1-1:10
                html_inline "<script/>" @1:1-1:10

            """),
        ("<PRE/>", """
            document @1:1-1:7
              paragraph @1:1-1:7
                html_inline "<PRE/>" @1:1-1:7

            """),
        ("<Style/>", """
            document @1:1-1:9
              paragraph @1:1-1:9
                html_inline "<Style/>" @1:1-1:9

            """),
    ])
    func type1TagNamesExcludedFromType7(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: .sourcePosition, sourceRanges: true) == tree)
    }

    @Test("`</script>` and `<scripting/>` open HTML blocks (type 7)", arguments: [
        ("</script>", """
            document @1:1-1:10
              html_block "</script>\\n" @1:1-1:10

            """),
        ("<scripting/>", """
            document @1:1-1:13
              html_block "<scripting/>\\n" @1:1-1:13

            """),
    ])
    func closingScriptAndScriptingMeetType7StartCondition(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: .sourcePosition, sourceRanges: true) == tree)
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
    func textareaMeetsType7StartCondition(_ source: String, _ tree: String) {
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
