import Foundation
import Testing
@testable import FireflyFM

struct ChatVideoPreparationTests {
    @Test func policyKeepsUploadsShortAndWithinThePrivateFileLimit() {
        #expect(ChatVideoPreparation.maximumDuration == 120)
        #expect(
            ChatVideoPreparationError.tooLong(maximumSeconds: 120)
                .localizedDescription
                .contains("2 minutes")
        )
        #expect(
            ChatVideoPreparationError.couldNotFit(maximumSize: UploadPolicy.maxFileSizeDescription)
                .localizedDescription
                .contains(UploadPolicy.maxFileSizeDescription)
        )
    }
}
