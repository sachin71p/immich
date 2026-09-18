import XCTest

/// WP-T red-first tests for P1–P6 (P7 lives in `ParityCollectionsUITests`).
/// Settings identifiers are owned by WP-P; the §3 owner decisions are settled
/// and implemented verbatim (identity block = name + counts + last-synced,
/// with user ID and email in a tappable Account detail row).
final class SettingsUITests: XCTestCase {
  /// Open the account/settings surface via the account button (known on base).
  private func openSettings(
    _ app: XCUIApplication,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let account = app.descendants(matching: .any)["account-button"]
    XCTAssertTrue(
      account.waitForExistence(timeout: 15),
      "P1: expected the account entry control on the Library grid",
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
    Parity.require("settings-avatar", in: app, gap: "P1", owner: "WP-P")
    Parity.require("settings-library-counts", in: app, gap: "P1", owner: "WP-P")
    Parity.require("settings-last-synced", in: app, gap: "P1", owner: "WP-P")
  }

  func test_settings_showsNameUserIdAndEmailTogether() throws {
    let app = Parity.launch()
    openSettings(app)
    // P2/WP-P (P0, standing owner requirement): the user ID must be shown —
    // today only name + email + server host appear. Per settled §3 decision 1
    // the ID and email live in the Account detail row.
    Parity.require("settings-account-row", in: app, gap: "P2", owner: "WP-P")
    Parity.require("settings-user-id", in: app, gap: "P2", owner: "WP-P")
    Parity.require("settings-user-email", in: app, gap: "P2", owner: "WP-P")
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
      Parity.require(id, in: app, gap: "P3", owner: "WP-P")
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
      Parity.require(id, in: app, gap: "P4", owner: "WP-P")
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
