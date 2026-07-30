//
//  FireflyFMUITests.swift
//  FireflyFMUITests
//
//  Created by FireflyFM contributors on 6/8/26.
//

import XCTest

final class FireflyFMUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // XCUIAutomation Documentation
        // https://developer.apple.com/documentation/xcuiautomation
    }

    @MainActor
    func testFourTabRoleMatrix() throws {
        for role in ["parent", "teacher", "school_director", "hq_director"] {
            let app = XCUIApplication()
            app.launchArguments = ["--ui-test-role=\(role)"]
            app.launch()

            let tabBar = app.tabBars.firstMatch
            XCTAssertTrue(tabBar.waitForExistence(timeout: 8), "Missing tab bar for \(role)")
            for title in ["Today", "Messages", "Calendar", "Workspace"] {
                XCTAssertTrue(tabBar.buttons[title].exists, "Missing \(title) for \(role)")
            }

            app.terminate()
        }
    }

    @MainActor
    func testActivityInboxIsReachableForEveryRoleAtAccessibilityTextSize() throws {
        for role in ["parent", "teacher", "school_director", "hq_director"] {
            let app = XCUIApplication()
            app.launchArguments = [
                "--ui-test-role=\(role)",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
            ]
            app.launch()

            let activityButton = app.buttons["Activity"]
            XCTAssertTrue(activityButton.waitForExistence(timeout: 8), "Missing accessible Activity button for \(role)")
            activityButton.tap()

            XCTAssertTrue(app.staticTexts["Activity"].waitForExistence(timeout: 5), "Activity did not open for \(role)")
            XCTAssertTrue(app.segmentedControls.buttons["All"].exists, "Missing All filter for \(role)")
            XCTAssertTrue(app.segmentedControls.buttons["Unread"].exists, "Missing Unread filter for \(role)")
            XCTAssertTrue(app.buttons["Notification preferences"].exists, "Missing settings action for \(role)")

            app.terminate()
        }
    }

    @MainActor
    func testManageWorkMetricCardsUseEqualFramesWhenAvailable() throws {
        let app = XCUIApplication()
        app.launch()

        let metrics = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "assignment-manager-metric-")
        )
        guard metrics.count > 1 else {
            throw XCTSkip("Requires a signed-in assignment creator with Manage Work metrics visible.")
        }

        let reference = metrics.element(boundBy: 0).frame
        for index in 1..<metrics.count {
            let frame = metrics.element(boundBy: index).frame
            XCTAssertEqual(frame.width, reference.width, accuracy: 0.5)
            XCTAssertEqual(frame.height, reference.height, accuracy: 0.5)
        }
    }

    @MainActor
    func testAssignmentControlsStayInTheirRelationshipPanelsWhenAvailable() throws {
        let app = XCUIApplication()
        app.launch()

        let recipientPanel = app.descendants(matching: .any)["assignment-recipient-panel"]
        let creatorPanel = app.descendants(matching: .any)["assignment-creator-panel"]
        let acknowledgment = app.descendants(matching: .any)["assignment-recipient-acknowledgment"]
        let accept = app.descendants(matching: .any)["assignment-accept"]
        let requestChanges = app.descendants(matching: .any)["assignment-request-changes"]

        guard recipientPanel.exists || creatorPanel.exists else {
            throw XCTSkip("Requires launch into a seeded assignment detail scenario.")
        }

        if acknowledgment.exists {
            XCTAssertTrue(recipientPanel.exists)
        }
        if accept.exists || requestChanges.exists {
            XCTAssertTrue(creatorPanel.exists)
        }
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
