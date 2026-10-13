/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parse time for deeply nested footnote openers with `.footnotes`.
///
/// A footnote label holds at most 999 characters and no line ending, so deciding whether a bracket is a footnote
/// reference must cost work bounded by that cap, not by the whole span the bracket encloses.
@Suite("Nested footnote openers parse in linear time")
struct FootnoteNestingParseTimeTests {

    @Test("deep nesting parses in linear time", arguments: [
        MarkdownDocument.ParseOptions.footnotes,
        [.footnotes, .attributes],
        [.footnotes, .inlineOnly],
    ])
    func deepNesting(_ options: MarkdownDocument.ParseOptions) {
        expectLinearParseTime(count: 4000, options: options) { depth in
            String(repeating: "[^", count: depth) + "x" + String(repeating: "]", count: depth)
        }
    }
}
