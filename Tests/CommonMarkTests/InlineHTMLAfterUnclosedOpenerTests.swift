/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The number of raw HTML nodes in the tree.
private func inlineHTMLCount(_ node: borrowing MarkdownNode) -> Int {
    var count = 0
    if case .htmlInline = node.kind {
        count += 1
    }
    node.children.forEach { child in
        count += inlineHTMLCount(child)
    }
    return count
}

/// Each raw HTML construct (Raw HTML) is recognized independently, so an unclosed opener of one kind doesn't keep a
/// later construct from matching. Every input starts with `x` so the construct is inline rather than an HTML block.
@Suite("Inline raw HTML after an unclosed opener")
struct InlineHTMLAfterUnclosedOpenerTests {

    private static let options: MarkdownDocument.ParseOptions = []

    private func htmlCount(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> Int {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> Int in
            inlineHTMLCount(doc.root)
        }
    }

    @Test("`x<![CDATA[a <![CDATA[b` is literal")
    func unclosedCDATAThenCDATAOpenerIsLiteral() {
        #expect(htmlCount("x<![CDATA[a <![CDATA[b", options: Self.options) == 0)
    }

    @Test("`x<!A x <!B y` is literal")
    func unclosedDeclarationThenDeclarationOpenerIsLiteral() {
        #expect(htmlCount("x<!A x <!B y", options: Self.options) == 0)
    }

    @Test("`x<?<??>` is one processing instruction")
    func processingInstructionContainingOpener() {
        #expect(htmlCount("x<?<??>", options: Self.options) == 1)
    }

    @Test("`x<!--<!--->` is one comment")
    func commentContainingOpener() {
        #expect(htmlCount("x<!--<!--->", options: Self.options) == 1)
    }

    @Test("`x<!--<![CDATA[y]]>`: the CDATA section after an unclosed comment is recognized")
    func cdataAfterUnclosedComment() {
        #expect(htmlCount("x<!--<![CDATA[y]]>", options: Self.options) == 1)
    }

    @Test("`x<!--<!DOCTYPE html>`: the declaration after an unclosed comment is recognized")
    func declarationAfterUnclosedComment() {
        #expect(htmlCount("x<!--<!DOCTYPE html>", options: Self.options) == 1)
    }

    @Test("a single processing instruction is recognized")
    func singleProcessingInstruction() {
        #expect(htmlCount("x<?php?>", options: Self.options) == 1)
    }

    @Test("two processing instructions are both recognized")
    func twoProcessingInstructions() {
        #expect(htmlCount("x<?a?><?b?>", options: Self.options) == 2)
    }

    @Test("a single comment is recognized")
    func singleComment() {
        #expect(htmlCount("x<!--y-->", options: Self.options) == 1)
    }

    @Test("a single CDATA section is recognized")
    func singleCDATA() {
        #expect(htmlCount("x<![CDATA[y]]>", options: Self.options) == 1)
    }

    @Test("a single declaration is recognized")
    func singleDeclaration() {
        #expect(htmlCount("x<!DOCTYPE html>", options: Self.options) == 1)
    }
}
