/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

private func collectText(_ node: borrowing MarkdownNode, into out: inout String, count: inout Int) {
    if case .text = node.kind, case .text(let literal) = node.stringContent {
        out += literal
        count += 1
    }
    node.children.forEach { child in
        collectText(child, into: &out, count: &count)
    }
}

/// A decimal numeric character reference has 1–7 digits and a hexadecimal one 1–6 digits (Entity and
/// numeric character references); a longer reference is literal text. A reference within the limit
/// whose code point is invalid decodes to U+FFFD.
@Suite("Numeric character reference digit limit")
struct NumericCharacterReferenceDigitLimitTests {

    private static let options: MarkdownDocument.ParseOptions = []

    private static let replacement = "\u{FFFD}"
    private static let maxScalar = "\u{10FFFF}"

    private func text(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> String {
        let (out, count): (String, Int) = MarkdownDocument.withParsedDocument(src, options: options) { doc -> (String, Int) in
            var out = ""
            var count = 0
            collectText(doc.root, into: &out, count: &count)
            return (out, count)
        }
        try #require(count >= 1, "no text node parsed")
        return out
    }

    @Test("`&#98665435;` (8 decimal digits) stays literal")
    func decimalEightDigits() throws {
        #expect(try text("&#98665435;", options: Self.options) == "&#98665435;")
    }

    @Test("`&#12345678;` (8 ascending decimal digits) stays literal")
    func decimalEightAscendingDigits() throws {
        #expect(try text("&#12345678;", options: Self.options) == "&#12345678;")
    }

    @Test("`&#x1234567;` (7 hex digits) stays literal")
    func hexSevenDigits() throws {
        #expect(try text("&#x1234567;", options: Self.options) == "&#x1234567;")
    }

    @Test("`&#x12345678;` (8 hex digits) stays literal")
    func hexEightDigits() throws {
        #expect(try text("&#x12345678;", options: Self.options) == "&#x12345678;")
    }

    @Test("1–7 decimal and 1–6 hex digit references decode; 9-digit references stay literal")
    func digitLimitBoundaries() throws {
        // In-range values decode to their scalar.
        #expect(try text("&#65;", options: Self.options) == "A")
        #expect(try text("&#x41;", options: Self.options) == "A")
        // The maximum scalar at the 7-decimal and 6-hex digit limits.
        #expect(try text("&#1114111;", options: Self.options) == Self.maxScalar)
        #expect(try text("&#x10FFFF;", options: Self.options) == Self.maxScalar)
        // Invalid code points within the digit limits decode to U+FFFD.
        #expect(try text("&#0;", options: Self.options) == Self.replacement)
        #expect(try text("&#1234567;", options: Self.options) == Self.replacement)
        #expect(try text("&#xFFFFFF;", options: Self.options) == Self.replacement)
        // Surrogate code points (U+D800…U+DFFF) also map to U+FFFD, decimal and hex alike.
        #expect(try text("&#55296;", options: Self.options) == Self.replacement)
        #expect(try text("&#xDFFF;", options: Self.options) == Self.replacement)
        // Nine-digit references stay literal, including a hexadecimal one whose value exceeds 32 bits.
        #expect(try text("&#123456789;", options: Self.options) == "&#123456789;")
        #expect(try text("&#x123456789;", options: Self.options) == "&#x123456789;")
    }
}
