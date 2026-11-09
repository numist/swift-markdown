/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Footnote Definition Tests")
struct FootnoteDefinitionTests {

    @Test("footnote definition whose lines end in CRLF registers and resolves")
    func crlfFootnoteDefinitionResolves() {
        #expect(TreeDump.dump("[^a]: first line\r\nsecond line\n\nsee [^a]\n", options: .footnotes) == """
            document
              paragraph
                text "see "
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "first line"
                  softbreak
                  text "second line"

            """)
    }
}
