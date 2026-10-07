/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Shared ASCII byte-classifier predicates on `UInt8`.
///
/// The parsers work over raw UTF-8 bytes, so these live on `UInt8` rather than any one parser type - `BlockParser`, the InlineParser extensions, and `EntityParser` all classify bytes and none should re-derive the ranges inline. They're `@inline(__always)` because they sit in the hot byte-scanning loops.
extension UInt8 {
    /// ASCII letter: `a`-`z` or `A`-`Z`.
    @inline(__always)
    var isASCIILetter: Bool {
        (self >= UInt8(ascii: "a") && self <= UInt8(ascii: "z"))
            || (self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z"))
    }

    /// Uppercase ASCII letter: `A`-`Z`.
    @inline(__always)
    var isUppercaseASCIILetter: Bool {
        self >= UInt8(ascii: "A") && self <= UInt8(ascii: "Z")
    }

    /// ASCII decimal digit: `0`-`9`.
    @inline(__always)
    var isASCIIDigit: Bool {
        self >= UInt8(ascii: "0") && self <= UInt8(ascii: "9")
    }

    /// Space or horizontal tab (ASCII "blank").
    @inline(__always)
    var isSpaceOrTab: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
    }

    /// Space, horizontal tab, line feed, or carriage return.
    @inline(__always)
    var isSpaceTabOrNewline: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
            || self == UInt8(ascii: "\n") || self == UInt8(ascii: "\r")
    }

    /// GFM extension-scanner whitespace: space, tab, vertical tab (0x0B), or form feed (0x0C).
    ///
    /// This is the `spacechar = [ \t\v\f]` defined once in cmark's `ext_scanners.re` and shared by the
    /// GFM extension scanners: `scan_table_start` pads a delimiter marker with it
    /// (`table_marker = spacechar*[:]?[-]+[:]?spacechar*`) and `scan_tasklist` requires it after the
    /// checkbox (`... ("[ ]"|"[x]") spacechar+`). It deliberately excludes CR/LF (line terminators).
    /// It is scanner-local: cmark's content trims (`cmark_strbuf_trim` / `cmark_isspace`,
    /// `S_find_first_nonspace`) do NOT treat VT/FF as whitespace, so this notion must not be applied to
    /// cell content, task-item content, or any other `cmark_isspace`-based construct.
    @inline(__always)
    var isExtensionScannerSpace: Bool {
        self == UInt8(ascii: " ") || self == UInt8(ascii: "\t")
            || self == 0x0B || self == 0x0C
    }

    /// ASCII whitespace: space, tab, newline, carriage return, vertical tab, or form feed.
    @inline(__always)
    var isASCIISpace: Bool {
        switch self {
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"),
             UInt8(ascii: "\r"), 0x0B, 0x0C:
            return true
        default:
            return false
        }
    }

    /// Inline delimiter-run flanking whitespace: space, tab, line feed, carriage return, or form
    /// feed (0x0C).
    ///
    /// This is the ASCII subset of cmark's `cmark_utf8proc_is_space` (`src/utf8.c`, "anything in the
    /// Zs class, plus LF, CR, TAB, FF"), the predicate `scan_delims` uses to classify the characters
    /// bordering an emphasis / strikethrough / smart-quote run. It deliberately differs from
    /// `isASCIISpace` (cmark's HTML `spacechar = [ \t\v\f\r\n]`) by EXCLUDING vertical tab (0x0B):
    /// cmark counts VT as a non-space for flanking, so `~<VT>~` flanks and pairs into a strikethrough
    /// while `~<FF>~` (FF is a flanking space) leaves the tildes non-flanking and literal. Non-ASCII
    /// whitespace (NBSP and the other Zs code points) is multi-byte and classified at the call site.
    @inline(__always)
    var isFlankingSpace: Bool {
        switch self {
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"),
             UInt8(ascii: "\r"), 0x0C:
            return true
        default:
            return false
        }
    }

    /// ASCII punctuation: the 32 ASCII punctuation marks per CommonMark §2.1.
    @inline(__always)
    var isASCIIPunct: Bool {
        switch self {
        case UInt8(ascii: "!"), UInt8(ascii: "\""), UInt8(ascii: "#"),
             UInt8(ascii: "$"), UInt8(ascii: "%"), UInt8(ascii: "&"),
             UInt8(ascii: "'"), UInt8(ascii: "("), UInt8(ascii: ")"),
             UInt8(ascii: "*"), UInt8(ascii: "+"), UInt8(ascii: ","),
             UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "/"),
             UInt8(ascii: ":"), UInt8(ascii: ";"), UInt8(ascii: "<"),
             UInt8(ascii: "="), UInt8(ascii: ">"), UInt8(ascii: "?"),
             UInt8(ascii: "@"), UInt8(ascii: "["), UInt8(ascii: "\\"),
             UInt8(ascii: "]"), UInt8(ascii: "^"), UInt8(ascii: "_"),
             UInt8(ascii: "`"), UInt8(ascii: "{"), UInt8(ascii: "|"),
             UInt8(ascii: "}"), UInt8(ascii: "~"):
            return true
        default:
            return false
        }
    }
}
