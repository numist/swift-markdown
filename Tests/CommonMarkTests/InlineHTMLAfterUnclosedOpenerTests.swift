/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Each raw HTML construct (Raw HTML) is recognized independently, so an unclosed opener of one kind doesn't keep a
/// later construct from matching. Every input starts with `x` so the construct is inline rather than an HTML block.
@Suite("Inline raw HTML after an unclosed opener")
struct InlineHTMLAfterUnclosedOpenerTests {

    @Test("`x<![CDATA[a <![CDATA[b` is literal")
    func unclosedCDATAThenCDATAOpenerIsLiteral() {
        #expect(TreeDump.dump("x<![CDATA[a <![CDATA[b", options: []) == """
            document
              paragraph
                text "x<![CDATA[a <![CDATA[b"

            """)
    }

    @Test("`x<!A x <!B y` is literal")
    func unclosedDeclarationThenDeclarationOpenerIsLiteral() {
        #expect(TreeDump.dump("x<!A x <!B y", options: []) == """
            document
              paragraph
                text "x<!A x <!B y"

            """)
    }

    @Test("`x<?<??>` is one processing instruction")
    func processingInstructionContainingOpener() {
        #expect(TreeDump.dump("x<?<??>", options: []) == """
            document
              paragraph
                text "x"
                html_inline "<?<??>"

            """)
    }

    @Test("`x<!--<!--->` is one comment")
    func commentContainingOpener() {
        #expect(TreeDump.dump("x<!--<!--->", options: []) == """
            document
              paragraph
                text "x"
                html_inline "<!--<!--->"

            """)
    }

    @Test("`x<!--<![CDATA[y]]>`: the CDATA section after an unclosed comment is recognized")
    func cdataAfterUnclosedComment() {
        #expect(TreeDump.dump("x<!--<![CDATA[y]]>", options: []) == """
            document
              paragraph
                text "x<!--"
                html_inline "<![CDATA[y]]>"

            """)
    }

    @Test("`x<!--<!DOCTYPE html>`: the declaration after an unclosed comment is recognized")
    func declarationAfterUnclosedComment() {
        #expect(TreeDump.dump("x<!--<!DOCTYPE html>", options: []) == """
            document
              paragraph
                text "x<!--"
                html_inline "<!DOCTYPE html>"

            """)
    }

    @Test("a single processing instruction is recognized")
    func singleProcessingInstruction() {
        #expect(TreeDump.dump("x<?php?>", options: []) == """
            document
              paragraph
                text "x"
                html_inline "<?php?>"

            """)
    }

    @Test("two processing instructions are both recognized")
    func twoProcessingInstructions() {
        #expect(TreeDump.dump("x<?a?><?b?>", options: []) == """
            document
              paragraph
                text "x"
                html_inline "<?a?>"
                html_inline "<?b?>"

            """)
    }

    @Test("a single comment is recognized")
    func singleComment() {
        #expect(TreeDump.dump("x<!--y-->", options: []) == """
            document
              paragraph
                text "x"
                html_inline "<!--y-->"

            """)
    }

    @Test("a single CDATA section is recognized")
    func singleCDATA() {
        #expect(TreeDump.dump("x<![CDATA[y]]>", options: []) == """
            document
              paragraph
                text "x"
                html_inline "<![CDATA[y]]>"

            """)
    }

    @Test("a single declaration is recognized")
    func singleDeclaration() {
        #expect(TreeDump.dump("x<!DOCTYPE html>", options: []) == """
            document
              paragraph
                text "x"
                html_inline "<!DOCTYPE html>"

            """)
    }
}
