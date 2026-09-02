//
//  SensitiveDataDetector.swift
//  clippy
//
//  Best-effort heuristics for flagging clipboard content that probably
//  shouldn't be written to disk in plaintext. This is intentionally
//  conservative-leaning: it will miss things, and it will occasionally
//  flag content that isn't actually sensitive. Neither is fatal here since
//  flagged items are simply not stored/previewed in plaintext.
//

import Foundation

struct SensitiveDataDetector {
    /// Bundle identifiers of well-known password managers. Copies that
    /// originate from these apps are treated as sensitive regardless of
    /// their shape.
    static let passwordManagerBundleIDs: Set<String> = [
        "com.agilebits.onepassword7", "com.1password.1password",
        "com.bitwarden.desktop", "com.lastpass.lastpassmacdesktop",
        "in.sinew.Enpass", "com.dashlane.dashlanephonefinal",
        "com.apple.Passwords",
    ]

    private static let jwtRegex = try! NSRegularExpression(
        pattern: #"^[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}$"#)
    private static let bearerRegex = try! NSRegularExpression(
        pattern: #"(?i)\bbearer\s+[A-Za-z0-9._~+/-]{15,}"#)
    private static let privateKeyRegex = try! NSRegularExpression(
        pattern: #"-----BEGIN [A-Z ]*PRIVATE KEY-----"#)
    private static let apiKeyRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(sk|pk|ghp|gho|ghu|ghs|xox[baprs]|AIza|AKIA)[A-Za-z0-9_-]{10,}\b"#)
    private static let genericSecretAssignmentRegex = try! NSRegularExpression(
        pattern: #"(?i)\b(api[_-]?key|secret|token|password|passwd|pwd)\b\s*[:=]\s*['"]?[A-Za-z0-9._~+/-]{6,}"#)
    private static let sixDigitOTPRegex = try! NSRegularExpression(pattern: #"^\s*\d{6}\s*$"#)

    /// Returns true when `content` matches a known sensitive pattern, or
    /// when it was copied from a recognized password manager.
    static func isSensitive(_ content: ClipboardContent, ignorePasswordManagers: Bool, detectOTP: Bool) -> Bool {
        if ignorePasswordManagers, let bundleID = content.sourceAppBundleID,
           passwordManagerBundleIDs.contains(bundleID) {
            return true
        }

        guard content.type == .text || content.type == .richText || content.type == .url else { return false }
        guard let text = content.plainText, !text.isEmpty else { return false }

        if detectOTP, matches(sixDigitOTPRegex, text) { return true }
        if matches(jwtRegex, text) { return true }
        if matches(bearerRegex, text) { return true }
        if matches(privateKeyRegex, text) { return true }
        if matches(apiKeyRegex, text) { return true }
        if matches(genericSecretAssignmentRegex, text) { return true }
        if isLikelyCreditCard(text) { return true }
        return false
    }

    private static func matches(_ regex: NSRegularExpression, _ text: String) -> Bool {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range) != nil
    }

    /// A copy consisting solely of 13-19 digits (optionally grouped) that
    /// passes the Luhn checksum is treated as a card number.
    private static func isLikelyCreditCard(_ text: String) -> Bool {
        let stripped = text.filter { $0.isNumber || $0 == " " || $0 == "-" }
        guard stripped.count == text.count else { return false }
        let digits = text.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return false }
        return luhnIsValid(digits)
    }

    private static func luhnIsValid(_ digits: String) -> Bool {
        var sum = 0
        var shouldDouble = false
        for character in digits.reversed() {
            guard let digit = character.wholeNumberValue else { return false }
            var value = digit
            if shouldDouble {
                value *= 2
                if value > 9 { value -= 9 }
            }
            sum += value
            shouldDouble.toggle()
        }
        return sum % 10 == 0
    }
}
