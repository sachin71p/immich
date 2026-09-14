import Testing
@testable import CoreModel
@testable import Rules

@Test func coreModulesLoad() {
  _ = PhotosCoreModel.self
  _ = PhotosRules.self
}
