/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(Footnotes) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// The footnote quirks (`[^[` collapse, escaped-caret over-read, cross-line capture) in inline-only mode.
///
/// Ground truth is cmark-gfm. Each case is an existing footnote regression input re-run with the option
/// byte's inline-mode bit (`0x20`, plus `0x10` for preserveWhitespace); the expected surfaces are the
/// reference's output bytes. Inputs are `[markdown …][option byte]`, split as the fuzzer does.
class InlineOnlyFootnoteQuirkTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool = true) -> String {
        let (markdown, options) = FuzzRegressionTests.splitInput(bytes)!
        return Document(parsing: markdown, options: cmarkBugCompatible ? options.union(.cmarkBugCompatibility) : options).debugDescription(options: [])
    }

    func test_footnote_multiline_label_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\n\u{fffd}]\"", surface([91, 94, 10, 128, 93, 160]))
    }

    func test_footnote_multiline_label_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\n\u{fffd}]\"", surface([91, 94, 10, 128, 93, 176]))
    }

    func test_footnote_caret_bracket_innerclose_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^[\"", surface([91, 94, 91, 93, 10, 93, 160]))
    }

    func test_footnote_caret_bracket_innerclose_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^[\"", surface([91, 94, 91, 93, 10, 93, 176]))
    }

    func test_footnote_caret_bracket_spans_empty_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^[\"", surface([91, 94, 91, 10, 93, 93, 160]))
    }

    func test_footnote_caret_bracket_spans_empty_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^[\"", surface([91, 94, 91, 10, 93, 93, 176]))
    }

    func test_footnote_escaped_caret_crossline_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\nx]]\"", surface([91, 92, 94, 10, 120, 93, 160]))
    }

    func test_footnote_escaped_caret_crossline_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\nx]]\"", surface([91, 92, 94, 10, 120, 93, 176]))
    }

    func test_footnote_escaped_caret_image_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^x]\"", surface([33, 91, 92, 94, 120, 93, 160]))
    }

    func test_footnote_escaped_caret_image_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^x]\"", surface([33, 91, 92, 94, 120, 93, 176]))
    }

    func test_footnote_multiline_collapse_blockquote_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \">[^\n\u{fffd}]\"", surface([62, 91, 94, 10, 128, 93, 160]))
    }

    func test_footnote_multiline_collapse_blockquote_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \">[^\n\u{fffd}]\"", surface([62, 91, 94, 10, 128, 93, 176]))
    }

    func test_footnote_multiline_label_multibyte_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\n\u{fffd}p]\"", surface([91, 94, 10, 128, 112, 93, 160]))
    }

    func test_footnote_multiline_label_multibyte_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\n\u{fffd}p]\"", surface([91, 94, 10, 128, 112, 93, 176]))
    }

    // Probes beyond the regression inputs, expected surfaces derived from cmark's source (inline-only
    // buffer: no `handle_newline` column resets, no rtrim, NUL-terminated).

    func test_probe_crossline_plain_label_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a[^x\ny]b\"", surface(Array("a[^x\ny]b".utf8) + [160]))
    }

    func test_probe_crossline_plain_label_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a[^x\ny]b\"", surface(Array("a[^x\ny]b".utf8) + [176]))
    }

    func test_probe_crossline_crlf_label_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^a\nb]\"", surface(Array("[^a\r\nb]".utf8) + [160]))
    }

    func test_probe_crossline_crlf_label_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^a\nb]\"", surface(Array("[^a\r\nb]".utf8) + [176]))
    }

    /// A code span's newline still resets the column (`adjust_subj_node_newlines`, sourcepos on); the bare one after it doesn't.
    func test_probe_codespan_newline_resets_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^`a]\"", surface(Array("[^`a\nb`\nc]".utf8) + [160]))
    }

    func test_probe_codespan_newline_resets_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^`a]\"", surface(Array("[^`a\nb`\nc]".utf8) + [176]))
    }

    func test_probe_escaped_caret_crossline_long_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^abcdef\nxxxxx]]\"", surface(Array("[\\^abcdef\nxxxxx]".utf8) + [160]))
    }

    func test_probe_escaped_caret_crossline_long_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^abcdef\nxxxxx]]\"", surface(Array("[\\^abcdef\nxxxxx]".utf8) + [176]))
    }

    func test_probe_escaped_caret_image_crossline_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^a\nb]\"", surface(Array("![\\^a\nb]".utf8) + [160]))
    }

    func test_probe_escaped_caret_image_crossline_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^a\nb]\"", surface(Array("![\\^a\nb]".utf8) + [176]))
    }

    /// A source-final newline is part of the inline-only buffer, so the image over-read lands on it, not the NUL.
    func test_probe_escaped_caret_image_trailing_newline_io() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^x]\n]\n\"", surface(Array("![\\^x]\n".utf8) + [160]))
    }

    func test_probe_escaped_caret_image_trailing_newline_pw() {
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^x]\n]\n\"", surface(Array("![\\^x]\n".utf8) + [176]))
    }

    /// With source positions off (API-only in inline mode) `adjust_subj_node_newlines` returns early, so even the code span's newline doesn't reset.
    func test_probe_codespan_newline_sourcepos_off() {
        let options: ParseOptions = [.inlineOnly, .footnotes, .disableSourcePosOpts, .cmarkBugCompatibility]
        XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^`a\nb`\nc]\"", Document(parsing: "[^`a\nb`\nc]", options: options).debugDescription(options: []))
    }

    // Flag-off (shipped): the same inputs in both inline-only modes.

    func test_footnote_multiline_label_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\n\u{fffd}]\"", surface([91, 94, 10, 128, 93] + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// A footnote reference label cannot hold an unescaped `[`, so the bracket run stays literal text, where cmark-gfm collapses it to `[^[`.
    func test_footnote_caret_bracket_innerclose_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^[]\n]\"", surface([91, 94, 91, 93, 10, 93] + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// A footnote reference label cannot hold an unescaped `[`, so the bracket run stays literal text, where cmark-gfm collapses it to `[^[`.
    func test_footnote_caret_bracket_spans_empty_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^[\n]]\"", surface([91, 94, 91, 10, 93, 93] + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// An escaped `^` is a literal caret, so the text keeps its single `]`, where cmark-gfm over-reads a second `]`.
    func test_footnote_escaped_caret_crossline_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\nx]\"", surface([91, 92, 94, 10, 120, 93] + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// An escaped `^` is a literal caret, so the text keeps its leading `!`, where cmark-gfm drops it.
    func test_footnote_escaped_caret_image_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"![^x]\"", surface([33, 91, 92, 94, 120, 93] + [optionByte], cmarkBugCompatible: false))
        }
    }

    func test_footnote_multiline_collapse_blockquote_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \">[^\n\u{fffd}]\"", surface([62, 91, 94, 10, 128, 93] + [optionByte], cmarkBugCompatible: false))
        }
    }

    func test_footnote_multiline_label_multibyte_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^\n\u{fffd}p]\"", surface([91, 94, 10, 128, 112, 93] + [optionByte], cmarkBugCompatible: false))
        }
    }

    func test_probe_crossline_plain_label_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"a[^x\ny]b\"", surface(Array("a[^x\ny]b".utf8) + [optionByte], cmarkBugCompatible: false))
        }
    }

    func test_probe_crossline_crlf_label_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^a\nb]\"", surface(Array("[^a\r\nb]".utf8) + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// Backticks form a code span whose line ending becomes a space, where cmark-gfm collapses the unresolved footnote bracket over it to `[^`a]`.
    func test_probe_codespan_newline_resets_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `a b`\n   └─ Text \"\nc]\"", surface(Array("[^`a\nb`\nc]".utf8) + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// An escaped `^` is a literal caret, so the text keeps its single `]`, where cmark-gfm over-reads a second `]`.
    func test_probe_escaped_caret_crossline_long_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"[^abcdef\nxxxxx]\"", surface(Array("[\\^abcdef\nxxxxx]".utf8) + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// An escaped `^` is a literal caret, so the text keeps its leading `!`, where cmark-gfm drops it.
    func test_probe_escaped_caret_image_crossline_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"![^a\nb]\"", surface(Array("![\\^a\nb]".utf8) + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// An escaped `^` is a literal caret, so the text is the source with its `!` and no extra `]`, where cmark-gfm drops the `!` and over-reads a `]`.
    func test_probe_escaped_caret_image_trailing_newline_flag_off() {
        for optionByte: UInt8 in [160, 176] {
            XCTAssertEqual("Document\n└─ Paragraph\n   └─ Text \"![^x]\n\"", surface(Array("![\\^x]\n".utf8) + [optionByte], cmarkBugCompatible: false))
        }
    }

    /// Flag-off (shipped): with source positions off too, backticks form a code span whose line ending
    /// becomes a space, where cmark-gfm keeps the whole bracket run literal.
    func test_probe_codespan_newline_sourcepos_off_flag_off() {
        let options: ParseOptions = [.inlineOnly, .footnotes, .disableSourcePosOpts]
        XCTAssertEqual("Document\n└─ Paragraph\n   ├─ Text \"[^\"\n   ├─ InlineCode `a b`\n   └─ Text \"\nc]\"", Document(parsing: "[^`a\nb`\nc]", options: options).debugDescription(options: []))
    }
}
