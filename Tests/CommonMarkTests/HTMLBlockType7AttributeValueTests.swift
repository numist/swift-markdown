/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// An unquoted attribute value is nonempty, while a quoted one may be empty (Raw HTML), so only a tag whose values
/// meet those rules is the complete open tag that start condition 7 needs (HTML blocks).
@Suite("Attribute values in a type 7 HTML block start tag")
struct HTMLBlockType7AttributeValueTests {

    @Test("an empty unquoted attribute value starts no HTML block", arguments: [
        ("<a b=>", """
            document
              paragraph
                text "<a b=>"

            """),
        ("<a b= >", """
            document
              paragraph
                text "<a b= >"

            """),
    ])
    func emptyUnquotedValueIsParagraph(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: []) == tree)
    }

    @Test("a nonempty unquoted or an empty quoted attribute value starts an HTML block", arguments: [
        ("<a b=c>", """
            document
              html_block "<a b=c>\\n"

            """),
        ("<a b=\"\">", """
            document
              html_block "<a b=\\"\\">\\n"

            """),
    ])
    func validValueStartsHTMLBlock(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: []) == tree)
    }
}
