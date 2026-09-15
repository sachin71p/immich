import Foundation

/// Per-tier disk budgets in bytes. A missing tier means unlimited — the "all thumbnails on
/// device" option (brief task 3) is `setBudget(nil, for: .thumbnail)`.
public struct CacheBudgets: Sendable, Hashable {
  public var bytes: [MediaTier: Int]

  public init(bytes: [MediaTier: Int] = CacheBudgets.defaults) {
    self.bytes = bytes
  }

  public static let defaults: [MediaTier: Int] = [
    .thumbnail: 2_000_000_000,
    .preview: 1_000_000_000,
    .fullsize: 512_000_000,
    .original: 256_000_000,
  ]

  public func budget(for tier: MediaTier) -> Int? {
    bytes[tier]
  }
}

/// Tiered on-disk media cache — brief task 3. Each `MediaTier` gets its own directory, budget,
/// and LRU chain; pins (offline keeps, task 3) are never evicted. The budget policy surface
/// (`setBudget`, `evict`, `usage`) is what A6 drives.
///
/// Original-tier bytes are stored verbatim — task 5 (HEIC/RAW/ProRAW/HDR keep original bytes);
/// byte-identity is covered by tests.
public actor TieredMediaCache {
  private struct Entry: Sendable {
    var size: Int
    var sequence: UInt64
  }

  public let rootDirectory: URL
  private var budgets: CacheBudgets
  private var entries: [MediaTier: [String: Entry]]
  private var pins: Set<String>
  private var sequence: UInt64

  public init(rootDirectory: URL, budgets: CacheBudgets = CacheBudgets()) {
    self.rootDirectory = rootDirectory
    self.budgets = budgets
    self.entries = Self.scan(rootDirectory: rootDirectory)
    self.pins = []
    self.sequence = 0
  }

  // MARK: - reads / writes

  public func store(_ data: Data, assetID: String, tier: MediaTier, edited: Bool = false) throws {
    let key = Self.key(assetID: assetID, edited: edited)
    let url = fileURL(key: key, tier: tier)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    sequence += 1
    var tierEntries = entries[tier, default: [:]]
    tierEntries[key] = Entry(size: data.count, sequence: sequence)
    entries[tier] = tierEntries
    enforceBudget(for: tier)
  }

  /// Returns cached bytes, or `nil` on a miss (or an unreadable file, treated as a miss).
  /// Hits advance the entry's LRU position.
  public func retrieve(assetID: String, tier: MediaTier, edited: Bool = false) -> Data? {
    let key = Self.key(assetID: assetID, edited: edited)
    guard entries[tier]?[key] != nil else { return nil }
    guard let data = try? Data(contentsOf: fileURL(key: key, tier: tier)) else {
      var tierEntries = entries[tier, default: [:]]
      tierEntries.removeValue(forKey: key)
      entries[tier] = tierEntries
      return nil
    }
    sequence += 1
    entries[tier]?[key]?.sequence = sequence
    return data
  }

  public func remove(assetID: String, tier: MediaTier, edited: Bool = false) {
    let key = Self.key(assetID: assetID, edited: edited)
    try? FileManager.default.removeItem(at: fileURL(key: key, tier: tier))
    entries[tier]?.removeValue(forKey: key)
  }

  /// Cached tiers for an asset, best quality first — drives offline "best cached tier" (task 4).
  public func cachedTiers(assetID: String, edited: Bool = false) -> [MediaTier] {
    let key = Self.key(assetID: assetID, edited: edited)
    return MediaTier.orderedHighToLow.filter { entries[$0]?[key] != nil }
  }

  public func bestCachedTier(assetID: String, edited: Bool = false) -> MediaTier? {
    cachedTiers(assetID: assetID, edited: edited).first
  }

  // MARK: - budget policy (A6 surface)

  public func setBudget(_ bytes: Int?, for tier: MediaTier) {
    budgets.bytes[tier] = bytes
    enforceBudget(for: tier)
  }

  public func budget(for tier: MediaTier) -> Int? {
    budgets.budget(for: tier)
  }

  public func usage() -> [MediaTier: Int] {
    var result: [MediaTier: Int] = [:]
    for tier in MediaTier.allCases {
      result[tier] = entries[tier, default: [:]].values.reduce(0) { $0 + $1.size }
    }
    return result
  }

  public func totalUsage() -> Int {
    usage().values.reduce(0, +)
  }

  /// Evicts least-recently-used unpinned entries until at least `byteCount` bytes are freed.
  /// Returns the bytes actually freed (less than asked when everything left is pinned).
  @discardableResult
  public func evict(freeing byteCount: Int, from tier: MediaTier) -> Int {
    guard byteCount > 0 else { return 0 }
    var freed = 0
    let victims =
      entries[tier, default: [:]]
      .filter { !pins.contains(Self.pinKey(tier: tier, key: $0.key)) }
      .sorted {
        if $0.value.sequence != $1.value.sequence { return $0.value.sequence < $1.value.sequence }
        return $0.key < $1.key
      }
    for (key, _) in victims {
      if freed >= byteCount { break }
      if let entry = entries[tier]?[key] {
        try? FileManager.default.removeItem(at: fileURL(key: key, tier: tier))
        entries[tier]?.removeValue(forKey: key)
        freed += entry.size
      }
    }
    return freed
  }

  // MARK: - pinning (offline keeps)

  public func setPinned(_ pinned: Bool, assetID: String, tier: MediaTier, edited: Bool = false) {
    let pin = Self.pinKey(tier: tier, key: Self.key(assetID: assetID, edited: edited))
    if pinned {
      pins.insert(pin)
    } else {
      pins.remove(pin)
    }
  }

  public func isPinned(assetID: String, tier: MediaTier, edited: Bool = false) -> Bool {
    pins.contains(Self.pinKey(tier: tier, key: Self.key(assetID: assetID, edited: edited)))
  }

  // MARK: - private

  private func enforceBudget(for tier: MediaTier) {
    guard let budget = budgets.budget(for: tier) else { return }
    let over = (usage()[tier] ?? 0) - budget
    if over > 0 { evict(freeing: over, from: tier) }
  }

  private func fileURL(key: String, tier: MediaTier) -> URL {
    rootDirectory.appendingPathComponent(tier.rawValue).appendingPathComponent(key + ".bin")
  }

  private static func key(assetID: String, edited: Bool) -> String {
    edited ? assetID + "@edited" : assetID
  }

  private static func pinKey(tier: MediaTier, key: String) -> String {
    tier.rawValue + "/" + key
  }

  /// Rebuilds the index from files on disk so usage survives restarts.
  private static func scan(rootDirectory: URL) -> [MediaTier: [String: Entry]] {
    var result: [MediaTier: [String: Entry]] = [:]
    let manager = FileManager.default
    for tier in MediaTier.allCases {
      let dir = rootDirectory.appendingPathComponent(tier.rawValue)
      guard let files = try? manager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
        continue
      }
      for file in files {
        guard file.pathExtension == "bin" else { continue }
        let key = file.deletingPathExtension().lastPathComponent
        let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        result[tier, default: [:]][key] = Entry(size: size, sequence: 0)
      }
    }
    return result
  }
}
