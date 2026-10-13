/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Long code fences (CommonMark §4.5).
///
/// A code fence has no upper bound on its length, and the closing fence must be at least as long as the opening one.
@Suite("Code fence length")
struct FenceLengthTests {

    struct Case: Sendable, CustomTestStringConvertible {
        let opening: Int
        let closing: Int
        let closes: Bool

        var testDescription: String {
            "\(opening) opening, \(closing) closing"
        }
    }

    static let cases: [Case] = [
        Case(opening: 255, closing: 255, closes: true),
        Case(opening: 255, closing: 254, closes: false),
        Case(opening: 256, closing: 256, closes: true),
        Case(opening: 256, closing: 255, closes: false),
        Case(opening: 300, closing: 300, closes: true),
        Case(opening: 300, closing: 299, closes: false),
        Case(opening: 300, closing: 256, closes: false),
        Case(opening: 1000, closing: 1000, closes: true),
        Case(opening: 1000, closing: 1001, closes: true),
        Case(opening: 1000, closing: 999, closes: false),
    ]

    /// A closed fence leaves `y` as a paragraph after the code block; an unclosed one holds every later line.
    @Test("a fence's length is its own, and only a fence at least as long closes it", arguments: cases, ["`", "~"])
    func fence(_ testCase: Case, _ character: String) {
        let opening = String(repeating: character, count: testCase.opening)
        let closing = String(repeating: character, count: testCase.closing)
        let source = opening + "\nx\n" + closing + "\ny\n"
        let fence = character == "`" ? "'`'" : "'~'"
        let kind = MarkdownDocument.withParsedDocument(source) { document -> String? in
            guard let first = document.root.firstChild else { return nil }
            return TreeDump.describe(first.kind)
        }
        #expect(kind == "code_block fenced fence=\(fence) length=\(testCase.opening) offset=0")
        let expected = testCase.closes ? """
            document
              code_block "" "x\\n"
              paragraph
                text "y"

            """ : """
            document
              code_block "" "x\\n\(closing)\\ny\\n"

            """
        #expect(TreeDump.dump(source, options: []) == expected)
    }
}
