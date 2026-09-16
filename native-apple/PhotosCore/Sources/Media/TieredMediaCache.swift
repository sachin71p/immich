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
/// and LRU chain; pins (offline keeps, task 3) are never evicted.
///
/// Original-tier bytes are stored verbatim — task 5 (HEIC/RAW/ProRAW/HDR keep original bytes);
/// byte-identity is covered by tests.
///
/// Concurrency (WP1 §4.7): `init` never touches the filesystem — the directory scan that used
/// to block launch (R9) now runs lazily in a detached utility task started by the first
/// budget/usage/evict call (`ensureIndexed`). Until the scan lands, `cachedTiers`/`retrieve`
/// fall back to `FileManager.fileExists` on the computed path. All file I/O runs in detached
/// tasks off the actor, so many cells can read concurrently; the actor only computes URLs
/// and updates the index.
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
  private var indexed = false
  private var indexTask: Task<Void, Never>?

  public init(rootDirectory: URL, budgets: CacheBudgets = CacheBudgets()) {
    self.rootDirectory = rootDirectory
    self.budgets = budgets
    self.entries = [:]
    self.pins = []
    self.sequence = 0
  }

  /// Starts the detached index scan (idempotent). Called by the first budget/usage/evict
  /// call, and directly by anyone wanting to warm the index (e.g. app launch, off-main).
  public func ensureIndexed() {
    guard !indexed, indexTask == nil else { return }
    let root = rootDirectory
    indexTask = Task.detached(priority: .utility) {
      let scanned = Self.scan(rootDirectory: root)
      await self.noteIndexed(scanned)
    }
  }

  /// Merges a finished scan: live writes win (a key written after the scan started keeps
  /// its live size/sequence; only keys the live index never saw are added).
  private func noteIndexed(_ scanned: [MediaTier: [String: Entry]]) {
    for (tier, map) in scanned {
      for (key, entry) in map where entries[tier]?[key] == nil {
        entries[tier, default: [:]][key] = entry
      }
    }
    indexed = true
  }

  private func awaitIndexed() async {
    await indexTask?.value
  }

  // MARK: - reads / writes

  public func store(_ data: Data, assetID: String, tier: MediaTier, edited: Bool = false) async throws {
    let key = Self.key(assetID: assetID, edited: edited)
    let url = fileURL(key: key, tier: tier)
    try await Self.writeFile(data, to: url)
    sequence += 1
    entries[tier, default: [:]][key] = Entry(size: data.count, sequence: sequence)
    await enforceBudget(for: tier)
  }

  /// Returns cached bytes, or `nil` on a miss (or an unreadable file, treated as a miss).
  /// Hits advance the entry's LRU position. When the index isn't ready yet, any file on
  /// disk counts as a hit (warming the index as it goes); once indexed, misses return
  /// without touching the filesystem.
  public func retrieve(assetID: String, tier: MediaTier, edited: Bool = false) async -> Data? {
    let key = Self.key(assetID: assetID, edited: edited)
    let url = fileURL(key: key, tier: tier)
    if indexed, entries[tier]?[key] == nil { return nil }
    guard let data = await Self.readFile(url) else {
      if indexed { entries[tier]?.removeValue(forKey: key) }
      return nil
    }
    sequence += 1
    entries[tier, default: [:]][key] = Entry(size: data.count, sequence: sequence)
    return data
  }

  public func remove(assetID: String, tier: MediaTier, edited: Bool = false) async {
    let key = Self.key(assetID: assetID, edited: edited)
    let url = fileURL(key: key, tier: tier)
    entries[tier]?.removeValue(forKey: key)
    await Self.removeFile(url)
  }

  /// Cached tiers for an asset, best quality first — drives offline "best cached tier" (task 4).
  /// Never waits for the index: before it's ready, presence falls back to `fileExists`.
  public func cachedTiers(assetID: String, edited: Bool = false) -> [MediaTier] {
    let key = Self.key(assetID: assetID, edited: edited)
    return MediaTier.orderedHighToLow.filter { tier in
      if entries[tier]?[key] != nil { return true }
      if indexed { return false }
      return FileManager.default.fileExists(atPath: fileURL(key: key, tier: tier).path)
    }
  }

  public func bestCachedTier(assetID: String, edited: Bool = false) -> MediaTier? {
    cachedTiers(assetID: assetID, edited: edited).first
  }

  // MARK: - budget policy (A6 surface)

  public func setBudget(_ bytes: Int?, for tier: MediaTier) async {
    ensureIndexed()
    budgets.bytes[tier] = bytes
    await enforceBudget(for: tier)
  }

  public func budget(for tier: MediaTier) -> Int? {
    ensureIndexed()
    return budgets.budget(for: tier)
  }

  /// Awaits the index when a scan is running, so usage reflects disk (restart durability).
  public func usage() async -> [MediaTier: Int] {
    ensureIndexed()
    await awaitIndexed()
    var result: [MediaTier: Int] = [:]
    for tier in MediaTier.allCases {
      result[tier] = entries[tier, default: [:]].values.reduce(0) { $0 + $1.size }
    }
    return result
  }

  public func totalUsage() async -> Int {
    await usage().values.reduce(0, +)
  }

  /// Evicts least-recently-used unpinned entries until at least `byteCount` bytes are freed.
  /// Returns the bytes actually freed (less than asked when everything left is pinned).
  @discardableResult
  public func evict(freeing byteCount: Int, from tier: MediaTier) async -> Int {
    ensureIndexed()
    await awaitIndexed()
    guard byteCount > 0 else { return 0 }
    var need = byteCount
    var victims: [(key: String, url: URL, size: Int)] = []
    let candidates =
      entries[tier, default: [:]]
      .filter { !pins.contains(Self.pinKey(tier: tier, key: $0.key)) }
      .sorted {
        if $0.value.sequence != $1.value.sequence { return $0.value.sequence < $1.value.sequence }
        return $0.key < $1.key
      }
    for (key, entry) in candidates {
      if need <= 0 { break }
      victims.append((key, fileURL(key: key, tier: tier), entry.size))
      need -= entry.size
    }
    let removedKeys = await Self.removeFiles(victims.map { ($0.url, $0.key) })
    var freed = 0
    for (key, _, size) in victims where removedKeys.contains(key) {
      // A concurrent `store` may have refreshed the key after we snapshotted victims —
      // only drop it when the entry still matches the evicted size.
      if entries[tier]?[key]?.size == size {
        entries[tier]?.removeValue(forKey: key)
        freed += size
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

  private func enforceBudget(for tier: MediaTier) async {
    guard let budget = budgets.budget(for: tier) else { return }
    // Live-index accounting (no index wait: enforcement runs on the write path where the
    // index may still be scanning; the scan merges without clobbering live sizes).
    let over = (entries[tier, default: [:]].values.reduce(0) { $0 + $1.size }) - budget
    if over > 0 { await evict(freeing: over, from: tier) }
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

  // MARK: - off-actor file I/O (detached, never holding the actor)

  private nonisolated static func writeFile(_ data: Data, to url: URL) async throws {
    try await Task.detached(priority: .utility) {
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
      try data.write(to: url, options: .atomic)
    }.value
  }

  private nonisolated static func readFile(_ url: URL) async -> Data? {
    await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
  }

  private nonisolated static func removeFile(_ url: URL) async {
    await Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: url) }.value
  }

  /// Deletes files off-actor; returns the keys actually removed.
  private nonisolated static func removeFiles(_ files: [(url: URL, key: String)]) async -> Set<String> {
    await Task.detached(priority: .utility) {
      var removed: Set<String> = []
      for file in files {
        do {
          try FileManager.default.removeItem(at: file.url)
          removed.insert(file.key)
        } catch {
          // Already gone counts as removed — the index must not reference it either.
          if !FileManager.default.fileExists(atPath: file.url.path) {
            removed.insert(file.key)
          }
        }
      }
      return removed
    }.value
  }

  /// Rebuilds the index from files on disk so usage survives restarts. Runs in the
  /// detached `ensureIndexed` task, never on the actor and never in `init`.
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
