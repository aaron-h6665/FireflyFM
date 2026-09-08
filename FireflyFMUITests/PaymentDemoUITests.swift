import XCTest

final class PaymentDemoUITests: XCTestCase {
    @MainActor
    func testAuthenticatedPaymentScreens() throws {
        let key = ProcessInfo.processInfo.environment["FIREFLY_DEMO_ANON_KEY"] ?? ""
        try XCTSkipIf(key.isEmpty, "Requires the isolated local payment demo")
        let app = XCUIApplication()
        app.launchEnvironment["FIREFLY_PAYMENT_DEMO"] = "1"
        app.launchEnvironment["FIREFLY_DEMO_ANON_KEY"] = key
        app.launch()
        XCTAssertTrue(app.buttons["Demo account"].waitForExistence(timeout: 15))
        for account in ["parent-a", "director-a"] {
            app.buttons["Demo account"].tap()
            app.buttons[account].tap()
            XCTAssertTrue(app.tabBars.buttons["Workspace"].waitForExistence(timeout: 20))
            app.tabBars.buttons["Workspace"].tap()
            let payments = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Payments'")).firstMatch
            for _ in 0..<5 where !payments.isHittable { app.swipeUp() }
            XCTAssertTrue(payments.waitForExistence(timeout: 10))
            payments.tap()
            let invoice = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Second semester tuition'")).firstMatch
            XCTAssertTrue(invoice.waitForExistence(timeout: 15))
            invoice.tap()
            XCTAssertTrue(app.staticTexts["DEMO — no money moved"].firstMatch.waitForExistence(timeout: 10))
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(account) demo invoice"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }
}
