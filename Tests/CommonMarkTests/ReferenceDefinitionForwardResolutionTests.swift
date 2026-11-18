/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Forward / nested link reference definition resolution")
struct ReferenceDefinitionForwardResolutionTests {

    @Test("multi-line reference resolves against a definition nested in a later list item")
    func multiLineReferenceResolvesAgainstNestedForwardDefinition() {
        #expect(TreeDump.dump(" ][ar\n]\n- [ar]:[", options: [.sourcePosition]) == """
            document
              paragraph
                text "]"
                link "[" ""
                  text "ar"
                  softbreak
              list bullet '-' tight
                item

            """)
    }

    @Test("single-line reference resolves against a definition nested in a later list item")
    func singleLineReferenceResolvesAgainstNestedForwardDefinition() {
        #expect(TreeDump.dump(" ][ar]\n- [ar]:[", options: [.sourcePosition]) == """
            document
              paragraph
                text "]"
                link "[" ""
                  text "ar"
              list bullet '-' tight
                item

            """)
    }

    @Test("reference resolves against a later top-level definition")
    func referenceResolvesAgainstLaterTopLevelDefinition() {
        #expect(TreeDump.dump("[a]\n\n[a]: /u", options: [.sourcePosition]) == """
            document
              paragraph
                link "/u" ""
                  text "a"

            """)
    }

    @Test("reference resolves against a later definition inside a list item")
    func referenceResolvesAgainstLaterNestedDefinition() {
        #expect(TreeDump.dump("[a]\n\n- [a]: /u", options: [.sourcePosition]) == """
            document
              paragraph
                link "/u" ""
                  text "a"
              list bullet '-' tight
                item

            """)
    }
}
