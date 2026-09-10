//
//  AppErrorMessage.swift
//  FireflyFM
//

import Foundation

enum AppErrorMessage {
    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }

        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }

        let nsError = error as NSError
        if nsError.domain.caseInsensitiveCompare("Swift.CancellationError") == .orderedSame {
            return true
        }
        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
            return true
        }

        let combined = "\(error) \(error.localizedDescription)".lowercased()
        return combined.contains("cancellationerror")
            || combined.contains("cancellation error")
            || combined.contains("cancelled")
            || combined.contains("canceled")
    }

    static func auth(_ error: Error) -> String {
        if let authError = error as? AuthFlowError {
            return authError.localizedDescription
        }

        let raw = error.localizedDescription
        let lower = raw.lowercased()

        if lower.contains("email not confirmed")
            || lower.contains("email_not_confirmed")
            || lower.contains("not confirmed")
            || lower.contains("confirm your email") {
            return "Your email has not been authenticated yet. Please open the verification email from FireflyFM, confirm your email address, and then sign in again."
        }

        if lower.contains("invalid login credentials") {
            return "The email or password is incorrect. Check both fields and try again."
        }

        if lower.contains("already registered") || lower.contains("user already") {
            return "An account already exists for this email. Please sign in instead."
        }

        if lower.contains("password") && (lower.contains("weak") || lower.contains("short") || lower.contains("characters")) {
            return "The password does not meet the required strength. Use a longer password with a mix of characters."
        }

        return "Authentication failed: \(raw)"
    }

    static func school(_ action: String, _ error: Error) -> String {
        if let uploadError = error as? UploadValidationError {
            return "\(action): \(uploadError.localizedDescription)"
        }

        if let workflowError = error as? SchoolWorkflowError {
            return "\(action): \(workflowError.localizedDescription)"
        }

        if let serviceError = error as? SchoolServiceError {
            switch serviceError {
            case .invalidEmail:
                return "\(action): enter a valid email address."
            case .invalidSchoolName:
                return "\(action): enter a school name."
            case .invalidCode:
                return "\(action): the code is invalid, expired, or already used."
            case .notFound:
                return "\(action): the requested school or invitation could not be found."
            }
        }

        let raw = error.localizedDescription
        let lower = raw.lowercased()

        if lower.contains("already pending")
            || lower.contains("pending invite")
            || lower.contains("idx_role_invites_one_pending") {
            return "\(action): an invitation for this person is already pending. You can resend or revoke the existing invitation instead."
        }

        if lower.contains("already a member")
            || lower.contains("already has access")
            || lower.contains("already an active") {
            return "\(action): this person already has access to the school."
        }

        if lower.contains("invite was issued to") || lower.contains("email does not match") {
            return "\(action): this invitation belongs to a different email address. Sign in with the invited address and try again."
        }

        if lower.contains("row-level security") || lower.contains("permission denied") || lower.contains("not authorized") {
            return "\(action): your account does not have permission for this school or item."
        }

        if lower.contains("schema cache") || lower.contains("could not find the function") {
            return "\(action): the Supabase schema is not up to date. Rerun the latest schema SQL and reload the schema cache."
        }

        if lower.contains("invalid or expired") || lower.contains("invalid code") {
            return "\(action): the code is invalid, expired, or already used."
        }

        if lower.contains("file too large") || lower.contains("maximum file size") || lower.contains("payload too large") {
            return "\(action): the selected file is too large. FireflyFM currently accepts files up to \(UploadPolicy.maxFileSizeDescription)."
        }

        if lower.contains("storage") || lower.contains("object") || lower.contains("bucket") {
            return "\(action): the file could not be saved to secure storage. Check that the private storage bucket and policies were created."
        }

        if lower.contains("network") || lower.contains("timed out") || lower.contains("offline") {
            return "\(action): the network request failed. Check your connection and try again."
        }

        return "\(action): \(raw)"
    }
}

enum AuthFlowError: LocalizedError {
    case emailConfirmationRequired(String)

    var errorDescription: String? {
        switch self {
        case .emailConfirmationRequired(let email):
            return "Your email has not been authenticated yet. We sent a verification email to \(email). Please confirm your email address, then sign in."
        }
    }
}
