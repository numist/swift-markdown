/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
@testable import CommonMark

// Count of `.htmlInline` nodes in the tree. File-scope + `borrowing MarkdownNode` to satisfy the
// noncopyable-borrow rules (see code-conventions: use file-scope helpers, don't capture the borrow
// across the tree walk).
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

/// cmark-gfm keeps a per-text-run flag per inline raw-HTML construct KIND (`src/inlines.c`
/// `handle_pointy_brace`, `FLAG_SKIP_HTML_{COMMENT,CDATA,DECLARATION,PI}` on `subj->flags`). When a scan
/// of a given kind overruns to end-of-input without closing, cmark sets that kind's flag; on every later
/// attempt of the same kind in that run it checks the flag first and, if set, emits a literal `<` instead
/// of re-scanning. The COMMENT flag is special: it gates the ENTIRE `<!` dispatch
/// (`if (c == '!' && (subj->flags & FLAG_SKIP_HTML_COMMENT) == 0)`), so a comment overrun ALSO suppresses
/// later CDATA and declaration matches in the same run.
///
/// The shipped deliverable (flag OFF) stays spec-correct — CommonMark 0.31 §6.6
/// attempts each construct independently, so a later well-formed construct is recognized regardless of an
/// earlier overrun. These tests parse without `.sourcePosition`.
///
/// Every input carries a leading `x` so the `<`-construct is parsed as INLINE HTML inside a paragraph
/// rather than as a leading HTML block (block start conditions require the marker at line start).
@Suite("Inline raw-HTML overrun skip-flag quirk")
struct InlineHTMLScanSkipQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []

    private func htmlCount(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) -> Int {
        MarkdownDocument.withParsedDocument(src, options: options) { doc -> Int in
            inlineHTMLCount(doc.root)
        }
    }

    // MARK: CDATA / declaration own-flag paths — inert on output

    @Test("own-flag: `x<![CDATA[a <![CDATA[b` — literal under flag OFF too (inert)")
    func cdataOverrunOwnFlagOff() {
        #expect(htmlCount("x<![CDATA[a <![CDATA[b", options: Self.flagOff) == 0)
    }

    @Test("own-flag: `x<!A x <!B y` — literal under flag OFF too (inert)")
    func declarationOverrunOwnFlagOff() {
        #expect(htmlCount("x<!A x <!B y", options: Self.flagOff) == 0)
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (each construct attempted independently)

    @Test("flag OFF: `x<?<??>` is recognized as one PI (no skip)")
    func flagOffPINoSkip() {
        #expect(htmlCount("x<?<??>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF: `x<!--<!--->` is recognized as one comment (no skip)")
    func flagOffCommentNoSkip() {
        #expect(htmlCount("x<!--<!--->", options: Self.flagOff) == 1)
    }

    @Test("flag OFF: `x<!--<![CDATA[y]]>` — the later CDATA is recognized (no bang gate)")
    func flagOffCDATANotSuppressed() {
        #expect(htmlCount("x<!--<![CDATA[y]]>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF: `x<!--<!DOCTYPE html>` — the later declaration is recognized (no bang gate)")
    func flagOffDeclarationNotSuppressed() {
        #expect(htmlCount("x<!--<!DOCTYPE html>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF control: a single well-formed PI is recognized")
    func flagOffControlSinglePI() {
        #expect(htmlCount("x<?php?>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF control: two well-formed PIs are BOTH recognized")
    func flagOffControlTwoPIs() {
        #expect(htmlCount("x<?a?><?b?>", options: Self.flagOff) == 2)
    }

    @Test("flag OFF control: a single well-formed comment is recognized")
    func flagOffControlSingleComment() {
        #expect(htmlCount("x<!--y-->", options: Self.flagOff) == 1)
    }

    @Test("flag OFF control: a single well-formed CDATA is recognized")
    func flagOffControlSingleCDATA() {
        #expect(htmlCount("x<![CDATA[y]]>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF control: a single well-formed declaration is recognized")
    func flagOffControlSingleDeclaration() {
        #expect(htmlCount("x<!DOCTYPE html>", options: Self.flagOff) == 1)
    }
}
