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
        XCTAssertFalse(element("micButton", in: app).isEnabled)
        XCTAssertTrue(app.staticTexts["usageCount"].waitForExistence(timeout: 5))
    }

    func testUsageCountIncrementsOnSearch() {
        let app = launch(
            orientation: .portrait,
            arguments: ["-resetLocalUsageCount"]
        )
        XCTAssertEqual(labeledText("usageCount", in: app).label, "つかった回数: 0")

        ask("なぜ空は青いの", in: app)
        element("nextQuestionButton", in: app).tap()
        XCTAssertTrue(app.staticTexts["questionHeading"].waitForExistence(timeout: 5))
        XCTAssertEqual(labeledText("usageCount", in: app).label, "つかった回数: 1")

        ask("月はなぜ光るの", in: app)
        element("nextQuestionButton", in: app).tap()
        XCTAssertEqual(labeledText("usageCount", in: app).label, "つかった回数: 2")
    }

    func testSearchStaysHittableAboveKeyboardInPortrait() {
        assertSearchStaysHittableAboveKeyboard(orientation: .portrait, shot: "question-portrait-keyboard")
    }

    func testSearchStaysHittableAboveKeyboardInLandscape() {
        assertSearchStaysHittableAboveKeyboard(
            orientation: .landscapeLeft,
            shot: "question-landscape-keyboard"
        )
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

    private func launch(
        orientation: UIDeviceOrientation,
        arguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments
        app.launch()
        rotate(to: orientation)
        return app
    }

    private func assertSearchStaysHittableAboveKeyboard(
        orientation: UIDeviceOrientation,
        shot: String
    ) {
        let app = launch(orientation: orientation)
        let field = questionField(in: app)
        field.tap()

        let keyboard = app.keyboards.firstMatch
        if !keyboard.waitForExistence(timeout: 4) {
            field.tap()
        }
        XCTAssertTrue(keyboard.waitForExistence(timeout: 8), "キーボードが出ていない")
        let key = app.keys.firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 8), "キーボードのキーが出ていない")

        let search = element("searchButton", in: app)
        XCTAssertFalse(search.isEnabled)

        field.typeText("空はなぜ青いの")
        let ready = NSPredicate(format: "isHittable == true AND isEnabled == true")
        wait(for: [XCTNSPredicateExpectation(predicate: ready, object: search)], timeout: 5)
        XCTAssertTrue(
            search.isHittable,
            "調べるがキーボードに隠れている search=\(search.frame) keyboard=\(keyboard.frame)"
        )
        XCTAssertTrue(search.isEnabled)

        let screenHeight = max(app.frame.height, app.windows.firstMatch.frame.height)
        let keyboardHeight = keyboard.frame.height
        let plausibleKeyboard = keyboardHeight > 120 && keyboardHeight < screenHeight * 0.75
        if plausibleKeyboard {
            XCTAssertFalse(
                search.frame.intersects(keyboard.frame),
                "調べるがキーボードと重なっている search=\(search.frame) keyboard=\(keyboard.frame)"
            )
            XCTAssertLessThanOrEqual(
                search.frame.maxY,
                keyboard.frame.minY + 1,
                "調べるがキーボードより下にある search=\(search.frame) keyboard=\(keyboard.frame)"
            )
        }
        saveScreenshot(shot)
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
            value.isEmpty || value == "質問を入力" || value == "質問を入力してください",
            "入力欄が空ではない: \(value)"
        )
        XCTAssertFalse(element("searchButton", in: app).isEnabled)
    }

    private func saveScreenshot(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let directories = [
            ProcessInfo.processInfo.environment["KININARU_SCREENSHOT_DIR"],
            "/tmp/kininaru-ui-screenshots",
        ].compactMap { $0 }.filter { !$0.isEmpty }
        let data = shot.pngRepresentation
        for directory in directories {
            let folder = URL(fileURLWithPath: directory, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? data.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }
}
