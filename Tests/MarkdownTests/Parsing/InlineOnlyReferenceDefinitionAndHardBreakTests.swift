/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// Inline-only parsing still extracts leading link reference definitions and still turns a backslash
/// before a line ending into a hard line break.
///
/// Ground truth is cmark-gfm, in both `.inlineOnly` and `.preserveWhitespace`. A reference definition at the
/// start of the input is consumed (and resolves later references) when content follows it; a lone definition,
/// or one preceded by a space, stays literal. A `\` immediately before a line ending is a LineBreak, while
/// trailing spaces or a tab before a line ending stay literal. Inline-only mode has no spec and its shipped
/// clients relied on cmark, so each case asserts the same surface with `.cmarkBugCompatibility` off.
/// Position-free compare surface.
class InlineOnlyReferenceDefinitionAndHardBreakTests: XCTestCase {
    private func surface(_ markdown: String, _ options: ParseOptions, cmarkBugCompatible: Bool = true) -> String {
        Document(parsing: markdown, options: cmarkBugCompatible ? options.union(.cmarkBugCompatibility) : options).debugDescription(options: [])
    }

    private let modes: [ParseOptions] = [.inlineOnly, .preserveWhitespace]

    func testLeadingDefinitionBeforeBlankLine() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\n\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\n\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n\n[a]", mode, cmarkBugCompatible: false))
        }
    }

    func testLeadingDefinitionThenReference() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n[a]", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x \"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u \"t\"\nx [a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"x \"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u \"t\"\nx [a]", mode, cmarkBugCompatible: false))
        }
    }

    func testDefinitionDestinationOnNextLine() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\n\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]:\n/u\n\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\n\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]:\n/u\n\n[a]", mode, cmarkBugCompatible: false))
        }
    }

    func testLiteralDefinitionControls() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[a]: /u\"", surface("[a]: /u", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[a]: /u\"", surface("[a]: /u", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \" [a]: /u\n\n[a]\"", surface(" [a]: /u\n\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \" [a]: /u\n\n[a]\"", surface(" [a]: /u\n\n[a]", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"x\n[a]: /u\n[a]\"", surface("x\n[a]: /u\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"x\n[a]: /u\n[a]\"", surface("x\n[a]: /u\n[a]", mode, cmarkBugCompatible: false))
        }
    }

    func testBackslashHardBreak() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"b\"", surface("a\\\nb", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"b\"", surface("a\\\nb", mode, cmarkBugCompatible: false))
        }
    }

    func testTrailingWhitespaceStaysLiteral() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a  \nb\"", surface("a  \nb", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a  \nb\"", surface("a  \nb", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a\t\nb\"", surface("a\t\nb", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a\t\nb\"", surface("a\t\nb", mode, cmarkBugCompatible: false))
        }
    }

    func testStackedLeadingDefinitions() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Link destination: \"/u\"\n   │  └─ Text \"a\"\n   ├─ Text \" \"\n   └─ Link destination: \"/v\"\n      └─ Text \"b\"", surface("[a]: /u\n[b]: /v\n[a] [b]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Link destination: \"/u\"\n   │  └─ Text \"a\"\n   ├─ Text \" \"\n   └─ Link destination: \"/v\"\n      └─ Text \"b\"", surface("[a]: /u\n[b]: /v\n[a] [b]", mode, cmarkBugCompatible: false))
        }
    }

    func testDefinitionTitleSpanningLines() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u \"t\nu\"\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u \"t\nu\"\n[a]", mode, cmarkBugCompatible: false))
            // A next-line title with trailing content is rejected; the definition ends after its destination.
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"(t) x\n\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n(t) x\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"(t) x\n\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n(t) x\n[a]", mode, cmarkBugCompatible: false))
        }
    }

    /// cmark keeps the paragraph (now empty, or whitespace-only) after extracting every definition: its
    /// empty-paragraph removal is gated off in inline-only modes.
    func testDefinitionFollowedOnlyByWhitespace() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph", surface("[a]: /u\n", mode))
            XCTAssertEqual("Document\n└─ Paragraph", surface("[a]: /u\n", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"  \"", surface("[a]: /u\n  ", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"  \"", surface("[a]: /u\n  ", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph", surface("[a]: /u \"t\"", mode))
            XCTAssertEqual("Document\n└─ Paragraph", surface("[a]: /u \"t\"", mode, cmarkBugCompatible: false))
        }
    }

    /// cmark's bare-destination scan fails when the destination reaches the very end of the input, which
    /// only inline-only content (no newline appended to its final line) can hit.
    func testDefinitionDestinationAtEndOfInputStaysLiteral() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[b]: /v\"", surface("[a]: /u\n[b]: /v", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[b]: /v\"", surface("[a]: /u\n[b]: /v", mode, cmarkBugCompatible: false))
        }
    }

    /// Flag-OFF keeps cmark's literal too: inline-only mode has no spec, and its shipped clients relied on cmark.
    func testDefinitionDestinationAtEndOfInputFlagOff() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[a]: /u\"", Document(parsing: "[a]: /u", options: mode).debugDescription(options: []))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[b]: /v\"", Document(parsing: "[a]: /u\n[b]: /v", options: mode).debugDescription(options: []))
        }
    }

    func testDefinitionAfterCRLF() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\r\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\r\n[a]", mode, cmarkBugCompatible: false))
        }
    }

    func testBackslashHardBreakEdges() {
        for mode in modes {
            // At end of input the backslash is literal.
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a\\\"", surface("a\\", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a\\\"", surface("a\\", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"b\"", surface("a\\\r\nb", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"b\"", surface("a\\\r\nb", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   └─ LineBreak", surface("a\\\n", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   └─ LineBreak", surface("a\\\n", mode, cmarkBugCompatible: false))
            // The next line's leading spaces stay literal.
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"  b\"", surface("a\\\n  b", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"  b\"", surface("a\\\n  b", mode, cmarkBugCompatible: false))
            // An escaped backslash does not break.
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a\\\nb\"", surface("a\\\\\nb", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a\\\nb\"", surface("a\\\\\nb", mode, cmarkBugCompatible: false))
        }
    }

    /// Definition extraction and the backslash hard break are not cmark quirks; flag-OFF matches cmark too.
    func testExtractionAndBackslashBreakFlagOff() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", Document(parsing: "[a]: /u\n[a]", options: mode).debugDescription(options: []))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"b\"", Document(parsing: "a\\\nb", options: mode).debugDescription(options: []))
        }
    }

    func testDefinitionEdgeForms() {
        for mode in modes {
            // A pointy destination reaching the end of input is rejected like a bare one.
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[a]: <>\"", surface("[a]: <>", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[a]: <>\"", surface("[a]: <>", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"u\"\n      └─ Text \"a\"", surface("[a]: <u> \"t\"\n[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Link destination: \"u\"\n      └─ Text \"a\"", surface("[a]: <u> \"t\"\n[a]", mode, cmarkBugCompatible: false))
            // Trailing space after the destination keeps it off the end of input, so the definition is consumed.
            XCTAssertEqual("Document\n└─ Paragraph", surface("[a]: /u ", mode))
            XCTAssertEqual("Document\n└─ Paragraph", surface("[a]: /u ", mode, cmarkBugCompatible: false))
            // Attribute definitions are consumed too; they have no destination, so one ending the input is accepted.
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"y\"", surface("^[x]: a\ny", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"y\"", surface("^[x]: a\ny", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph", surface("^[x]: a", mode))
            XCTAssertEqual("Document\n└─ Paragraph", surface("^[x]: a", mode, cmarkBugCompatible: false))
            // NUL forces the arena path; the definition is still consumed and the NUL becomes U+FFFD.
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\u{FFFD}\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n\u{0}[a]", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"\u{FFFD}\"\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface("[a]: /u\n\u{0}[a]", mode, cmarkBugCompatible: false))
        }
    }

    func testBackslashHardBreakAfterInlineConstruct() {
        for mode in modes {
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineCode `x`\n   ├─ LineBreak\n   └─ Text \"b\"", surface("`x`\\\nb", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ InlineCode `x`\n   ├─ LineBreak\n   └─ Text \"b\"", surface("`x`\\\nb", mode, cmarkBugCompatible: false))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Emphasis\n   │  └─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"b\"", surface("*a*\\\nb", mode))
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Emphasis\n   │  └─ Text \"a\"\n   ├─ LineBreak\n   └─ Text \"b\"", surface("*a*\\\nb", mode, cmarkBugCompatible: false))
        }
    }
}
