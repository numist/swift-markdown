/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Parse time for many footnote-shaped brackets whose `]` lands on a later line than their `[`, with `.footnotes`.
///
/// A footnote label can't hold a line ending, so none of these brackets is a footnote reference; telling so must cost
/// each bracket a bounded amount of work, not a scan of the paragraph before it.
@Suite("Cross-line footnote brackets parse in linear time")
struct CrossLineFootnoteParseTimeTests {

    struct Shape: Sendable, CustomTestStringConvertible {
        let make: @Sendable (Int) -> String
        let testDescription: String
    }

    static let shapes: [Shape] = [
        Shape(make: { String(repeating: "[^a\nb] ", count: $0) }, testDescription: "a bracket per line"),
        Shape(make: { String(repeating: "[^\n", count: $0) + "a" + String(repeating: "]", count: $0) }, testDescription: "brackets nested across lines"),
        Shape(make: { String(repeating: "[^", count: $0) + "\n" + String(repeating: "]", count: $0) }, testDescription: "brackets nested across one line ending"),
        Shape(make: { String(repeating: "> [^\n", count: $0) + "> a" + String(repeating: "]", count: $0) }, testDescription: "brackets nested across block quote lines"),
        Shape(make: { String(repeating: "[\\^", count: $0) + "x" + String(repeating: "]", count: $0) }, testDescription: "escaped-caret brackets nested on one line"),
    ]

    static let options: [MarkdownDocument.ParseOptions] = [.footnotes, [.footnotes, .inlineOnly]]

    @Test("many cross-line brackets parse in linear time", arguments: shapes, options)
    func manyBrackets(_ shape: Shape, _ options: MarkdownDocument.ParseOptions) {
        expectLinearParseTime(count: 1000, options: options, shape.make)
    }
}
