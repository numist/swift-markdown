/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Inline link destination at the end of preserved-whitespace content")
struct PreserveWhitespaceLinkDestinationEndTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .preserveWhitespace]

    @Test
    func destinationFollowedBySpacesAtEndOfInlineContent() {
        #expect(CmarkTreeDump.dump("[](a ", options: Self.options) == """
            document
              paragraph
                text "[](a "

            """)
    }
}
