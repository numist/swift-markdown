/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A label's bytes are those of its block content, and a paragraph continuation line that its containers don't continue
/// (a lazy continuation line) keeps its leading whitespace in that content: each space and each tab counts one byte,
/// and the columns left of a tab that a container's prefix partly consumed count one byte each (Tabs). A continuation
/// line its containers continue keeps no leading whitespace. A footnote reference's label counts the same bytes.
///
/// With byte limits of 6, each label below is a line ending, the lazy line's whitespace, and enough letters to make 6
/// bytes, then 7. The lazy line's whitespace counts 3 bytes for three spaces, 1 for a tab, and in a nested block quote
/// 3 for four spaces and 2 for a tab after the outer `>`, whose optional space takes one column, or 1 when that `>` is
/// indented one space. A link or attribute reference's definition writes its label on one line, so where the lazy line
/// has no whitespace, the 7-byte label's definition is past the limit too.
@Suite("Lazy continuation line whitespace in label bytes")
struct LazyContinuationLabelBytesTests {

    private static let limits: MarkdownDocument.ParseLimits = {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxLinkLabelBytes = 6
        limits.maxFootnoteLabelBytes = 6
        return limits
    }()

    static let cases: [(markdown: String, options: MarkdownDocument.ParseOptions, expected: String)] = [
        // MARK: definition
        ("> [abcd\nb]: /u\n\n[abcd b]", [], """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "abcd b"

            """),
        ("> [abcde\nb]: /u\n\n[abcde b]", [], """
            document
              block_quote
                paragraph
                  text "[abcde"
                  softbreak
                  text "b]: /u"
              paragraph
                text "[abcde b]"

            """),
        ("> [a\n   b]: /u\n\n[a b]", [], """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "a b"

            """),
        ("> [ab\n   b]: /u\n\n[ab b]", [], """
            document
              block_quote
                paragraph
                  text "[ab"
                  softbreak
                  text "b]: /u"
              paragraph
                text "[ab b]"

            """),
        ("> [abc\n\tb]: /u\n\n[abc b]", [], """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "abc b"

            """),
        ("> [abcd\n\tb]: /u\n\n[abcd b]", [], """
            document
              block_quote
                paragraph
                  text "[abcd"
                  softbreak
                  text "b]: /u"
              paragraph
                text "[abcd b]"

            """),
        ("> > [abcd\n>b]: /u\n\n[abcd b]", [], """
            document
              block_quote
                block_quote
              paragraph
                link "/u" ""
                  text "abcd b"

            """),
        ("> > [abcde\n>b]: /u\n\n[abcde b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[abcde"
                    softbreak
                    text "b]: /u"
              paragraph
                text "[abcde b]"

            """),
        ("> > [a\n>    b]: /u\n\n[a b]", [], """
            document
              block_quote
                block_quote
              paragraph
                link "/u" ""
                  text "a b"

            """),
        ("> > [ab\n>    b]: /u\n\n[ab b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[ab"
                    softbreak
                    text "b]: /u"
              paragraph
                text "[ab b]"

            """),
        ("> > [ab\n>\tb]: /u\n\n[ab b]", [], """
            document
              block_quote
                block_quote
              paragraph
                link "/u" ""
                  text "ab b"

            """),
        ("> > [abc\n>\tb]: /u\n\n[abc b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[abc"
                    softbreak
                    text "b]: /u"
              paragraph
                text "[abc b]"

            """),
        (" > > [abc\n >\tb]: /u\n\n[abc b]", [], """
            document
              block_quote
                block_quote
              paragraph
                link "/u" ""
                  text "abc b"

            """),
        (" > > [abcd\n >\tb]: /u\n\n[abcd b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[abcd"
                    softbreak
                    text "b]: /u"
              paragraph
                text "[abcd b]"

            """),
        ("100. [abcd\nb]: /u\n\n[abcd b]", [], """
            document
              list ordered start=100 delim=period tight
                item
              paragraph
                link "/u" ""
                  text "abcd b"

            """),
        ("100. [abcde\nb]: /u\n\n[abcde b]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[abcde"
                    softbreak
                    text "b]: /u"
              paragraph
                text "[abcde b]"

            """),
        ("100. [a\n   b]: /u\n\n[a b]", [], """
            document
              list ordered start=100 delim=period tight
                item
              paragraph
                link "/u" ""
                  text "a b"

            """),
        ("100. [ab\n   b]: /u\n\n[ab b]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[ab"
                    softbreak
                    text "b]: /u"
              paragraph
                text "[ab b]"

            """),
        ("100. [abc\n\tb]: /u\n\n[abc b]", [], """
            document
              list ordered start=100 delim=period tight
                item
              paragraph
                link "/u" ""
                  text "abc b"

            """),
        ("100. [abcd\n\tb]: /u\n\n[abcd b]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[abcd"
                    softbreak
                    text "b]: /u"
              paragraph
                text "[abcd b]"

            """),
        // MARK: full reference
        ("[abcd b]: /u\n\n> [t][abcd\nb]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "t"

            """),
        ("[abcde b]: /u\n\n> [t][abcde\nb]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              block_quote
                paragraph
                  text "[t][abcde"
                  softbreak
                  text "b]"

            """),
        ("[a b]: /u\n\n> [t][a\n   b]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "t"

            """),
        ("[ab b]: /u\n\n> [t][ab\n   b]", [], """
            document
              block_quote
                paragraph
                  text "[t][ab"
                  softbreak
                  text "b]"

            """),
        ("[abc b]: /u\n\n> [t][abc\n\tb]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "t"

            """),
        ("[abcd b]: /u\n\n> [t][abcd\n\tb]", [], """
            document
              block_quote
                paragraph
                  text "[t][abcd"
                  softbreak
                  text "b]"

            """),
        ("[abcd b]: /u\n\n> > [t][abcd\n>b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "t"

            """),
        ("[abcde b]: /u\n\n> > [t][abcde\n>b]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              block_quote
                block_quote
                  paragraph
                    text "[t][abcde"
                    softbreak
                    text "b]"

            """),
        ("[a b]: /u\n\n> > [t][a\n>    b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "t"

            """),
        ("[ab b]: /u\n\n> > [t][ab\n>    b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[t][ab"
                    softbreak
                    text "b]"

            """),
        ("[ab b]: /u\n\n> > [t][ab\n>\tb]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "t"

            """),
        ("[abc b]: /u\n\n> > [t][abc\n>\tb]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[t][abc"
                    softbreak
                    text "b]"

            """),
        ("[abcd b]: /u\n\n100. [t][abcd\nb]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "t"

            """),
        ("[abcde b]: /u\n\n100. [t][abcde\nb]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[t][abcde"
                    softbreak
                    text "b]"

            """),
        ("[a b]: /u\n\n100. [t][a\n   b]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "t"

            """),
        ("[ab b]: /u\n\n100. [t][ab\n   b]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[t][ab"
                    softbreak
                    text "b]"

            """),
        ("[abc b]: /u\n\n100. [t][abc\n\tb]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "t"

            """),
        ("[abcd b]: /u\n\n100. [t][abcd\n\tb]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[t][abcd"
                    softbreak
                    text "b]"

            """),
        // MARK: collapsed reference
        ("[abcd b]: /u\n\n> [abcd\nb][]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "abcd"
                    softbreak
                    text "b"

            """),
        ("[abcde b]: /u\n\n> [abcde\nb][]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              block_quote
                paragraph
                  text "[abcde"
                  softbreak
                  text "b][]"

            """),
        ("[a b]: /u\n\n> [a\n   b][]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "a"
                    softbreak
                    text "b"

            """),
        ("[ab b]: /u\n\n> [ab\n   b][]", [], """
            document
              block_quote
                paragraph
                  text "[ab"
                  softbreak
                  text "b][]"

            """),
        ("[abc b]: /u\n\n> [abc\n\tb][]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "abc"
                    softbreak
                    text "b"

            """),
        ("[abcd b]: /u\n\n> [abcd\n\tb][]", [], """
            document
              block_quote
                paragraph
                  text "[abcd"
                  softbreak
                  text "b][]"

            """),
        ("[abcd b]: /u\n\n> > [abcd\n>b][]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "abcd"
                      softbreak
                      text "b"

            """),
        ("[abcde b]: /u\n\n> > [abcde\n>b][]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              block_quote
                block_quote
                  paragraph
                    text "[abcde"
                    softbreak
                    text "b][]"

            """),
        ("[a b]: /u\n\n> > [a\n>    b][]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "a"
                      softbreak
                      text "b"

            """),
        ("[ab b]: /u\n\n> > [ab\n>    b][]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[ab"
                    softbreak
                    text "b][]"

            """),
        ("[ab b]: /u\n\n> > [ab\n>\tb][]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "ab"
                      softbreak
                      text "b"

            """),
        ("[abc b]: /u\n\n> > [abc\n>\tb][]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[abc"
                    softbreak
                    text "b][]"

            """),
        ("[abcd b]: /u\n\n100. [abcd\nb][]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "abcd"
                      softbreak
                      text "b"

            """),
        ("[abcde b]: /u\n\n100. [abcde\nb][]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[abcde"
                    softbreak
                    text "b][]"

            """),
        ("[a b]: /u\n\n100. [a\n   b][]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "a"
                      softbreak
                      text "b"

            """),
        ("[ab b]: /u\n\n100. [ab\n   b][]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[ab"
                    softbreak
                    text "b][]"

            """),
        ("[abc b]: /u\n\n100. [abc\n\tb][]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "abc"
                      softbreak
                      text "b"

            """),
        ("[abcd b]: /u\n\n100. [abcd\n\tb][]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[abcd"
                    softbreak
                    text "b][]"

            """),
        // MARK: shortcut reference
        ("[abcd b]: /u\n\n> [abcd\nb]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "abcd"
                    softbreak
                    text "b"

            """),
        ("[abcde b]: /u\n\n> [abcde\nb]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              block_quote
                paragraph
                  text "[abcde"
                  softbreak
                  text "b]"

            """),
        ("[a b]: /u\n\n> [a\n   b]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "a"
                    softbreak
                    text "b"

            """),
        ("[ab b]: /u\n\n> [ab\n   b]", [], """
            document
              block_quote
                paragraph
                  text "[ab"
                  softbreak
                  text "b]"

            """),
        ("[abc b]: /u\n\n> [abc\n\tb]", [], """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "abc"
                    softbreak
                    text "b"

            """),
        ("[abcd b]: /u\n\n> [abcd\n\tb]", [], """
            document
              block_quote
                paragraph
                  text "[abcd"
                  softbreak
                  text "b]"

            """),
        ("[abcd b]: /u\n\n> > [abcd\n>b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "abcd"
                      softbreak
                      text "b"

            """),
        ("[abcde b]: /u\n\n> > [abcde\n>b]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              block_quote
                block_quote
                  paragraph
                    text "[abcde"
                    softbreak
                    text "b]"

            """),
        ("[a b]: /u\n\n> > [a\n>    b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "a"
                      softbreak
                      text "b"

            """),
        ("[ab b]: /u\n\n> > [ab\n>    b]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[ab"
                    softbreak
                    text "b]"

            """),
        ("[ab b]: /u\n\n> > [ab\n>\tb]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "ab"
                      softbreak
                      text "b"

            """),
        ("[abc b]: /u\n\n> > [abc\n>\tb]", [], """
            document
              block_quote
                block_quote
                  paragraph
                    text "[abc"
                    softbreak
                    text "b]"

            """),
        ("[abcd b]: /u\n\n100. [abcd\nb]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "abcd"
                      softbreak
                      text "b"

            """),
        ("[abcde b]: /u\n\n100. [abcde\nb]", [], """
            document
              paragraph
                text "[abcde b]: /u"
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[abcde"
                    softbreak
                    text "b]"

            """),
        ("[a b]: /u\n\n100. [a\n   b]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "a"
                      softbreak
                      text "b"

            """),
        ("[ab b]: /u\n\n100. [ab\n   b]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[ab"
                    softbreak
                    text "b]"

            """),
        ("[abc b]: /u\n\n100. [abc\n\tb]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    link "/u" ""
                      text "abc"
                      softbreak
                      text "b"

            """),
        ("[abcd b]: /u\n\n100. [abcd\n\tb]", [], """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "[abcd"
                    softbreak
                    text "b]"

            """),
        // MARK: attribute definition
        ("> ^[abcd\nb]: k: 1\n\n^[t][abcd b]", .attributes, """
            document
              block_quote
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("> ^[abcde\nb]: k: 1\n\n^[t][abcde b]", .attributes, """
            document
              block_quote
                paragraph
                  text "^[abcde"
                  softbreak
                  text "b]: k: 1"
              paragraph
                text "^[t][abcde b]"

            """),
        ("> ^[a\n   b]: k: 1\n\n^[t][a b]", .attributes, """
            document
              block_quote
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("> ^[ab\n   b]: k: 1\n\n^[t][ab b]", .attributes, """
            document
              block_quote
                paragraph
                  text "^[ab"
                  softbreak
                  text "b]: k: 1"
              paragraph
                text "^[t]"

            """),
        ("> ^[abc\n\tb]: k: 1\n\n^[t][abc b]", .attributes, """
            document
              block_quote
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("> ^[abcd\n\tb]: k: 1\n\n^[t][abcd b]", .attributes, """
            document
              block_quote
                paragraph
                  text "^[abcd"
                  softbreak
                  text "b]: k: 1"
              paragraph
                text "^[t]"

            """),
        ("> > ^[abcd\n>b]: k: 1\n\n^[t][abcd b]", .attributes, """
            document
              block_quote
                block_quote
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("> > ^[abcde\n>b]: k: 1\n\n^[t][abcde b]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "^[abcde"
                    softbreak
                    text "b]: k: 1"
              paragraph
                text "^[t][abcde b]"

            """),
        ("> > ^[a\n>    b]: k: 1\n\n^[t][a b]", .attributes, """
            document
              block_quote
                block_quote
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("> > ^[ab\n>    b]: k: 1\n\n^[t][ab b]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "^[ab"
                    softbreak
                    text "b]: k: 1"
              paragraph
                text "^[t]"

            """),
        ("> > ^[ab\n>\tb]: k: 1\n\n^[t][ab b]", .attributes, """
            document
              block_quote
                block_quote
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("> > ^[abc\n>\tb]: k: 1\n\n^[t][abc b]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "^[abc"
                    softbreak
                    text "b]: k: 1"
              paragraph
                text "^[t]"

            """),
        ("100. ^[abcd\nb]: k: 1\n\n^[t][abcd b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("100. ^[abcde\nb]: k: 1\n\n^[t][abcde b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "^[abcde"
                    softbreak
                    text "b]: k: 1"
              paragraph
                text "^[t][abcde b]"

            """),
        ("100. ^[a\n   b]: k: 1\n\n^[t][a b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("100. ^[ab\n   b]: k: 1\n\n^[t][ab b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "^[ab"
                    softbreak
                    text "b]: k: 1"
              paragraph
                text "^[t]"

            """),
        ("100. ^[abc\n\tb]: k: 1\n\n^[t][abc b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
              paragraph
                attribute "k: 1"
                  text "t"

            """),
        ("100. ^[abcd\n\tb]: k: 1\n\n^[t][abcd b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "^[abcd"
                    softbreak
                    text "b]: k: 1"
              paragraph
                text "^[t]"

            """),
        // MARK: attribute reference
        ("^[abcd b]: k: 1\n\n> ^[t][abcd\nb]", .attributes, """
            document
              block_quote
                paragraph
                  attribute "k: 1"
                    text "t"

            """),
        ("^[abcde b]: k: 1\n\n> ^[t][abcde\nb]", .attributes, """
            document
              paragraph
                text "^[abcde b]: k: 1"
              block_quote
                paragraph
                  text "^[t][abcde"
                  softbreak
                  text "b]"

            """),
        ("^[a b]: k: 1\n\n> ^[t][a\n   b]", .attributes, """
            document
              block_quote
                paragraph
                  attribute "k: 1"
                    text "t"

            """),
        ("^[ab b]: k: 1\n\n> ^[t][ab\n   b]", .attributes, """
            document
              block_quote
                paragraph
                  text "^[t][ab"
                  softbreak
                  text "b]"

            """),
        ("^[abc b]: k: 1\n\n> ^[t][abc\n\tb]", .attributes, """
            document
              block_quote
                paragraph
                  attribute "k: 1"
                    text "t"

            """),
        ("^[abcd b]: k: 1\n\n> ^[t][abcd\n\tb]", .attributes, """
            document
              block_quote
                paragraph
                  text "^[t][abcd"
                  softbreak
                  text "b]"

            """),
        ("^[abcd b]: k: 1\n\n> > ^[t][abcd\n>b]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    attribute "k: 1"
                      text "t"

            """),
        ("^[abcde b]: k: 1\n\n> > ^[t][abcde\n>b]", .attributes, """
            document
              paragraph
                text "^[abcde b]: k: 1"
              block_quote
                block_quote
                  paragraph
                    text "^[t][abcde"
                    softbreak
                    text "b]"

            """),
        ("^[a b]: k: 1\n\n> > ^[t][a\n>    b]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    attribute "k: 1"
                      text "t"

            """),
        ("^[ab b]: k: 1\n\n> > ^[t][ab\n>    b]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "^[t][ab"
                    softbreak
                    text "b]"

            """),
        ("^[ab b]: k: 1\n\n> > ^[t][ab\n>\tb]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    attribute "k: 1"
                      text "t"

            """),
        ("^[abc b]: k: 1\n\n> > ^[t][abc\n>\tb]", .attributes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "^[t][abc"
                    softbreak
                    text "b]"

            """),
        ("^[abcd b]: k: 1\n\n100. ^[t][abcd\nb]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    attribute "k: 1"
                      text "t"

            """),
        ("^[abcde b]: k: 1\n\n100. ^[t][abcde\nb]", .attributes, """
            document
              paragraph
                text "^[abcde b]: k: 1"
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "^[t][abcde"
                    softbreak
                    text "b]"

            """),
        ("^[a b]: k: 1\n\n100. ^[t][a\n   b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    attribute "k: 1"
                      text "t"

            """),
        ("^[ab b]: k: 1\n\n100. ^[t][ab\n   b]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "^[t][ab"
                    softbreak
                    text "b]"

            """),
        ("^[abc b]: k: 1\n\n100. ^[t][abc\n\tb]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    attribute "k: 1"
                      text "t"

            """),
        ("^[abcd b]: k: 1\n\n100. ^[t][abcd\n\tb]", .attributes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "^[t][abcd"
                    softbreak
                    text "b]"

            """),
        // MARK: footnote reference
        ("> x[^abcde\n]\n\n[^abcde]: n", .footnotes, """
            document
              block_quote
                paragraph
                  text "x"
                  footnote_reference "1"
              footnote_definition "abcde"
                paragraph
                  text "n"

            """),
        ("> x[^abcdef\n]\n\n[^abcdef]: n", .footnotes, """
            document
              block_quote
                paragraph
                  text "x[^abcdef"
                  softbreak
                  text "]"

            """),
        ("> x[^ab\n   ]\n\n[^ab]: n", .footnotes, """
            document
              block_quote
                paragraph
                  text "x"
                  footnote_reference "1"
              footnote_definition "ab"
                paragraph
                  text "n"

            """),
        ("> x[^abc\n   ]\n\n[^abc]: n", .footnotes, """
            document
              block_quote
                paragraph
                  text "x[^abc"
                  softbreak
                  text "]"

            """),
        ("> x[^abcd\n\t]\n\n[^abcd]: n", .footnotes, """
            document
              block_quote
                paragraph
                  text "x"
                  footnote_reference "1"
              footnote_definition "abcd"
                paragraph
                  text "n"

            """),
        ("> x[^abcde\n\t]\n\n[^abcde]: n", .footnotes, """
            document
              block_quote
                paragraph
                  text "x[^abcde"
                  softbreak
                  text "]"

            """),
        ("> > x[^abcde\n>]\n\n[^abcde]: n", .footnotes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "x"
                    footnote_reference "1"
              footnote_definition "abcde"
                paragraph
                  text "n"

            """),
        ("> > x[^abcdef\n>]\n\n[^abcdef]: n", .footnotes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "x[^abcdef"
                    softbreak
                    text "]"

            """),
        ("> > x[^ab\n>    ]\n\n[^ab]: n", .footnotes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "x"
                    footnote_reference "1"
              footnote_definition "ab"
                paragraph
                  text "n"

            """),
        ("> > x[^abc\n>    ]\n\n[^abc]: n", .footnotes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "x[^abc"
                    softbreak
                    text "]"

            """),
        ("> > x[^abc\n>\t]\n\n[^abc]: n", .footnotes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "x"
                    footnote_reference "1"
              footnote_definition "abc"
                paragraph
                  text "n"

            """),
        ("> > x[^abcd\n>\t]\n\n[^abcd]: n", .footnotes, """
            document
              block_quote
                block_quote
                  paragraph
                    text "x[^abcd"
                    softbreak
                    text "]"

            """),
        ("100. x[^abcde\n]\n\n[^abcde]: n", .footnotes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "x"
                    footnote_reference "1"
              footnote_definition "abcde"
                paragraph
                  text "n"

            """),
        ("100. x[^abcdef\n]\n\n[^abcdef]: n", .footnotes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "x[^abcdef"
                    softbreak
                    text "]"

            """),
        ("100. x[^ab\n   ]\n\n[^ab]: n", .footnotes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "x"
                    footnote_reference "1"
              footnote_definition "ab"
                paragraph
                  text "n"

            """),
        ("100. x[^abc\n   ]\n\n[^abc]: n", .footnotes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "x[^abc"
                    softbreak
                    text "]"

            """),
        ("100. x[^abcd\n\t]\n\n[^abcd]: n", .footnotes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "x"
                    footnote_reference "1"
              footnote_definition "abcd"
                paragraph
                  text "n"

            """),
        ("100. x[^abcde\n\t]\n\n[^abcde]: n", .footnotes, """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    text "x[^abcde"
                    softbreak
                    text "]"

            """),
    ]

    @Test(arguments: cases)
    func labelBytes(_ markdown: String, options: MarkdownDocument.ParseOptions, expected: String) {
        #expect(TreeDump.dump(markdown, options: options, limits: Self.limits) == expected)
    }

    @Test("a continuation line its block quote continues counts no leading whitespace")
    func matchedContinuationWhitespace() {
        #expect(TreeDump.dump("> [abcd\n>    b]: /u\n\n[abcd b]", options: [], limits: Self.limits) == """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "abcd b"

            """)
    }

    /// `a`, a line ending, a space, `b`, a line ending, a space and `c` are 7 bytes.
    @Test("each lazy continuation line's whitespace counts")
    func severalLazyLines() {
        var limits = Self.limits
        limits.maxLinkLabelBytes = 7
        #expect(TreeDump.dump("> [a\n b\n c]: /u\n\n[a b c]", options: [], limits: limits) == """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "a b c"

            """)
        #expect(TreeDump.dump("> [ab\n b\n c]: /u\n\n[ab b c]", options: [], limits: limits) == """
            document
              block_quote
                paragraph
                  text "[ab"
                  softbreak
                  text "b"
                  softbreak
                  text "c]: /u"
              paragraph
                text "[ab b c]"

            """)
    }

    /// The first block quote's lazy line keeps whitespace. In the second, `abcd`, a line ending and `b` are 6 bytes
    /// when the line its block quote continues adds none, and `abcde` makes 7.
    @Test("a continuation line its block quote continues adds no bytes in a document with a lazy line")
    func continuedLineAfterLazyLine() {
        #expect(TreeDump.dump("> a\n   b\n\n> [abcd\n> b]: /u\n\n[abcd b]", options: [], limits: Self.limits) == """
            document
              block_quote
                paragraph
                  text "a"
                  softbreak
                  text "b"
              block_quote
              paragraph
                link "/u" ""
                  text "abcd b"

            """)
        #expect(TreeDump.dump("> a\n   b\n\n> [abcde\n> b]: /u\n\n[abcde b]", options: [], limits: Self.limits) == """
            document
              block_quote
                paragraph
                  text "a"
                  softbreak
                  text "b"
              block_quote
                paragraph
                  text "[abcde"
                  softbreak
                  text "b]: /u"
              paragraph
                text "[abcde b]"

            """)
    }

    @Test("a lazy continuation line's whitespace counts in a setext heading's label")
    func setextHeading() {
        #expect(TreeDump.dump("[a b]: /u\n[ab b]: /u\n\n> [a\n   b] [ab\n   b]\n> ===", options: [], limits: Self.limits) == """
            document
              block_quote
                heading 1
                  link "/u" ""
                    text "a"
                    softbreak
                    text "b"
                  text " [ab"
                  softbreak
                  text "b]"

            """)
    }

    /// A NUL, which is replaced with U+FFFD (Insecure characters), leaves unchanged the bytes its paragraph's lazy
    /// continuation lines count in a label, with and without source positions.
    @Test("a lazy continuation line's whitespace counts in a paragraph holding a NUL", arguments: [[], MarkdownDocument.ParseOptions.sourcePosition])
    func paragraphHoldingNUL(_ options: MarkdownDocument.ParseOptions) {
        #expect(TreeDump.dump("[a b]: /u\n[ab b]: /u\n\n> \0 [a\n   b] [ab\n   b] [t][a\n   b] [t][ab\n   b]", options: options, limits: Self.limits) == """
            document
              block_quote
                paragraph
                  text "\u{FFFD} "
                  link "/u" ""
                    text "a"
                    softbreak
                    text "b"
                  text " [ab"
                  softbreak
                  text "b] "
                  link "/u" ""
                    text "t"
                  text " [t][ab"
                  softbreak
                  text "b]"

            """)
    }

    @Test("the default limits admit the labels the tests above refuse")
    func defaultsAdmitOverLimitLabels() {
        #expect(TreeDump.dump("> [abcde\n   b]: /u\n\n[abcde b]", options: []) == """
            document
              block_quote
              paragraph
                link "/u" ""
                  text "abcde b"

            """)
        #expect(TreeDump.dump("[abc b]: /u\n\n> > [abc\n>\tb] [t][abc\n>\tb]", options: []) == """
            document
              block_quote
                block_quote
                  paragraph
                    link "/u" ""
                      text "abc"
                      softbreak
                      text "b"
                    text " "
                    link "/u" ""
                      text "t"

            """)
        #expect(TreeDump.dump("^[ab b]: k: 1\n\n100. ^[t][ab\n   b]", options: .attributes) == """
            document
              list ordered start=100 delim=period tight
                item
                  paragraph
                    attribute "k: 1"
                      text "t"

            """)
        #expect(TreeDump.dump("> x[^abcdef\n   ]\n\n[^abcdef]: n", options: .footnotes) == """
            document
              block_quote
                paragraph
                  text "x"
                  footnote_reference "1"
              footnote_definition "abcdef"
                paragraph
                  text "n"

            """)
    }
}
