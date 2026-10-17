import XCTest

final class NavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIDevice.shared.orientation = .portrait
    }

    func testSearchButtonDisabledWhenEmptyOrWhitespace() {
        let app = launch(orientation: .portrait)
        let search = element("searchButton", in: app)
        XCTAssertFalse(search.isEnabled)
        _ = element("micButton", in: app)
        _ = element("historyButton", in: app)

        let field = questionField(in: app)
        field.tap()
        field.typeText("   ")
        XCTAssertFalse(search.isEnabled)
    }

    func testQuestionToAnswerToNextQuestion() {
        let app = launch(orientation: .portrait)
        ask("なぜ空は青いの", in: app)

        let question = labeledText("answerQuestion", in: app)
        XCTAssertEqual(question.label, "なぜ空は青いの")
        XCTAssertEqual(labeledText("answerBody", in: app).label, "ここに答えが入ります")

        element("sourceButton", in: app).tap()
        _ = labeledText("sourceNote", in: app)
        XCTAssertEqual(app.state, .runningForeground)

        element("nextQuestionButton", in: app).tap()
        XCTAssertTrue(app.staticTexts["questionHeading"].waitForExistence(timeout: 5))
        assertDraftCleared(in: app)
    }

    func testQuestionToHistoryToAnswer() {
        let app = launch(orientation: .portrait)
        element("historyButton", in: app).tap()
        element("history-sample-1", in: app).tap()

        XCTAssertEqual(labeledText("answerQuestion", in: app).label, "空はなぜ青いの")
        XCTAssertEqual(
            labeledText("answerBody", in: app).label,
            "太陽の光が空気の中でちらばるからです。"
        )
    }

    func testMeasurementScreenOpensFromGear() {
        let app = launch(orientation: .portrait)
        element("measurementButton", in: app).tap()
        XCTAssertTrue(app.staticTexts["measurementHeading"].waitForExistence(timeout: 5))
        app.navigationBars.buttons["質問"].tap()
        XCTAssertTrue(app.staticTexts["questionHeading"].waitForExistence(timeout: 5))
    }

    func testNavigationAndSearchButtonInLandscape() {
        let app = launch(orientation: .landscapeLeft)
        let search = element("searchButton", in: app)
        XCTAssertFalse(search.isEnabled)

        let field = questionField(in: app)
        field.tap()
        field.typeText("月はなぜ光るの")

        let hittable = NSPredicate(format: "isHittable == true AND isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: hittable, object: search)
        wait(for: [expectation], timeout: 5)
        search.tap()

        XCTAssertEqual(labeledText("answerQuestion", in: app).label, "月はなぜ光るの")
        element("nextQuestionButton", in: app).tap()
        XCTAssertTrue(app.staticTexts["questionHeading"].waitForExistence(timeout: 5))
        assertDraftCleared(in: app)
    }

    private func launch(orientation: UIDeviceOrientation) -> XCUIApplication {
        let app = XCUIApplication()
        app.launch()
        rotate(to: orientation)
        return app
    }

    private func rotate(to orientation: UIDeviceOrientation) {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            XCUIDevice.shared.orientation = orientation
            if XCUIDevice.shared.orientation == orientation {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("画面の向きを変えられなかった")
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let queries = [
            app.buttons[identifier],
            app.staticTexts[identifier],
            app.textFields[identifier],
            app.textViews[identifier],
            app.cells[identifier],
        ]
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let match = queries.first(where: \.exists) {
                return match
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTFail("\(identifier) が見つからない")
        return app.buttons[identifier]
    }

    private func labeledText(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        let match = app.staticTexts.matching(predicate).firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: 5), "\(identifier) が見つからない")
        return match
    }

    private func questionField(in app: XCUIApplication) -> XCUIElement {
        let field = app.textFields["questionField"]
        if field.waitForExistence(timeout: 10) {
            return field
        }
        let textView = app.textViews["questionField"]
        XCTAssertTrue(textView.waitForExistence(timeout: 2), "質問の入力欄が見つからない")
        return textView
    }

    private func ask(_ text: String, in app: XCUIApplication) {
        let field = questionField(in: app)
        field.tap()
        field.typeText(text)
        let search = element("searchButton", in: app)
        XCTAssertTrue(search.isEnabled)
        search.tap()
    }

    private func assertDraftCleared(in app: XCUIApplication) {
        let field = questionField(in: app)
        let value = field.value as? String ?? ""
        XCTAssertTrue(
            value.isEmpty || value == "質問を入力",
            "入力欄が空ではない: \(value)"
        )
        XCTAssertFalse(element("searchButton", in: app).isEnabled)
    }
}
