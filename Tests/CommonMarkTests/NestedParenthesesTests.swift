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
/// line break, and each run of text, in document order with no link, image, attribute or soft line break between, as
/// one literal.
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
/// an attribute form's `(…)` holds balanced parentheses, nested to any depth.
@Suite("Nested parentheses in link destinations and attributes")
struct NestedParenthesesTests {

    private static let options: MarkdownDocument.ParseOptions = [.attributes]

    private func nodes(_ src: String) -> [String] {
        MarkdownDocument.withParsedDocument(src, options: Self.options) { doc -> [String] in
            var out: [String] = []
            outline(doc.root, into: &out)
            return out
        }
    }

    // MARK: Depth

    @Test("an inline link's destination holds nested pairs")
    func inlineLink() {
        #expect(nodes("[a]((((x))))") == ["link (((x)))", "text a"])
    }

    @Test("an image's destination holds nested pairs")
    func image() {
        #expect(nodes("![a]((((x))))") == ["image (((x)))", "text a"])
    }

    @Test("a link reference definition's destination holds nested pairs")
    func referenceDefinition() {
        #expect(nodes("[a]: (((x)))\n\n[a]") == ["link (((x)))", "text a"])
    }

    @Test("a link reference definition's destination on the line after its label holds nested pairs")
    func referenceDefinitionDestinationOnNextLine() {
        #expect(nodes("[a]:\n(((x)))\n\n[a]") == ["link (((x)))", "text a"])
    }

    @Test("an inline link's destination on the line after its `(` holds nested pairs")
    func inlineLinkDestinationOnNextLine() {
        #expect(nodes("[a](\n(((x))))") == ["link (((x)))", "text a"])
    }

    @Test("an escaped `)` inside nested pairs is not part of a pair")
    func escapedCloser() {
        #expect(nodes("[a]((((x\\)))))") == ["link (((x))))", "text a"])
    }

    @Test("an escaped `(` before nested pairs is not part of a pair")
    func escapedOpener() {
        #expect(nodes("[a](\\((((x))))") == ["link ((((x)))", "text a"])
    }

    @Test("a destination whose pairs take every `)` leaves none to close the inline link")
    func unclosedInlineLink() {
        #expect(nodes("[a](((((x))))") == ["text [a](((((x))))"])
    }

    @Test("a link in a block quote has a destination of nested pairs")
    func inlineLinkInBlockQuote() {
        #expect(nodes("> [a]((((x))))") == ["link (((x)))", "text a"])
    }

    @Test("an image in a list item has a destination of nested pairs")
    func imageInListItem() {
        #expect(nodes("- ![a]((((x))))") == ["image (((x)))", "text a"])
    }

    @Test("an attribute form's `(…)` holds nested pairs")
    func attribute() {
        #expect(nodes("^[a]((((x))))") == ["attribute (((x)))", "text a"])
    }

    @Test("an attribute form's nested pairs span a line ending")
    func attributeAcrossLineEnding() {
        #expect(nodes("^[a]((((\nx))))") == ["attribute (((\nx)))", "text a"])
    }

    @Test("an escaped `)` inside an attribute form's nested pairs is not part of a pair")
    func attributeEscapedCloser() {
        #expect(nodes("^[a]((((x\\)))))") == ["attribute (((x\\))))", "text a"])
    }

    @Test("an attribute in a block quote holds nested pairs")
    func attributeInBlockQuote() {
        #expect(nodes("> ^[a]((((x))))") == ["attribute (((x)))", "text a"])
    }

    // MARK: Deep nesting

    // Matching each paragraph's parentheses costs time in proportion to its length, so these inputs of 250 KB to
    // 500 KB parse well within the time limit.

    private static let depth = 250_000
    private static let openers = String(repeating: "(", count: depth)
    private static let closers = String(repeating: ")", count: depth)

    @Test(.timeLimit(.minutes(1)))
    func deeplyNestedDestination() {
        #expect(nodes("[a](" + Self.openers + "x" + Self.closers + ")") == [
            "link \(Self.openers)x\(Self.closers)",
            "text a",
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func deeplyNestedAttribute() {
        #expect(nodes("^[a](" + Self.openers + "x" + Self.closers + ")") == [
            "attribute \(Self.openers)x\(Self.closers)",
            "text a",
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func deepUnclosedRunThenLink() {
        #expect(nodes("[a](" + Self.openers + " [b](c)") == [
            "text [a](\(Self.openers) ",
            "link c",
            "text b",
        ])
    }

    @Test(.timeLimit(.minutes(1)))
    func manyUnclosedDestinations() {
        let openers = String(repeating: "[](", count: 100_000)
        #expect(nodes(openers + "x") == ["text \(openers)x"])
    }

    @Test(.timeLimit(.minutes(1)))
    func manyUnclosedAttributes() {
        let openers = String(repeating: "^[](", count: 100_000)
        #expect(nodes(openers + "x") == ["text \(openers)x"])
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

    @Test("unclosed `(`s end at a space, and `[b](c)` after it is a link")
    func unbalancedRunEndedBySpace() {
        #expect(nodes("[a](((((((((((( [b](c)") == [
            "text [a](((((((((((( ",
            "link c",
            "text b",
        ])
    }

    @Test("unclosed `(`s end at a line ending, and `[b](c)` after it is a link")
    func unbalancedRunEndedByLineEnding() {
        #expect(nodes("[a](((((((((((\n[b](c)") == [
            "text [a](((((((((((",
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

    @Test("`^[a](^[b](c)`: the first attribute form is unclosed, and the second holds `c`")
    func attributeInsideUnclosedAttribute() {
        #expect(nodes("^[a](^[b](c)") == [
            "text ^[a](",
            "attribute c",
            "text b",
        ])
    }

    @Test("`^[a](x^[b]((c)`: both attribute forms are unclosed")
    func nestedUnclosedAttributes() {
        #expect(nodes("^[a](x^[b]((c)") == [
            "text ^[a](x^[b]((c)",
        ])
    }

    @Test("`^[a](x [b](c d)`: the attribute form is unclosed, and `c d` is no destination")
    func destinationInsideUnclosedAttribute() {
        #expect(nodes("^[a](x [b](c d)") == [
            "text ^[a](x [b](c d)",
        ])
    }
}
