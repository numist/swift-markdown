/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A CDATA section (Raw HTML) runs to the first `]]>`, so content ending in `]` before the closer, as in
/// `<![CDATA[x]]]>`, is part of the section.
@Suite("Inline CDATA section ending in a bracket")
struct InlineCDATATrailingBracketTests {

    @Test("`<![CDATA[]]]>` (empty content + trailing `]`) is inline HTML")
    func emptyTrailingBracketRecognized() {
        #expect(TreeDump.dump("o<![CDATA[]]]>", options: []) == """
            document
              paragraph
                text "o"
                html_inline "<![CDATA[]]]>"

            """)
    }

    @Test("`<![CDATA[x]]]>` (content ending in `]`) is inline HTML")
    func contentTrailingBracketRecognized() {
        #expect(TreeDump.dump("o<![CDATA[x]]]>", options: []) == """
            document
              paragraph
                text "o"
                html_inline "<![CDATA[x]]]>"

            """)
    }

    @Test("`<![CDATA[xx]]>` (normal) is inline HTML")
    func normalCDATARecognized() {
        #expect(TreeDump.dump("o<![CDATA[xx]]>", options: []) == """
            document
              paragraph
                text "o"
                html_inline "<![CDATA[xx]]>"

            """)
    }

    @Test("`<![CDATA[]]>` (empty content) is inline HTML")
    func emptyCDATARecognized() {
        #expect(TreeDump.dump("o<![CDATA[]]>", options: []) == """
            document
              paragraph
                text "o"
                html_inline "<![CDATA[]]>"

            """)
    }
}
