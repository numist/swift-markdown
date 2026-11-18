/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// Whitespace after the `:` is read as in a link reference definition (Link reference definitions), and line
// tabulation and form feed are whitespace characters (Characters and lines).
@Suite("Attribute definition whitespace after the colon")
struct AttributeDefinitionLineWhitespaceTests {

    @Test("a line tabulation before the attributes is skipped")
    func lineTabulation() {
        #expect(TreeDump.dump("^[x][a]\n\n^[a]:\u{0B}b\n", options: .attributes) == """
            document
              paragraph
                attribute "b"
                  text "x"

            """)
    }

    @Test("form feeds around the line ending before the attributes are skipped")
    func formFeedsAroundLineEnding() {
        #expect(TreeDump.dump("^[x][a]\n\n^[a]:\u{0C}\n\u{0C}b\n", options: .attributes) == """
            document
              paragraph
                attribute "b"
                  text "x"

            """)
    }

    @Test("without `.attributes`, the definition is text")
    func withoutAttributes() {
        #expect(TreeDump.dump("^[x][a]\n\n^[a]:\u{0B}b\n", options: []) == """
            document
              paragraph
                text "^[x][a]"
              paragraph
                text "^[a]:\\u{B}b"

            """)
    }
}
