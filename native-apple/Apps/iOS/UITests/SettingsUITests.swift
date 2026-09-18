import XCTest

/// WP-T red-first tests for P1–P6 (P7 lives in `ParityCollectionsUITests`).
/// Settings identifiers are owned by WP-P; the §3 owner decisions are settled
/// and implemented verbatim (identity block = name + counts + last-synced,
/// with user ID and email in a tappable Account detail row).
final class SettingsUITests: XCTestCase {
  /// Like `Parity.require`, but swipes the sheet upward until the element
  /// exists. The account sheet is a virtualized List: below-fold rows have
  /// no hierarchy presence until scrolled into view, so a bare require can
  /// never see them. Each lookup is independent — earlier rows may
  /// virtualize away again, which is fine.
  @discardableResult
  private func requireScrolling(
    _ id: String, in app: XCUIApplication, gap: String,
    file: StaticString = #filePath, line: UInt = #line
  ) -> XCUIElement {
    let element = app.descendants(matching: .any)[id]
    if element.waitForExistence(timeout: 2) { return element }
    // Back to the top first (the identity avatar is always there), then
    // sweep downward: the sheet virtualizes in both directions, so every
    // lookup must run monotonically from a known position.
    let top = app.descendants(matching: .any)["settings-avatar"]
    for _ in 0..<10 {
      if top.waitForExistence(timeout: 1) { break }
      app.swipeDown()
    }
    for _ in 0..<20 {
      if element.waitForExistence(timeout: 2) { return element }
      app.swipeUp()
    }
    return Parity.require(id, in: app, gap: gap, owner: "WP-P", file: file, line: line)
  }
  /// Open the account/settings surface via the Search toolbar's account button —
  /// the entry point known on base (ScreenshotTour.tourAccount uses the same
  /// path; the Library grid hosts no account button). Gap assertions below are
  /// unchanged.
  private func openSettings(
    _ app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    app.tabBars.buttons["Search"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["search-view"].waitForExistence(timeout: 30),
      "P1: Search tab should render the search surface",
      file: file, line: line)
    let account = app.descendants(matching: .any)["account-button"]
    XCTAssertTrue(
      account.waitForExistence(timeout: 15),
      "P1: expected the account entry control in the Search toolbar",
      file: file, line: line)
    account.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["account-sheet"].waitForExistence(timeout: 10),
      "P1: tapping account should open the account sheet", file: file, line: line)
  }

  func test_accountHeader_isCentredWithPhotoVideoCountsAndLastSynced() throws {
    let app = Parity.launch()
    openSettings(app)
    // P1/WP-P: centred large avatar, name, `N Photos, M Videos`,
    // `Last Synced …` — not a left-aligned card.
    requireScrolling("settings-avatar", in: app, gap: "P1")
    requireScrolling("settings-library-counts", in: app, gap: "P1")
    requireScrolling("settings-last-synced", in: app, gap: "P1")
  }

  func test_settings_showsNameUserIdAndEmailTogether() throws {
    let app = Parity.launch()
    openSettings(app)
    // P2/WP-P (P0, standing owner requirement): the user ID must be shown —
    // today only name + email + server host appear. Per settled §3 decision 1
    // the ID and email live in the Account detail row.
    requireScrolling("settings-account-row", in: app, gap: "P2")
    requireScrolling("settings-user-id", in: app, gap: "P2")
    requireScrolling("settings-user-email", in: app, gap: "P2")
  }

  func test_settings_containsPhotosParityItems() throws {
    let app = Parity.launch()
    openSettings(app)
    // P3/WP-P: adopted Photos items (PLAN §3).
    for id in [
      "settings-invitations",
      "settings-manage-keywords",
      "settings-zoom-to-fill",
      "settings-show-ratings",
      "settings-show-featured",
      "settings-reset-memories",
      "settings-reset-people-suggestions",
    ] {
      requireScrolling(id, in: app, gap: "P3")
    }
  }

  func test_settings_preservesHeirloomOnlyItems() throws {
    let app = Parity.launch()
    openSettings(app)
    // P4/WP-P (regression): Heirloom-only items must survive the §3 merge.
    // Several already exist on base (`settings-sync-now`,
    // `settings-last-synced`, `settings-optimize-storage`, `settings-freeup`,
    // `settings-syncing`, `timeline-sources`); assert the full set so a
    // future merge cannot silently drop one.
    for id in [
      "settings-sync-now",
      "settings-last-synced",
      "settings-backup-photos",
      "timeline-sources",
      "settings-freeup",
      "settings-optimize-storage",
      "settings-cache-usage",
      "account-shared-libraries",
      "account-signout",
    ] {
      requireScrolling(id, in: app, gap: "P4")
    }
  }

  func test_memories_rendersGeneratedCards() throws {
    let app = Parity.launch()
    // P5/WP-P: generated memory cards + a "Type to Create" affordance, not
    // the empty state. (Collections → Memories path matches the A9 test.)
    app.tabBars.buttons["Collections"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["collections"].waitForExistence(timeout: 30))
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Memories'")).firstMatch.tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["memories"].waitForExistence(timeout: 10))
    Parity.require("memories-type-to-create", in: app, gap: "P5", owner: "WP-P")
    let card = app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier BEGINSWITH 'memory-'")).firstMatch
    XCTAssertTrue(
      card.waitForExistence(timeout: 10),
      "P5/WP-P: Memories should show at least one generated card, not the empty state")
  }

  func test_search_hasNaturalLanguageSuggestionsAndPersistentField() throws {
    let app = Parity.launch()
    // P6/WP-P: NL suggestion chips, Recents thumbnails, persistent bottom
    // search field — not metadata chips only.
    app.tabBars.buttons["Search"].tap()
    XCTAssertTrue(
      app.descendants(matching: .any)["search-view"].waitForExistence(timeout: 30))
    Parity.require("search-nl-suggestions", in: app, gap: "P6", owner: "WP-P")
    Parity.require("search-recents-thumbnails", in: app, gap: "P6", owner: "WP-P")
    Parity.require("search-persistent-field", in: app, gap: "P6", owner: "WP-P")
  }
}
