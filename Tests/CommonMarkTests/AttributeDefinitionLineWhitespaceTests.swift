/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An attribute definition's `:` may be followed by whitespace and at most one line ending before its
/// attributes, read as for a link reference definition (spec "Link reference definitions"), where line
/// tabulation and form feed are whitespace.
@Suite("Attribute definition whitespace after the colon")
struct AttributeDefinitionLineWhitespaceTests {

    @Test("a line tabulation before the attributes is skipped")
    func lineTabulation() {
        #expect(CmarkTreeDump.dump("^[x][a]\n\n^[a]:\u{0B}b\n", options: .attributes) == """
            document
              paragraph
                attribute "b"
                  text "x"

            """)
    }

    @Test("form feeds around the line ending before the attributes are skipped")
    func formFeedsAroundLineEnding() {
        #expect(CmarkTreeDump.dump("^[x][a]\n\n^[a]:\u{0C}\n\u{0C}b\n", options: .attributes) == """
            document
              paragraph
                attribute "b"
                  text "x"

            """)
    }

    @Test("without attributes, the definition is text")
    func withoutAttributes() {
        #expect(CmarkTreeDump.dump("^[x][a]\n\n^[a]:\u{0B}b\n", options: []) == """
            document
              paragraph
                text "^[x][a]"
              paragraph
                text "^[a]:\\u{B}b"

            """)
    }
}
