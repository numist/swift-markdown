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
/// This is a `[ref-b4b]` quirk: reproduced ONLY under `.cmarkBugCompatibility` (adopted by the
/// differential fuzzer). The shipped deliverable (flag OFF) stays spec-correct — CommonMark 0.31 §6.6
/// attempts each construct independently, so a later well-formed construct is recognized regardless of an
/// earlier overrun. The quirk is STRUCTURAL (an `.htmlInline` node appears or not), gated on
/// `.cmarkBugCompatibility` alone with no positions dependency; these tests parse without `.sourcePosition`.
///
/// Every input carries a leading `x` so the `<`-construct is parsed as INLINE HTML inside a paragraph
/// rather than as a leading HTML block (block start conditions require the marker at line start). The two
/// fuzzer artifacts that motivated this fix carried a leading `\u{FFFD}` (from NUL→U+FFFD materialization)
/// which serves the same purpose.
///
/// Observability of the four flags: PI and COMMENT are directly observable (a later `<?…?>`, or a later
/// empty comment `<!-->`/`<!--->`, matches without the terminator the earlier overrun ruled out). The
/// COMMENT flag is additionally observable through the bang gate (a comment overrun suppresses a later
/// well-formed `<![CDATA[…]]>` / `<!DOCTYPE …>`). The CDATA and DECLARATION *own* flags are inert on
/// output — a CDATA/declaration overrun means no `]]>` / `>` exists through end-of-input, so no later
/// CDATA/declaration in the same run could have matched anyway — but the flags are still set to mirror
/// cmark's control flow; the own-flag paths below lock that behavior in (identical under both flags).
@Suite("Inline raw-HTML overrun skip-flag quirk")
struct InlineHTMLScanSkipQuirkTests {

    private static let flagOff: MarkdownDocument.ParseOptions = []
    private static let flagOn: MarkdownDocument.ParseOptions = [.cmarkBugCompatibility]

    private func htmlCount(
        _ src: String, options: MarkdownDocument.ParseOptions
    ) throws -> Int {
        try MarkdownDocument.withParsedDocument(src, options: options) { doc -> Int in
            inlineHTMLCount(doc.root)
        }
    }

    // MARK: Flag ON — reproduce cmark's overrun-skip (all-literal, no `.htmlInline`)

    @Test("flag ON: `x<?<??>` — PI overrun makes the later `<?` stay literal")
    func flagOnPIOverrunSkipsLater() throws {
        // The first `<?` greedily consumes `<??>` (cmark's PI body admits a lone `>` and pairs each `?`
        // with its following byte), leaving no room for the framing `?>`, so it overruns EOF and sets the
        // PI skip flag. The second `<?` is then skipped; all bytes stay literal.
        #expect(try htmlCount("x<?<??>", options: Self.flagOn) == 0)
    }

    @Test("flag ON: `x<!--<!--->` — comment overrun makes the later empty comment stay literal")
    func flagOnCommentOverrunSkipsLater() throws {
        // The first `<!--` body scans to EOF without a valid `-->` closer (strict grammar), setting the
        // comment skip flag. The later empty comment `<!--->` (which needs no `-->`) is then suppressed.
        #expect(try htmlCount("x<!--<!--->", options: Self.flagOn) == 0)
    }

    @Test("flag ON: `x<!--<![CDATA[y]]>` — comment overrun suppresses the later CDATA (bang gate)")
    func flagOnCommentOverrunSuppressesCDATA() throws {
        // The comment overrun sets the comment skip flag, which gates the whole `<!` dispatch, so the
        // otherwise-well-formed `<![CDATA[y]]>` is never attempted.
        #expect(try htmlCount("x<!--<![CDATA[y]]>", options: Self.flagOn) == 0)
    }

    @Test("flag ON: `x<!--<!DOCTYPE html>` — comment overrun suppresses the later declaration (bang gate)")
    func flagOnCommentOverrunSuppressesDeclaration() throws {
        #expect(try htmlCount("x<!--<!DOCTYPE html>", options: Self.flagOn) == 0)
    }

    // MARK: Flag ON controls — a well-formed construct is recognized; skip fires only AFTER an overrun

    @Test("flag ON control: a single well-formed PI is recognized")
    func flagOnControlSinglePI() throws {
        #expect(try htmlCount("x<?php?>", options: Self.flagOn) == 1)
    }

    @Test("flag ON control: two well-formed PIs (no overrun) are BOTH recognized")
    func flagOnControlTwoPIs() throws {
        #expect(try htmlCount("x<?a?><?b?>", options: Self.flagOn) == 2)
    }

    @Test("flag ON control: a single well-formed comment is recognized")
    func flagOnControlSingleComment() throws {
        #expect(try htmlCount("x<!--y-->", options: Self.flagOn) == 1)
    }

    @Test("flag ON control: a single well-formed CDATA is recognized")
    func flagOnControlSingleCDATA() throws {
        #expect(try htmlCount("x<![CDATA[y]]>", options: Self.flagOn) == 1)
    }

    @Test("flag ON control: a single well-formed declaration is recognized")
    func flagOnControlSingleDeclaration() throws {
        #expect(try htmlCount("x<!DOCTYPE html>", options: Self.flagOn) == 1)
    }

    // MARK: CDATA / declaration own-flag paths — inert on output (identical under both flags)

    @Test("own-flag: `x<![CDATA[a <![CDATA[b` — CDATA overrun, later CDATA stays literal (flag ON)")
    func cdataOverrunOwnFlagOn() throws {
        // No `]]>` exists through EOF, so neither CDATA can close. Exercises the CDATA skip-flag SET path.
        #expect(try htmlCount("x<![CDATA[a <![CDATA[b", options: Self.flagOn) == 0)
    }

    @Test("own-flag: `x<![CDATA[a <![CDATA[b` — literal under flag OFF too (inert)")
    func cdataOverrunOwnFlagOff() throws {
        #expect(try htmlCount("x<![CDATA[a <![CDATA[b", options: Self.flagOff) == 0)
    }

    @Test("own-flag: `x<!A x <!B y` — declaration overrun, later declaration stays literal (flag ON)")
    func declarationOverrunOwnFlagOn() throws {
        // No `>` exists through EOF, so neither declaration can close. Exercises the declaration
        // skip-flag SET path.
        #expect(try htmlCount("x<!A x <!B y", options: Self.flagOn) == 0)
    }

    @Test("own-flag: `x<!A x <!B y` — literal under flag OFF too (inert)")
    func declarationOverrunOwnFlagOff() throws {
        #expect(try htmlCount("x<!A x <!B y", options: Self.flagOff) == 0)
    }

    // MARK: Flag OFF — the deliverable stays spec-correct (each construct attempted independently)

    @Test("flag OFF: `x<?<??>` is recognized as one PI (no skip)")
    func flagOffPINoSkip() throws {
        #expect(try htmlCount("x<?<??>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF: `x<!--<!--->` is recognized as one comment (no skip)")
    func flagOffCommentNoSkip() throws {
        #expect(try htmlCount("x<!--<!--->", options: Self.flagOff) == 1)
    }

    @Test("flag OFF: `x<!--<![CDATA[y]]>` — the later CDATA is recognized (no bang gate)")
    func flagOffCDATANotSuppressed() throws {
        #expect(try htmlCount("x<!--<![CDATA[y]]>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF: `x<!--<!DOCTYPE html>` — the later declaration is recognized (no bang gate)")
    func flagOffDeclarationNotSuppressed() throws {
        #expect(try htmlCount("x<!--<!DOCTYPE html>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF control: a single well-formed PI is recognized")
    func flagOffControlSinglePI() throws {
        #expect(try htmlCount("x<?php?>", options: Self.flagOff) == 1)
    }

    @Test("flag OFF control: two well-formed PIs are BOTH recognized")
    func flagOffControlTwoPIs() throws {
        #expect(try htmlCount("x<?a?><?b?>", options: Self.flagOff) == 2)
    }
}
