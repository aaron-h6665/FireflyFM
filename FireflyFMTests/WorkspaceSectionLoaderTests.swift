import Foundation
import Testing
@testable import FireflyFM

@MainActor
struct WorkspaceSectionLoaderTests {
    private func scope(_ school: UUID = UUID()) -> WorkspaceLoadScope {
        WorkspaceLoadScope(userId: UUID(), membershipId: UUID(), schoolId: school)
    }

    @Test func activeContentSurvivesHistoryFailureAndTargetedRetry() async {
        let loader = WorkspaceSectionLoader<String, [Int]>()
        let identity = scope()
        await loader.load("active", scope: identity, failureMessage: "Active") { [1] }
        await loader.load("history", scope: identity, failureMessage: "History") { throw URLError(.timedOut) }
        #expect(loader.values["active"] == [1])
        #expect(loader.values["history"] == nil)
        #expect(loader.errors["history"] != nil)
        await loader.load("history", scope: identity, failureMessage: "History") { [] }
        #expect(loader.values["active"] == [1])
        #expect(loader.values["history"] == [])
        #expect(loader.errors["history"] == nil)
    }

    @Test func olderResponseCannotReplaceNewerRefresh() async {
        let loader = WorkspaceSectionLoader<String, [Int]>()
        let identity = scope()
        var resume: CheckedContinuation<[Int], Never>?
        let old = Task { await loader.load("invoices", scope: identity, failureMessage: "Invoices") {
            await withCheckedContinuation { resume = $0 }
        } }
        while resume == nil { await Task.yield() }
        await loader.load("invoices", scope: identity, failureMessage: "Invoices") { [2] }
        resume?.resume(returning: [1])
        await old.value
        #expect(loader.values["invoices"] == [2])
        #expect(loader.loading.isEmpty)
    }

    @Test func schoolSwitchClearsEverythingAndRejectsLateFailure() async {
        let loader = WorkspaceSectionLoader<String, [Int]>()
        let first = scope(), second = scope()
        await loader.load("active", scope: first, failureMessage: "Active") { [1] }
        var resume: CheckedContinuation<[Int], any Error>?
        let old = Task { await loader.load("labels", scope: first, failureMessage: "Labels") {
            try await withCheckedThrowingContinuation { resume = $0 }
        } }
        while resume == nil { await Task.yield() }
        loader.reset(to: second)
        #expect(loader.values.isEmpty)
        #expect(loader.loading.isEmpty)
        await loader.load("active", scope: second, failureMessage: "Active") { [2] }
        resume?.resume(throwing: URLError(.timedOut))
        await old.value
        #expect(loader.values["active"] == [2])
        #expect(loader.errors.isEmpty)
    }

    @Test func failedSameScopeRefreshRetainsContentButAccountSwitchClearsIt() async {
        let loader = WorkspaceSectionLoader<String, [Int]>()
        let first = scope()
        await loader.load("active", scope: first, failureMessage: "Active") { [1] }
        await loader.load("active", scope: first, failureMessage: "Active") { throw URLError(.notConnectedToInternet) }
        #expect(loader.values["active"] == [1])
        loader.reset(to: WorkspaceLoadScope(userId: UUID(), membershipId: first.membershipId, schoolId: first.schoolId))
        #expect(loader.values.isEmpty)
        #expect(loader.errors.isEmpty)
    }
}
