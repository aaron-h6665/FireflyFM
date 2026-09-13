import Foundation

struct LegalAcceptance: Equatable {
    let termsVersion: String
    let privacyVersion: String
    let aiNoticeVersion: String
    let acceptedAt: Date

    static func current(at date: Date = Date()) -> LegalAcceptance {
        LegalAcceptance(
            termsVersion: LegalContent.termsVersion,
            privacyVersion: LegalContent.privacyVersion,
            aiNoticeVersion: LegalContent.aiNoticeVersion,
            acceptedAt: date
        )
    }
}

enum LegalDocumentKind: String, Identifiable {
    case terms
    case privacy
    case aiNotice

    var id: String { rawValue }
}

struct LegalSection: Identifiable {
    let title: String
    let body: String

    var id: String { title }
}

struct LegalDocument {
    let title: String
    let effectiveDate: String
    let introduction: String
    let sections: [LegalSection]
}

enum LegalContent {
    static let termsVersion = "2026-09-13-parallel-onboarding-v1"
    static let privacyVersion = "2026-09-13-parallel-onboarding-v1"
    static let aiNoticeVersion = "2026-08-03-local-v2"
    static let privacyContactEmail = "privacy@fireflyfm.app"

    static func document(_ kind: LegalDocumentKind) -> LegalDocument {
        switch kind {
        case .terms: terms
        case .privacy: privacy
        case .aiNotice: aiNotice
        }
    }

    static let terms = LegalDocument(
        title: "Terms of Service",
        effectiveDate: "Effective September 10, 2026",
        introduction: "These Terms govern your use of FireflyFM. By creating an account or continuing to use the app, you agree to these Terms and acknowledge the Privacy Policy. If you use FireflyFM for a school or other organization, you confirm that you are authorized to do so.",
        sections: [
            LegalSection(
                title: "Who may use FireflyFM",
                body: "FireflyFM is an adult-facing service for authorized parents, guardians, educators, school directors, and administrators. It is not intended for children to create or operate accounts. You must provide accurate information, protect your credentials, and promptly report suspected unauthorized access."
            ),
            LegalSection(
                title: "School and family responsibilities",
                body: "Schools control access to school records and are responsible for configuring memberships, permissions, retention, and legally required notices. Parents and guardians may access only children for whom access has been approved. You must have the necessary authority before uploading information about a child or another person."
            ),
            LegalSection(
                title: "Content and communications",
                body: "You retain rights in content you submit. You grant FireflyFM the limited rights needed to host, secure, process, display, and transmit that content to authorized users and service providers for operating the service. Do not submit unlawful, abusive, misleading, infringing, or unnecessarily sensitive content. School records and communications must be handled under applicable school policy and law."
            ),
            LegalSection(
                title: "Invoices and external Zelle transfers",
                body: "A school may use FireflyFM to issue an invoice and display its Zelle recipient instructions. FireflyFM does not initiate, receive, settle, or verify the transfer automatically. A payer completes any transfer separately through their bank or Zelle experience and submits only a short confirmation reference. Assigned onboarding items may be completed in any order while other items await review. School directors review parent and teacher onboarding submissions; FireflyFM HQ reviews school-director onboarding submissions. Rejected confirmation details can be corrected without sending another payment. A newly published plan applies to people still onboarding and future invitees; matching approved or waived work and submitted payment history are preserved, while new and unfinished requirements may change. Do not upload bank credentials, account or routing numbers, or payment screenshots. Demo receipts represent simulated transfers in an isolated test environment. Voiding an invoice does not refund a transfer or waive enrollment requirements; a waiver requires a separate authorized action and reason."
            ),
            LegalSection(
                title: "Google Forms connection",
                body: "An authorized school director may connect one or more Google accounts to select and synchronize existing onboarding Forms. FireflyFM requests the Google permissions described in the Privacy Policy and keeps refresh credentials encrypted on its backend. The director can switch the account used for new Forms without changing existing Form connections. Disconnect Google revokes FireflyFM’s authorization, deletes the saved credential, and pauses Forms linked to that account. It does not delete Forms in Google or previously imported FireflyFM records, which remain subject to the school’s retention obligations."
            ),
            LegalSection(
                title: "On-device AI summaries",
                body: "FireflyFM may offer optional on-device summaries to authorized directors. Local Summary uses Apple’s Natural Language framework and deterministic record aggregation without requiring Apple Intelligence. On supported devices, a director may instead choose Apple’s on-device Foundation Model. Neither engine sends source material to a cloud AI provider, and attachment contents are not analyzed. Every output can be incomplete or omit context, must be reviewed by a qualified adult, and must not be the sole basis for medical, safety, disciplinary, educational, eligibility, or legal decisions. See the On-Device AI Notice for details."
            ),
            LegalSection(
                title: "Acceptable use",
                body: "You may not bypass access controls, scrape or reverse engineer the service except where law permits, introduce malware, interfere with other users, use the service to profile or discriminate unlawfully, or rely on AI output to make automated high-impact decisions about a child."
            ),
            LegalSection(
                title: "Availability and changes",
                body: "Features may change, be suspended, or become unavailable. Local Summary depends on Apple’s built-in language resources. The optional generative engine additionally depends on compatible hardware, software, language, and Apple Intelligence settings. We may update these Terms and will present material changes for review when required."
            ),
            LegalSection(
                title: "No professional advice",
                body: "FireflyFM and its AI output do not provide medical, legal, educational, or emergency advice. Contact qualified professionals and emergency services when appropriate."
            ),
            LegalSection(
                title: "Suspension and termination",
                body: "Access may be limited or terminated for security, legal, contractual, or policy reasons. A school may also remove a membership. Sections that by their nature should survive termination, including content licenses already needed for lawful retention, disclaimers, and limitations, will survive."
            ),
            LegalSection(
                title: "Disclaimers and responsibility",
                body: "To the extent permitted by law, the service is provided without guarantees that it will be uninterrupted or error-free. Nothing in these Terms excludes rights or liability that cannot legally be excluded. Any organization-specific commercial terms control if they conflict with these consumer-facing Terms."
            ),
            LegalSection(
                title: "Apple",
                body: "Apple is not responsible for providing or supporting FireflyFM. Your use of the iOS app is also subject to the applicable App Store terms."
            ),
            LegalSection(
                title: "Contact",
                body: "Questions about these Terms may be sent to \(privacyContactEmail) or raised through your school administrator."
            )
        ]
    )

    static let privacy = LegalDocument(
        title: "Privacy Policy",
        effectiveDate: "Effective September 10, 2026",
        introduction: "This Policy explains how FireflyFM handles personal information for its adult-facing school and family communication service. A school may act as the organization responsible for child and school records, while FireflyFM processes information to provide the service.",
        sections: [
            LegalSection(
                title: "Information we handle",
                body: "We may handle account and profile details; school memberships and roles; child identity and guardian relationships; attendance, care, medication, health, developmental, goal, assignment, and onboarding records; invoices, line items, payment status, receipts, and payer-supplied short confirmation references; messages and activity cards; photos, videos, audio, files, and attachment metadata; notification preferences and device tokens; and security, diagnostic, and audit information."
            ),
            LegalSection(
                title: "How information is collected",
                body: "Information comes from account holders, authorized school staff, approved guardians, school-configured workflows, and technical operation of the service. We do not intend to collect information directly from children through child-operated accounts."
            ),
            LegalSection(
                title: "How information is used",
                body: "We use information to authenticate users, provide role-based school and family features, deliver communications and notifications, maintain records, secure and troubleshoot the service, comply with law, and provide optional features such as on-device summaries. We do not use child information for targeted advertising."
            ),
            LegalSection(
                title: "On-device AI processing",
                body: "When an authorized director taps Generate, the current prototype prepares eligible child-related text and record metadata on that director’s device. By default, Local Summary uses Apple’s Natural Language framework to extract recurring terms and combines them with deterministic counts and source excerpts. If Apple Intelligence is available, the director may optionally choose Apple’s on-device Foundation Model for a generative draft. FireflyFM does not send source material or results to its servers or to a cloud AI provider, and the result is not saved by the app. The prototype does not inspect image, video, audio, or file contents; it may include attachment type, name, size, or duration. If FireflyFM later uses a cloud or third-party AI provider, we will update this notice and obtain any required permission before sending personal information."
            ),
            LegalSection(
                title: "When information is shared",
                body: "Information is shared with users authorized by the relevant school and child relationship. It may also be processed by infrastructure providers needed to operate FireflyFM, such as hosted database, storage, authentication, and Apple notification services; by professional advisers under confidentiality; or when required for safety, security, or law. We do not sell personal information."
            ),
            LegalSection(
                title: "Manual Zelle payment workflow",
                body: "FireflyFM displays the school’s Zelle instructions and records the invoice, the payer’s short confirmation reference, and the authorized reviewer’s decision. School directors review parent and teacher onboarding submissions; FireflyFM HQ reviews school-director onboarding submissions. The transfer itself occurs outside FireflyFM in the payer’s bank or Zelle experience. FireflyFM does not collect bank logins, account or routing numbers, card numbers, Zelle credentials, or payment screenshots. A newly published onboarding plan applies to people still onboarding and future invitees. Stable requirement identifiers preserve matching approved or waived work; removed steps and prior invoice or assignment links remain in restricted audit history. Invoice recipient snapshots, correction history, replacement links, waiver reasons, and review audit events are retained. A receipt records reviewer confirmation, not independent Zelle verification. The isolated local Simulator demo uses synthetic accounts and a simulated bank ledger; demo receipts are labeled DEMO — no money moved and affect only test memberships. Teachers see family enrollment readiness without parent payment details; a teacher assigned their own onboarding invoice can view and respond to that invoice."
            ),
            LegalSection(
                title: "Google Forms and connected accounts",
                body: "A school director may connect Google accounts used for onboarding Forms. FireflyFM receives the account email, Form structure and questions, configured Form responses, and eligible Drive-upload files under the permissions shown before connection. Refresh credentials are encrypted and remain backend-only. Directors can choose a different account for new Forms without moving existing Forms. Disconnecting revokes Google access, deletes the saved refresh credential, and pauses linked synchronization. Google Forms are not deleted. Responses and files already imported into FireflyFM remain school records governed by the school’s retention requirements."
            ),
            LegalSection(
                title: "Retention and deletion",
                body: "Account information is generally retained while an account or school relationship is active. School and child records are retained according to the school’s instructions, contractual requirements, and applicable law. Security records and backups may remain for a limited period after deletion. A verified deletion request may be limited when a school must retain a record, another person’s rights are involved, or law requires retention."
            ),
            LegalSection(
                title: "Your choices and rights",
                body: "Depending on location and your relationship with the school, you may request access, correction, export, restriction, objection, or deletion. Parents and guardians should usually begin with their school for child records. Account and privacy requests can also be sent to our privacy contact. You may disable notifications in device settings."
            ),
            LegalSection(
                title: "Security",
                body: "We use role-based access controls, authenticated requests, private storage, and other administrative and technical safeguards. No system can guarantee absolute security. Please report suspected misuse promptly and avoid placing unnecessary sensitive details in free-form messages."
            ),
            LegalSection(
                title: "Children’s information",
                body: "FireflyFM is designed for adults acting for families and schools. Schools and guardians are responsible for providing notices and obtaining permissions required in their jurisdiction. Child information must be used only for authorized care, education, administration, communication, and safety purposes."
            ),
            LegalSection(
                title: "International processing",
                body: "Service providers may process information in locations different from yours. Where required, appropriate contractual or legal safeguards should be used. Your school may provide additional location-specific information."
            ),
            LegalSection(
                title: "Policy changes and contact",
                body: "We may update this Policy as the service changes. Material changes will be presented when required. Contact \(privacyContactEmail) for privacy questions or requests, or contact the school responsible for the relevant child record."
            )
        ]
    )

    static let aiNotice = LegalDocument(
        title: "On-Device AI Notice",
        effectiveDate: "Version \(aiNoticeVersion)",
        introduction: "This notice describes the first FireflyFM AI summary prototype. It supplements the Terms of Service and Privacy Policy.",
        sections: [
            LegalSection(
                title: "What it does",
                body: "An authorized school director can ask FireflyFM to summarize recent child-related communications and records. The summary is intended to help a director review context before completing their own work. It is not an official child record unless a qualified user independently verifies and intentionally records it."
            ),
            LegalSection(
                title: "What may be included",
                body: "The source set may include message text with sender role and time, activity-card and care-event details, attendance status and notes, child goals, and attachment metadata such as type, name, size, or audio duration. The prototype limits the review period and the amount of text used by either engine."
            ),
            LegalSection(
                title: "What is not analyzed",
                body: "The prototype does not open, transcribe, classify, or interpret image, video, audio, or file contents. It does not use a cloud AI API."
            ),
            LegalSection(
                title: "Where processing happens",
                body: "Local Summary uses Apple’s Natural Language framework and deterministic Swift code on the director’s device. The optional generative engine uses Apple’s Foundation Models framework on a compatible device. FireflyFM does not upload the prepared source material or result, and it does not persist the result. Normal source records remain stored under the Privacy Policy."
            ),
            LegalSection(
                title: "Human review is required",
                body: "Either summary engine may omit facts or miss context, and the optional generative engine may also misstate facts or produce unexpected text. Compare every statement with the source records. Do not use a summary by itself for health, safety, medication, discipline, developmental assessment, eligibility, reporting, or other consequential decisions."
            ),
            LegalSection(
                title: "Availability and future changes",
                body: "Local Summary does not require Apple Intelligence and is available wherever the required built-in language resources are supported. The optional generative engine requires a supported device with Apple Intelligence available and enabled. Any future cloud AI, media analysis, saved summaries, broader access, or automated form filling will require a new product and privacy review, updated disclosures, and any legally required permission."
            )
        ]
    )
}
