import PluckCore
import XCTest

final class AppleScriptEscapeTests: XCTestCase {
    func testPlainPathIsJustQuoted() {
        XCTAssertEqual(AppleScriptEscape.quoted("/Users/me/Notes.txt"), "\"/Users/me/Notes.txt\"")
    }

    func testQuotesAndBackslashesAreEscaped() {
        XCTAssertEqual(AppleScriptEscape.quoted("a\"b\\c"), "\"a\\\"b\\\\c\"")
    }

    func testInjectionAttemptStaysInsideTheLiteral() {
        let evil = "/tmp/x\" & (do shell script \"touch /tmp/pwned\") & \""
        let q = AppleScriptEscape.quoted(evil)
        // Every inner quote is escaped, so the only unescaped quotes are the outer pair.
        var unescaped = 0
        var prev: Character = " "
        for c in q {
            if c == "\"" && prev != "\\" { unescaped += 1 }
            prev = (c == "\\" && prev == "\\") ? " " : c
        }
        XCTAssertEqual(unescaped, 2)
    }

    func testControlCharactersAreNeutralised() {
        XCTAssertEqual(AppleScriptEscape.quoted("a\nb\u{0}c"), "\"a bc\"")
    }
}
