/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Appends the literal of every text node in `node`'s subtree to `out`, depth-first.
private func concatText(_ node: borrowing MarkdownNode, into out: inout String) {
    if case .text = node.kind, case .text(let s) = node.stringContent {
        out += s
    }
    node.children.forEach { child in
        concatText(child, into: &out)
    }
}

/// The concatenated text of the first strikethrough in depth-first order, or nil if there is none.
private func firstStrikethroughText(_ node: borrowing MarkdownNode) -> String? {
    if case .strikethrough = node.kind {
        var out = ""
        concatText(node, into: &out)
        return out
    }
    var found: String? = nil
    node.children.forEach { child in
        if found == nil {
            found = firstStrikethroughText(child)
        }
    }
    return found
}

/// The number of strikethrough nodes in the tree.
private func strikethroughCount(_ node: borrowing MarkdownNode) -> Int {
    var n = 0
    if case .strikethrough = node.kind { n += 1 }
    node.children.forEach { child in
        n += strikethroughCount(child)
    }
    return n
}

/// With `.strikethrough`, a run of one or two tildes delimits strikethrough and closes only an opener of the same
/// length. A run of three or more tildes is literal text, whatever its length.
@Suite("Strikethrough delimiter run length")
struct StrikethroughDelimiterRunLengthTests {

    private static let options: MarkdownDocument.ParseOptions = [.strikethrough]

    /// The concatenated text of the first strikethrough, or nil if there is none.
    private func strikeText(_ src: String, options: MarkdownDocument.ParseOptions) -> String? {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> String? in
            firstStrikethroughText(doc.root)
        }
    }

    /// The number of strikethrough nodes.
    private func strikeCount(_ src: String, options: MarkdownDocument.ParseOptions) -> Int {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> Int in
            strikethroughCount(doc.root)
        }
    }

    // `**` puts punctuation before the opener so that it is left-flanking, and `)` gives a strikethrough
    // content of its own.
    private func input(openerLen: Int, tailCount: Int) -> String {
        "**" + String(repeating: "~", count: openerLen) + ")" + String(repeating: "~", count: tailCount)
    }

    @Test("a one-tilde opener before a 101-tilde run stays literal")
    func oneTildeOpenerBefore101TildeRun() {
        #expect(strikeText(input(openerLen: 1, tailCount: 101), options: Self.options) == nil)
    }

    @Test("a one-tilde opener before a 201-tilde run stays literal")
    func oneTildeOpenerBefore201TildeRun() {
        #expect(strikeText(input(openerLen: 1, tailCount: 201), options: Self.options) == nil)
    }

    @Test("a two-tilde opener before a 102-tilde run stays literal")
    func twoTildeOpenerBefore102TildeRun() {
        #expect(strikeText(input(openerLen: 2, tailCount: 102), options: Self.options) == nil)
    }

    @Test("a one-tilde opener before a 100-, 102- or 200-tilde run stays literal")
    func oneTildeOpenerBeforeLongRuns() {
        #expect(strikeText(input(openerLen: 1, tailCount: 100), options: Self.options) == nil)
        #expect(strikeText(input(openerLen: 1, tailCount: 102), options: Self.options) == nil)
        #expect(strikeText(input(openerLen: 1, tailCount: 200), options: Self.options) == nil)
    }

    @Test("a 101-tilde opener stays literal")
    func longOpenerStaysLiteral() {
        #expect(strikeText("**" + String(repeating: "~", count: 101) + ")~", options: Self.options) == nil)
    }

    @Test("one- and two-tilde runs pair with a run of the same length; three-tilde runs stay literal")
    func shortRuns() {
        #expect(strikeText("~x~", options: Self.options) == "x")
        #expect(strikeCount("~x~", options: Self.options) == 1)
        #expect(strikeText("~~x~~", options: Self.options) == "x")
        #expect(strikeCount("~~x~~", options: Self.options) == 1)
        #expect(strikeText("~~~x~~~", options: Self.options) == nil)
        #expect(strikeText("**~)~", options: Self.options) == ")")
        #expect(strikeCount("**~)~", options: Self.options) == 1)
        #expect(strikeText("**~~)~~", options: Self.options) == ")")
        #expect(strikeCount("**~~)~~", options: Self.options) == 1)
    }

    /// With `.strikethroughDoubleTilde`, only a two-tilde run delimits strikethrough.
    @Test("with double-tilde strikethrough, neither a 102-tilde nor a 101-tilde run closes")
    func doubleTildeLongRuns() {
        let options: MarkdownDocument.ParseOptions = [.strikethrough, .strikethroughDoubleTilde]
        #expect(strikeText(input(openerLen: 2, tailCount: 102), options: options) == nil)
        #expect(strikeText(input(openerLen: 1, tailCount: 101), options: options) == nil)
    }
}
