/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Parenthesis nesting limits")
struct ParenthesisNestingLimitTests {

    private func limits(destination: Int = .max, attribute: Int = .max) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxLinkDestinationParenthesisNesting = destination
        limits.maxAttributeParenthesisNesting = attribute
        return limits
    }

    @Test("an inline link's destination fits at the nesting limit but not past it")
    func inlineLink() {
        let limits = limits(destination: 2)
        #expect(TreeDump.dump("[a](b((c)))", options: [], limits: limits) == """
            document
              paragraph
                link "b((c))" ""
                  text "a"

            """)
        #expect(TreeDump.dump("[a](b(((c))))", options: [], limits: limits) == """
            document
              paragraph
                text "[a](b(((c))))"

            """)
    }

    @Test("an image's destination fits at the nesting limit but not past it")
    func image() {
        let limits = limits(destination: 2)
        #expect(TreeDump.dump("![a](((c)))", options: [], limits: limits) == """
            document
              paragraph
                image "((c))" ""
                  text "a"

            """)
        #expect(TreeDump.dump("![a]((((c))))", options: [], limits: limits) == """
            document
              paragraph
                text "![a]((((c))))"

            """)
    }

    @Test("a link reference definition's destination fits at the nesting limit but not past it")
    func referenceDefinition() {
        let limits = limits(destination: 2)
        #expect(TreeDump.dump("[a]: b((c))\n\n[a]", options: [], limits: limits) == """
            document
              paragraph
                link "b((c))" ""
                  text "a"

            """)
        #expect(TreeDump.dump("[a]: b(((c)))\n\n[a]", options: [], limits: limits) == """
            document
              paragraph
                text "[a]: b(((c)))"
              paragraph
                text "[a]"

            """)
    }

    @Test("pairs side by side nest no deeper than one of them")
    func adjacentPairs() {
        #expect(TreeDump.dump("[a](b(c)(d)(e))", options: [], limits: limits(destination: 1)) == """
            document
              paragraph
                link "b(c)(d)(e)" ""
                  text "a"

            """)
    }

    @Test("escaped parentheses do not nest")
    func escapedParentheses() {
        #expect(TreeDump.dump("[a](b\\(\\((c)\\)\\))", options: [], limits: limits(destination: 1)) == """
            document
              paragraph
                link "b(((c)))" ""
                  text "a"

            """)
    }

    @Test("a destination starting inside an earlier destination's parentheses counts its own nesting")
    func destinationInsideEarlierDestination() {
        #expect(TreeDump.dump("[a](x[b](((c))))", options: [], limits: limits(destination: 2)) == """
            document
              paragraph
                text "[a](x"
                link "((c))" ""
                  text "b"
                text ")"

            """)
        #expect(TreeDump.dump("[a](x[b](((c))))", options: [], limits: limits(destination: 1)) == """
            document
              paragraph
                text "[a](x[b](((c))))"

            """)
    }

    @Test("a destination starting inside an earlier unbalanced destination's parentheses counts its own nesting")
    func destinationInsideEarlierUnbalancedDestination() {
        #expect(TreeDump.dump("[a](b[c](((d)) )", options: [], limits: limits(destination: 2)) == """
            document
              paragraph
                text "[a](b"
                link "((d))" ""
                  text "c"

            """)
        #expect(TreeDump.dump("[a](b[c](((d)) )", options: [], limits: limits(destination: 1)) == """
            document
              paragraph
                text "[a](b[c](((d)) )"

            """)
    }

    @Test("a nesting limit of 0 admits a destination without parentheses, as does a negative one")
    func zeroAndNegativeLimits() {
        for limit in [0, -5] {
            #expect(TreeDump.dump("[a](b) [c](d(e))", options: [], limits: limits(destination: limit)) == """
                document
                  paragraph
                    link "b" ""
                      text "a"
                    text " [c](d(e))"

                """)
        }
    }

    @Test("an attribute form's parentheses fit at the nesting limit but not past it")
    func attribute() {
        let limits = limits(attribute: 2)
        #expect(TreeDump.dump("^[a](k: ((v)))", options: .attributes, limits: limits) == """
            document
              paragraph
                attribute "k: ((v))"
                  text "a"

            """)
        #expect(TreeDump.dump("^[a](k: (((v))))", options: .attributes, limits: limits) == """
            document
              paragraph
                text "^[a](k: (((v))))"

            """)
    }

    @Test("parentheses inside quotes nest, and escaped ones do not")
    func attributeQuotedAndEscapedParentheses() {
        let limits = limits(attribute: 1)
        #expect(TreeDump.dump("^[a](k: \"((v))\")", options: .attributes, limits: limits) == """
            document
              paragraph
                text "^[a](k: \\"((v))\\")"

            """)
        #expect(TreeDump.dump("^[a](k: \\(\\((v)\\)\\))", options: .attributes, limits: limits) == """
            document
              paragraph
                attribute "k: \\\\(\\\\((v)\\\\)\\\\)"
                  text "a"

            """)
    }

    @Test("an attribute nesting limit of 0 admits attributes without parentheses, as does a negative one")
    func attributeZeroAndNegativeLimits() {
        for limit in [0, -5] {
            #expect(TreeDump.dump("^[a](k) ^[b](k(v))", options: .attributes, limits: limits(attribute: limit)) == """
                document
                  paragraph
                    attribute "k"
                      text "a"
                    text " ^[b](k(v))"

                """)
        }
    }

    @Test("each limit bounds only its own form")
    func limitsAreIndependent() {
        let source = "[a](((c))) ^[b](((v)))"
        #expect(TreeDump.dump(source, options: .attributes, limits: limits(destination: 1)) == """
            document
              paragraph
                text "[a](((c))) "
                attribute "((v))"
                  text "b"

            """)
        #expect(TreeDump.dump(source, options: .attributes, limits: limits(attribute: 1)) == """
            document
              paragraph
                link "((c))" ""
                  text "a"
                text " ^[b](((v)))"

            """)
    }

    @Test("the default limits admit the inputs past the limits above")
    func defaultsAdmitDeeperNesting() {
        #expect(TreeDump.dump("[a](b(((c)))) [d]\n\n[d]: e(((f)))", options: .attributes) == """
            document
              paragraph
                link "b(((c)))" ""
                  text "a"
                text " "
                link "e(((f)))" ""
                  text "d"

            """)
        #expect(TreeDump.dump("^[a](k: (((v)))) ^[b](k: \"((v))\")", options: .attributes) == """
            document
              paragraph
                attribute "k: (((v)))"
                  text "a"
                text " "
                attribute "k: \\"((v))\\""
                  text "b"

            """)
        #expect(TreeDump.dump("[a](x[b](((c))))", options: []) == """
            document
              paragraph
                link "x[b](((c)))" ""
                  text "a"

            """)
    }
}
