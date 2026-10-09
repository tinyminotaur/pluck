import Foundation

/// Safe interpolation of untrusted text (file names, paths) into AppleScript source.
///
/// A file called `x" & (do shell script "…") & "` must stay a string literal and never become code.
public enum AppleScriptEscape {
    /// Returns `s` as a double-quoted AppleScript string literal, escaping backslashes and quotes
    /// and dropping control characters (newlines would otherwise end the statement).
    public static func quoted(_ s: String) -> String {
        var out = "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\\": out += "\\\\"
            case "\"": out += "\\\""
            case "\n", "\r", "\t": out += " "
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F { continue }
                out.unicodeScalars.append(scalar)
            }
        }
        return out + "\""
    }
}
