/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Markdown
import XCTest

/// Regression coverage for divergences found by the swift-markdown-difftest differential fuzzer.
///
/// Each case is a pair of files in `FuzzRegressions/`:
///   - `<name>.input`    — the raw fuzzer artifact bytes (`[markdown …][final byte = options]`).
///   - `<name>.expected` — the reference (cmark-gfm) comparison surface, minted losslessly with
///                         `dump --ref <artifact>`. This is the oracle; the rewrite must reproduce it.
///
/// The harness re-derives the fuzzer's comparison surface for the rewrite and asserts it equals the
/// stored reference surface. The split + surface logic mirrors `DiffSupport` (the fuzzer and `dump`
/// share it); MarkdownTests can't import that package, so the two-line equivalent is inlined here.
class FuzzRegressionTests: XCTestCase {

    /// Split a raw artifact exactly as `DiffSupport.splitInput`: the last byte selects parse options
    /// (masked to the five known bits), the rest is the UTF-8 document (invalid sequences → U+FFFD).
    private static func splitInput(_ bytes: [UInt8]) -> (markdown: String, options: ParseOptions)? {
        guard let optionBits = bytes.last else { return nil }
        let markdown = String(decoding: bytes.dropLast(), as: UTF8.self)
        return (markdown, ParseOptions(rawValue: UInt(optionBits & 0b11111)))
    }

    /// The rewrite's comparison surface, matching `DiffSupport.newSurface`.
    private static func surface(_ markdown: String, options: ParseOptions) -> String {
        Document(parsing: markdown, options: options).debugDescription(options: .printSourceLocations)
    }

    func testFuzzRegressions() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("FuzzRegressions")

        let inputs = try FileManager.default
            .contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "input" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        // Fixture sanity: a broken path or empty directory must fail loudly, not pass vacuously.
        XCTAssertFalse(inputs.isEmpty, "no fuzz regression pairs found in \(dir.path)")

        for inputURL in inputs {
            let name = inputURL.deletingPathExtension().lastPathComponent
            let expectedURL = inputURL.deletingPathExtension().appendingPathExtension("expected")

            let bytes = [UInt8](try Data(contentsOf: inputURL))
            let expected = try String(contentsOf: expectedURL, encoding: .utf8)

            guard let (markdown, options) = Self.splitInput(bytes) else {
                XCTFail("\(name): empty artifact")
                continue
            }

            let actual = Self.surface(markdown, options: options)
            XCTAssertEqual(actual, expected, "surface diverges from reference for \(name)")
        }
    }
}
