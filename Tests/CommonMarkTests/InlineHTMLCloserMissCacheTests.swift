/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Literals of every `.htmlInline` node in the tree, in document order. File-scope + `borrowing MarkdownNode`
// to satisfy the noncopyable-borrow rules.
private func inlineHTMLLiterals(_ node: borrowing MarkdownNode) -> [String] {
    var literals: [String] = []
    if case .htmlInline = node.kind {
        literals.append(node.literal() ?? "")
    }
    node.children.forEach { child in
        literals += inlineHTMLLiterals(child)
    }
    return literals
}

/// An unclosed raw-HTML opener (`<!--`, `<?`, `<!X `, `<![CDATA[`) scans to its closer, a NUL, or the end of
/// the inline content. Once a scan of one kind has failed from some offset, a later opener of that kind whose
/// scan starts inside the failed stretch is known to fail too, without rescanning. These cases pin down that
/// every construct that must still match does - the empty comments, closers that overlap a later opener, the
/// other kinds, and later paragraphs - and that every opener inside a failed stretch stays literal, in both
/// flag states.
@Suite("Inline raw-HTML closer miss cache")
struct InlineHTMLCloserMissCacheTests {

    private static let bothFlagStates: [MarkdownDocument.ParseOptions] = [[], [.cmarkBugCompatibility]]

    private func htmlLiterals(_ src: String, options: MarkdownDocument.ParseOptions) throws -> [String] {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> [String] in
            inlineHTMLLiterals(doc.root)
        }
    }

    // MARK: Every opener inside a failed stretch stays literal

    @Test("unclosed openers of one kind all stay literal", arguments: bothFlagStates)
    func unclosedOpenersStayLiteral(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<!--a <!--b\n<!--c", options: options) == [])
        #expect(try htmlLiterals("x<?a <?b\n<?c", options: options) == [])
        #expect(try htmlLiterals("x<!A a <!B b\n<!C c", options: options) == [])
        #expect(try htmlLiterals("x<![CDATA[a <![CDATA[b\n<![CDATA[c", options: options) == [])
    }

    // MARK: A closer that overlaps its own opener never closes it

    @Test("the comment closer search starts after `<!--`", arguments: bothFlagStates)
    func commentCloserSearchStartsAfterOpener(options: MarkdownDocument.ParseOptions) throws {
        // `<!-` + `->` would read as `-->` only if the search started inside the opener.
        #expect(try htmlLiterals("x<!-> <!--a", options: options) == [])
        #expect(try htmlLiterals("x<!--a <!-->", options: options) == ["<!--a <!-->"])
    }

    @Test("flag OFF: a later `<!--->` closes an earlier comment at its `-->`")
    func flagOffLaterDashEmptyCommentClosesEarlierComment() throws {
        #expect(try htmlLiterals("x<!--a <!--->", options: []) == ["<!--a <!--->"])
    }

    @Test("flag ON: a later `<!--->` does not close an earlier comment (cmark's comment grammar)")
    func flagOnLaterDashEmptyCommentDoesNotCloseEarlierComment() throws {
        #expect(try htmlLiterals("x<!--a <!--->", options: [.cmarkBugCompatibility]) == [])
    }

    @Test("the empty comments `<!-->` and `<!--->` match without a later closer", arguments: bothFlagStates)
    func emptyComments(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<!--> <!--a", options: options) == ["<!-->"])
        #expect(try htmlLiterals("x<!---> <!--a", options: options) == ["<!--->"])
    }

    @Test("the processing-instruction closer search starts after `<?`", arguments: bothFlagStates)
    func processingInstructionCloserSearchStartsAfterOpener(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<?a <?>", options: options) == ["<?a <?>"])
        #expect(try htmlLiterals("x<?a <?b ?>", options: options) == ["<?a <?b ?>"])
    }

    @Test("the CDATA closer search starts after `<![CDATA[`", arguments: bothFlagStates)
    func cdataCloserSearchStartsAfterOpener(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<![CDATA[a <![CDATA[]]>", options: options) == ["<![CDATA[a <![CDATA[]]>"])
    }

    @Test("the declaration closer search starts after the name and its whitespace", arguments: bothFlagStates)
    func declarationCloserSearchStartsAfterName(options: MarkdownDocument.ParseOptions) throws {
        // The later `<!B` has no whitespace after its name, so it is no declaration; the `>` closes the first.
        #expect(try htmlLiterals("x<!A a <!B>", options: options) == ["<!A a <!B>"])
        #expect(try htmlLiterals("x<!A a\nb<!B c>", options: options) == ["<!A a\nb<!B c>"])
    }

    // MARK: A failed scan of one kind does not suppress another kind

    @Test("a failed processing instruction leaves later comments, CDATA, and declarations matchable", arguments: bothFlagStates)
    func failedProcessingInstructionLeavesOtherKinds(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<?a <!--b-->", options: options) == ["<!--b-->"])
        #expect(try htmlLiterals("x<?a <![CDATA[b]]>", options: options) == ["<![CDATA[b]]>"])
        #expect(try htmlLiterals("x<?a <!B b>", options: options) == ["<!B b>"])
    }

    // Every raw-HTML construct ends in `>`, so after a failed declaration nothing later in the run can match.
    @Test("a failed CDATA leaves later declarations and processing instructions matchable", arguments: bothFlagStates)
    func failedCDATALeavesOtherKinds(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<![CDATA[a <!B b>", options: options) == ["<!B b>"])
        #expect(try htmlLiterals("x<![CDATA[a <?b?>", options: options) == ["<?b?>"])
    }

    @Test("a failed comment leaves a later processing instruction matchable", arguments: bothFlagStates)
    func failedCommentLeavesProcessingInstruction(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<!--a <?b?>", options: options) == ["<?b?>"])
    }

    @Test("flag OFF: a failed comment leaves later CDATA and declarations matchable")
    func flagOffFailedCommentLeavesBangForms() throws {
        #expect(try htmlLiterals("x<!--a <![CDATA[b]]>", options: []) == ["<![CDATA[b]]>"])
        #expect(try htmlLiterals("x<!--a <!B b>", options: []) == ["<!B b>"])
    }

    // MARK: Every opener of a kind after a matched construct of that kind is scanned afresh

    @Test("openers after a matched construct of the same kind are scanned afresh", arguments: bothFlagStates)
    func openersAfterMatchScannedAfresh(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<!--a--> <!--b--> <!--c", options: options) == ["<!--a-->", "<!--b-->"])
        #expect(try htmlLiterals("x<?a?> <?b?> <?c", options: options) == ["<?a?>", "<?b?>"])
        #expect(try htmlLiterals("x<!A a> <!B b> <!C c", options: options) == ["<!A a>", "<!B b>"])
        #expect(try htmlLiterals("x<![CDATA[a]]> <![CDATA[b]]> <![CDATA[c", options: options) == ["<![CDATA[a]]>", "<![CDATA[b]]>"])
    }

    // MARK: NUL

    // NUL is replaced with U+FFFD before inline parsing (CommonMark §2.3), so these pin the observable
    // behaviour; the closer scan's NUL-stop branch is not reached through them.

    @Test("a NUL in a construct's body is replaced and does not end the closer search", arguments: bothFlagStates)
    func nulDoesNotEndCloserSearch(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<!--a\u{0}<!--b-->", options: options) == ["<!--a\u{FFFD}<!--b-->"])
        #expect(try htmlLiterals("x<?a\u{0}<?b?>", options: options) == ["<?a\u{FFFD}<?b?>"])
        #expect(try htmlLiterals("x<!A a\u{0}<!B b>", options: options) == ["<!A a\u{FFFD}<!B b>"])
        #expect(try htmlLiterals("x<![CDATA[a\u{0}<![CDATA[b]]>", options: options) == ["<![CDATA[a\u{FFFD}<![CDATA[b]]>"])
    }

    // MARK: Separate paragraphs are scanned independently

    @Test("a failed scan in one paragraph does not suppress a match in the next", arguments: bothFlagStates)
    func failedScanDoesNotCrossParagraphs(options: MarkdownDocument.ParseOptions) throws {
        #expect(try htmlLiterals("x<!--a\n\nx<!--b-->", options: options) == ["<!--b-->"])
        #expect(try htmlLiterals("x<?a\n\nx<?b?>", options: options) == ["<?b?>"])
        #expect(try htmlLiterals("x<!A a\n\nx<!B b>", options: options) == ["<!B b>"])
        #expect(try htmlLiterals("x<![CDATA[a\n\nx<![CDATA[b]]>", options: options) == ["<![CDATA[b]]>"])
    }
}
