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
/// other kinds, and later paragraphs - and that every opener inside a failed stretch stays literal.
@Suite("Inline raw-HTML closer miss cache")
struct InlineHTMLCloserMissCacheTests {

    private func htmlLiterals(_ src: String, options: MarkdownDocument.ParseOptions) -> [String] {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> [String] in
            inlineHTMLLiterals(doc.root)
        }
    }

    // MARK: Every opener inside a failed stretch stays literal

    @Test("unclosed openers of one kind all stay literal")
    func unclosedOpenersStayLiteral() {
        #expect(htmlLiterals("x<!--a <!--b\n<!--c", options: []) == [])
        #expect(htmlLiterals("x<?a <?b\n<?c", options: []) == [])
        #expect(htmlLiterals("x<!A a <!B b\n<!C c", options: []) == [])
        #expect(htmlLiterals("x<![CDATA[a <![CDATA[b\n<![CDATA[c", options: []) == [])
    }

    // MARK: A closer that overlaps its own opener never closes it

    @Test("the comment closer search starts after `<!--`")
    func commentCloserSearchStartsAfterOpener() {
        // `<!-` + `->` would read as `-->` only if the search started inside the opener.
        #expect(htmlLiterals("x<!-> <!--a", options: []) == [])
        #expect(htmlLiterals("x<!--a <!-->", options: []) == ["<!--a <!-->"])
    }

    @Test("flag OFF: a later `<!--->` closes an earlier comment at its `-->`")
    func flagOffLaterDashEmptyCommentClosesEarlierComment() {
        #expect(htmlLiterals("x<!--a <!--->", options: []) == ["<!--a <!--->"])
    }

    @Test("the empty comments `<!-->` and `<!--->` match without a later closer")
    func emptyComments() {
        #expect(htmlLiterals("x<!--> <!--a", options: []) == ["<!-->"])
        #expect(htmlLiterals("x<!---> <!--a", options: []) == ["<!--->"])
    }

    @Test("the processing-instruction closer search starts after `<?`")
    func processingInstructionCloserSearchStartsAfterOpener() {
        #expect(htmlLiterals("x<?a <?>", options: []) == ["<?a <?>"])
        #expect(htmlLiterals("x<?a <?b ?>", options: []) == ["<?a <?b ?>"])
    }

    @Test("the CDATA closer search starts after `<![CDATA[`")
    func cdataCloserSearchStartsAfterOpener() {
        #expect(htmlLiterals("x<![CDATA[a <![CDATA[]]>", options: []) == ["<![CDATA[a <![CDATA[]]>"])
    }

    @Test("the declaration closer search starts after the name and its whitespace")
    func declarationCloserSearchStartsAfterName() {
        // The later `<!B` has no whitespace after its name, so it is no declaration; the `>` closes the first.
        #expect(htmlLiterals("x<!A a <!B>", options: []) == ["<!A a <!B>"])
        #expect(htmlLiterals("x<!A a\nb<!B c>", options: []) == ["<!A a\nb<!B c>"])
    }

    // MARK: A failed scan of one kind does not suppress another kind

    @Test("a failed processing instruction leaves later comments, CDATA, and declarations matchable")
    func failedProcessingInstructionLeavesOtherKinds() {
        #expect(htmlLiterals("x<?a <!--b-->", options: []) == ["<!--b-->"])
        #expect(htmlLiterals("x<?a <![CDATA[b]]>", options: []) == ["<![CDATA[b]]>"])
        #expect(htmlLiterals("x<?a <!B b>", options: []) == ["<!B b>"])
    }

    // Every raw-HTML construct ends in `>`, so after a failed declaration nothing later in the run can match.
    @Test("a failed CDATA leaves later declarations and processing instructions matchable")
    func failedCDATALeavesOtherKinds() {
        #expect(htmlLiterals("x<![CDATA[a <!B b>", options: []) == ["<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a <?b?>", options: []) == ["<?b?>"])
    }

    @Test("a failed comment leaves a later processing instruction matchable")
    func failedCommentLeavesProcessingInstruction() {
        #expect(htmlLiterals("x<!--a <?b?>", options: []) == ["<?b?>"])
    }

    @Test("flag OFF: a failed comment leaves later CDATA and declarations matchable")
    func flagOffFailedCommentLeavesBangForms() {
        #expect(htmlLiterals("x<!--a <![CDATA[b]]>", options: []) == ["<![CDATA[b]]>"])
        #expect(htmlLiterals("x<!--a <!B b>", options: []) == ["<!B b>"])
    }

    // MARK: Every opener of a kind after a matched construct of that kind is scanned afresh

    @Test("openers after a matched construct of the same kind are scanned afresh")
    func openersAfterMatchScannedAfresh() {
        #expect(htmlLiterals("x<!--a--> <!--b--> <!--c", options: []) == ["<!--a-->", "<!--b-->"])
        #expect(htmlLiterals("x<?a?> <?b?> <?c", options: []) == ["<?a?>", "<?b?>"])
        #expect(htmlLiterals("x<!A a> <!B b> <!C c", options: []) == ["<!A a>", "<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a]]> <![CDATA[b]]> <![CDATA[c", options: []) == ["<![CDATA[a]]>", "<![CDATA[b]]>"])
    }

    // MARK: NUL

    // NUL is replaced with U+FFFD before inline parsing (CommonMark §2.3), so these pin the observable
    // behaviour; the closer scan's NUL-stop branch is not reached through them.

    @Test("a NUL in a construct's body is replaced and does not end the closer search")
    func nulDoesNotEndCloserSearch() {
        #expect(htmlLiterals("x<!--a\u{0}<!--b-->", options: []) == ["<!--a\u{FFFD}<!--b-->"])
        #expect(htmlLiterals("x<?a\u{0}<?b?>", options: []) == ["<?a\u{FFFD}<?b?>"])
        #expect(htmlLiterals("x<!A a\u{0}<!B b>", options: []) == ["<!A a\u{FFFD}<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a\u{0}<![CDATA[b]]>", options: []) == ["<![CDATA[a\u{FFFD}<![CDATA[b]]>"])
    }

    // MARK: Separate paragraphs are scanned independently

    @Test("a failed scan in one paragraph does not suppress a match in the next")
    func failedScanDoesNotCrossParagraphs() {
        #expect(htmlLiterals("x<!--a\n\nx<!--b-->", options: []) == ["<!--b-->"])
        #expect(htmlLiterals("x<?a\n\nx<?b?>", options: []) == ["<?b?>"])
        #expect(htmlLiterals("x<!A a\n\nx<!B b>", options: []) == ["<!B b>"])
        #expect(htmlLiterals("x<![CDATA[a\n\nx<![CDATA[b]]>", options: []) == ["<![CDATA[b]]>"])
    }
}
