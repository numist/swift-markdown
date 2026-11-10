/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The start condition of an HTML block of type 5 (HTML blocks) is the string `<![CDATA[`, matched case-sensitively.
/// `<![cdata[` and `<![CDAtA[` meet no start condition, since type 4 needs an uppercase ASCII letter after `<!`, so
/// they are paragraphs.
@Suite("HTML block CDATA start condition case")
struct HTMLBlockCDATAStartCaseTests {

    @Test("`<![CDAtA[` (lowercase t) is a paragraph")
    func mixedCaseIsParagraph() {
        #expect(TreeDump.dump("<![CDAtA[", options: []) == """
            document
              paragraph
                text "<![CDAtA["

            """)
    }

    @Test("`<![cdata[` (all lowercase) is a paragraph")
    func lowercaseIsParagraph() {
        #expect(TreeDump.dump("<![cdata[", options: []) == """
            document
              paragraph
                text "<![cdata["

            """)
    }

    @Test("`<![CDATA[` opens an HTML block")
    func exactCaseOpensHTMLBlock() {
        #expect(TreeDump.dump("<![CDATA[", options: []) == """
            document
              html_block "<![CDATA[\\n"

            """)
    }

    @Test("`<![CDATAx` (no trailing bracket) is a paragraph")
    func noTrailingBracket() {
        #expect(TreeDump.dump("<![CDATAx", options: []) == """
            document
              paragraph
                text "<![CDATAx"

            """)
    }

    @Test("`<!x` (lowercase after `<!`) is a paragraph")
    func lowercaseAfterBang() {
        #expect(TreeDump.dump("<!x", options: []) == """
            document
              paragraph
                text "<!x"

            """)
    }

    @Test("`<!DOCTYPE html>` meets the type 4 start condition and opens an HTML block")
    func type4Declaration() {
        #expect(TreeDump.dump("<!DOCTYPE html>", options: []) == """
            document
              html_block "<!DOCTYPE html>\\n"

            """)
    }

    @Test("`<!Baz` meets the type 4 start condition, which needs only an uppercase letter after `<!`")
    func type4FirstLetterOnly() {
        #expect(TreeDump.dump("<!Baz", options: []) == """
            document
              html_block "<!Baz\\n"

            """)
    }
}
