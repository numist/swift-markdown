/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Appends each link, image and attribute node in document order with its destination or attribute string, each soft
/// line break, and each run of adjacent text nodes as one literal.
private func outline(_ node: borrowing MarkdownNode, into out: inout [String]) {
    switch node.kind {
    case .link:
        out.append("link " + (node.url() ?? ""))
    case .image:
        out.append("image " + (node.url() ?? ""))
    case .attribute:
        out.append("attribute " + (node.attributes() ?? ""))
    case .softBreak:
        out.append("softbreak")
    case .text:
        let literal = node.literal() ?? ""
        if let last = out.last, last.hasPrefix("text ") {
            out[out.count - 1] = last + literal
        } else {
            out.append("text " + literal)
        }
    default:
        break
    }
    node.children.forEach { child in
        outline(child, into: &out)
    }
}

/// A bare link destination includes parentheses that are part of a balanced pair of unescaped parentheses (Links), and
/// an attribute form's `(…)` holds balanced parentheses.
@Suite("Nested parentheses in link destinations and attributes")
struct NestedParenthesesTests {

    private static let options: MarkdownDocument.ParseOptions = [.attributes]

    private static let open33 = "((((((((((((((((((((((((((((((((("

    private func nodes(_ src: String) -> [String] {
        MarkdownDocument.withParsedDocument(src, options: Self.options) { doc -> [String] in
            var out: [String] = []
            outline(doc.root, into: &out)
            return out
        }
    }

    // MARK: Several destinations in one paragraph

    @Test("`[](` five times, then `x [b](c)`: only `[b](c)` is a link")
    func failedDestinationsThenLink() {
        #expect(nodes("[]([]([]([]([](x [b](c)") == [
            "text []([]([]([]([](x ",
            "link c",
            "text b",
        ])
    }

    @Test("`[a](b([c](d)`: the first destination is unbalanced and the second is `d`")
    func balancedDestinationAfterUnbalancedOne() {
        #expect(nodes("[a](b([c](d)") == [
            "text [a](b(",
            "link d",
            "text c",
        ])
    }

    @Test("`[a](b[c](d )`: the first destination is unbalanced at the space and the second is `d`")
    func destinationEndingAtSpaceAfterUnbalancedOne() {
        #expect(nodes("[a](b[c](d )") == [
            "text [a](b",
            "link d",
            "text c",
        ])
    }

    @Test("`[a](b[c]((d )`: both destinations are unbalanced at the space")
    func nestedUnbalancedDestinations() {
        #expect(nodes("[a](b[c]((d )") == [
            "text [a](b[c]((d )",
        ])
    }

    @Test("40 unclosed `(` end at a space, and `[b](c)` after it is a link")
    func unbalancedRunEndedBySpace() {
        #expect(nodes("[a](" + Self.open33 + "((((((( [b](c)") == [
            "text [a]((((((((((((((((((((((((((((((((((((((((( ",
            "link c",
            "text b",
        ])
    }

    @Test("40 unclosed `(` end at a line ending, and `[b](c)` after it is a link")
    func unbalancedRunEndedByLineEnding() {
        #expect(nodes("[a](" + Self.open33 + "(((((((\n[b](c)") == [
            "text [a](((((((((((((((((((((((((((((((((((((((((",
            "softbreak",
            "link c",
            "text b",
        ])
    }

    @Test("`[a]([b](c))` has the destination `[b](c)`")
    func bracketsInsideDestination() {
        #expect(nodes("[a]([b](c))") == [
            "link [b](c)",
            "text a",
        ])
    }

    @Test("`[a](x[b](c)` leaves no `)` to close the first link, and `[b](c)` is a link")
    func linkInsideUnclosedDestination() {
        #expect(nodes("[a](x[b](c)") == [
            "text [a](x",
            "link c",
            "text b",
        ])
    }

    // MARK: Attributes and links in one paragraph

    @Test("`^[a]([b](c)) [d](e)` is an attribute holding `[b](c)` and a link to `e`")
    func attributeHoldingLinkThenLink() {
        #expect(nodes("^[a]([b](c)) [d](e)") == [
            "attribute [b](c)",
            "text a ",
            "link e",
            "text d",
        ])
    }

    @Test("`[x](^[a](b c)`: the destination ends at the space, and the attribute holds `b c`")
    func attributeInsideUnbalancedDestination() {
        #expect(nodes("[x](^[a](b c)") == [
            "text [x](",
            "attribute b c",
            "text a",
        ])
    }

    @Test("`^[a](x [b](c d)`: the attribute form is unclosed, and `c d` is no destination")
    func destinationInsideUnclosedAttribute() {
        #expect(nodes("^[a](x [b](c d)") == [
            "text ^[a](x [b](c d)",
        ])
    }
}
