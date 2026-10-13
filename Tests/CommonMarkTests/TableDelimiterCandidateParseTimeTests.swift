/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parse time for a long paragraph with `.tables` whose every continuation line looks like a delimiter row but isn't
/// one, when the paragraph's lines aren't contiguous in the source.
///
/// Each such line asks whether the paragraph's last line and itself open a table. A paragraph in a block quote, or one
/// with CRLF line endings, holds its lines as separate pieces, and finding the last line must not walk all of them for
/// every candidate.
@Suite("Delimiter-shaped paragraph lines parse in linear time")
struct TableDelimiterCandidateParseTimeTests {

    struct Shape: Sendable, CustomTestStringConvertible {
        let prefix: String
        let line: String
        let testDescription: String

        func source(count: Int) -> String {
            prefix + String(repeating: line, count: count)
        }
    }

    static let shapes: [Shape] = [
        Shape(prefix: "> a\n", line: "> -:-\n", testDescription: "block quote"),
    ]

    @Test("the lines stay one paragraph")
    func paragraph() {
        #expect(TreeDump.dump(Self.shapes[0].source(count: 2), options: .tables) == """
            document
              block_quote
                paragraph
                  text "a"
                  softbreak
                  text "-:-"
                  softbreak
                  text "-:-"

            """)
    }
}
