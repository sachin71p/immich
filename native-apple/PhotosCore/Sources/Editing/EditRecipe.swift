import CoreGraphics
import CoreModel
import Foundation

/// The metadata-KV key holding the fork's edit recipe. The stored value is always a JSON
/// object (`PUT /assets/:id/metadata` requires object values — server/src/dtos/asset.dto.ts
/// `AssetMetadataUpsertItemSchema`):
/// `{ "format": "fork.editRecipe.v2", "sourceAssetId": ..., "savedAt": ...,
///    "recipe": {...}, "renderedAssetId": ...? }` — see `EditPersistencePayload`.
///
/// E1 v2: reads try `.current` first and fall back to `.legacy` (decoded with identity
/// defaults for missing keys, as before); saves write `.current` only and delete `.legacy`
/// after a successful write (lazy migration on touch — no standalone migration job).
public enum EditRecipeKey {
  public static let current = "fork.editRecipe.v2"
  public static let legacy = "fork.editRecipe.v1"
}

/// A full non-destructive edit description. The original bytes are never modified: operations
/// upstream supports (crop rectangle, quarter-turn rotation, flips) are ALSO sent to
/// `PUT /assets/:id/edits`, while this recipe is the source of truth for everything else and
/// for the client-side full-resolution render that is PUT as the asset's rendition
/// (`PUT /assets/:id/rendition`) on the same asset — no separate asset is ever created.
public struct EditRecipe: Sendable, Codable, Equatable {
  public static let schemaVersion = 1

  public var adjust: AdjustRecipe
  public var style: StyleRecipe?
  public var crop: CropRecipe?
  public var portrait: PortraitRecipe?
  public var markup: MarkupRecipe?
  public var video: VideoRecipe?

  public init(
    adjust: AdjustRecipe = .init(),
    style: StyleRecipe? = nil,
    crop: CropRecipe? = nil,
    portrait: PortraitRecipe? = nil,
    markup: MarkupRecipe? = nil,
    video: VideoRecipe? = nil
  ) {
    self.adjust = adjust
    self.style = style
    self.crop = crop
    self.portrait = portrait
    self.markup = markup
    self.video = video
  }

  /// True when every section is at its neutral value — nothing to persist, render, or upload.
  public var isEmpty: Bool {
    adjust.isEmpty && style == nil && crop == nil && portrait == nil && markup == nil && video == nil
  }

  /// True when the recipe contains anything upstream edits cannot express (anything beyond a
  /// crop rectangle, quarter-turn rotation, and flips). Such recipes REQUIRE the recipe-KV +
  /// rendered-upload path; upstream-only recipes may persist through `/edits` alone, though the
  /// recipe is still saved so other clients can show "edited in Heirloom".
  public var requiresClientRender: Bool {
    if !(style?.isNeutral ?? true) { return true }
    if !adjust.isEmpty { return true }
    if let crop, !crop.isUpstreamExpressible { return true }
    if portrait != nil { return true }
    if markup != nil { return true }
    if video != nil { return true }
    return false
  }
}

/// One Curves control point in unit `0...1` space (`x` = input tone,
/// `y` = output tone). Both components clamp into `0...1` on init, so stored
/// and decoded points are always in range.
public struct CurvePoint: Sendable, Codable, Equatable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = Self.clampUnit(x)
    self.y = Self.clampUnit(y)
  }

  public static func clampUnit(_ v: Double) -> Double { min(1, max(0, v)) }

  /// Piecewise-linear evaluation with implicit `(0, 0)` / `(1, 1)` endpoints:
  /// user points at `x == 0` / `x == 1` override the black/white rails, inner
  /// points interpolate, and storage order is irrelevant (sorted here).
  /// Inputs and outputs clamp to `0...1`.
  public static func evaluate(_ points: [CurvePoint], at x: Double) -> Double {
    let t = clampUnit(x)
    let sorted = points.sorted { $0.x < $1.x }
    var prev = CurvePoint(x: 0, y: 0)
    for p in sorted {
      if t <= p.x {
        let span = p.x - prev.x
        if span <= 1e-9 {
          prev = p
          continue
        }
        return clampUnit(prev.y + (t - prev.x) / span * (p.y - prev.y))
      }
      prev = p
    }
    let span = 1 - prev.x
    guard span > 1e-9 else { return clampUnit(prev.y) }
    return clampUnit(prev.y + (t - prev.x) / span * (1 - prev.y))
  }
}

/// All `-100...100` adjust sliders. Values are clamped on set; neutral is `0`.
///
/// WP-E section map: Light (exposure…blackPoint), Color (saturation, vibrance, cast),
/// Black & White (bwIntensity, bwNeutrals, bwTone, grain), White Balance
/// (wbTemperature, wbTint; warmth/tint are the legacy pair and keep rendering),
/// Sharpen (sharpness legacy + sharpenEdges/sharpenFalloff), Vignette (legacy vignette
/// + vignetteStrength/Radius/Softness), Curves (curvesMaster/Red/Green/Blue point
/// arrays), Levels (levelsInBlack/White/OutBlack/OutWhite), plus
/// definition/noiseReduction.
///
/// Back-compat: every WP-E key decodes with `decodeIfPresent`, so recipes written
/// before this WP (missing keys) decode with neutral defaults and render identically.
public struct AdjustRecipe: Sendable, Equatable {
  public var exposure: Int
  public var brilliance: Int
  public var highlights: Int
  public var shadows: Int
  public var contrast: Int
  public var brightness: Int
  public var blackPoint: Int
  public var saturation: Int
  public var vibrance: Int
  public var warmth: Int
  public var tint: Int
  public var sharpness: Int
  public var definition: Int
  public var noiseReduction: Int
  public var vignette: Int
  public var autoEnhance: Bool
  // MARK: WP-E keys
  /// Color > Cast (extra color shift applied after warmth/tint).
  public var cast: Int
  /// B&W section.
  public var bwIntensity: Int
  public var bwNeutrals: Int
  public var bwTone: Int
  public var grain: Int
  /// White Balance section (finer than the legacy warmth/tint pair).
  public var wbTemperature: Int
  public var wbTint: Int
  /// Sharpen section detail.
  public var sharpenEdges: Int
  public var sharpenFalloff: Int
  /// Vignette section detail.
  public var vignetteStrength: Int
  public var vignetteRadius: Int
  public var vignetteSoftness: Int
  /// Levels section (D3): dedicated input/output handle positions, 0...100.
  public var levelsInBlack: Int
  public var levelsInWhite: Int
  public var levelsOutBlack: Int
  public var levelsOutWhite: Int
  /// Selective Color section (D1): 6 hue swatches × Hue/Saturation/Luminance/
  /// Range. Hue/Saturation/Luminance are -100...100 (neutral 0); Range is
  /// 0...100 (default 0 = narrowest falloff, so the generic section
  /// reset-to-0 restores defaults and `isEmpty` stays exact).
  public var selRedHue: Int
  public var selRedSat: Int
  public var selRedLum: Int
  public var selRedRange: Int
  public var selOrangeHue: Int
  public var selOrangeSat: Int
  public var selOrangeLum: Int
  public var selOrangeRange: Int
  public var selYellowHue: Int
  public var selYellowSat: Int
  public var selYellowLum: Int
  public var selYellowRange: Int
  public var selGreenHue: Int
  public var selGreenSat: Int
  public var selGreenLum: Int
  public var selGreenRange: Int
  public var selBlueHue: Int
  public var selBlueSat: Int
  public var selBlueLum: Int
  public var selBlueRange: Int
  public var selMagentaHue: Int
  public var selMagentaSat: Int
  public var selMagentaLum: Int
  public var selMagentaRange: Int
  /// Red-Eye section (D4): tap-to-select eye regions (normalized, origin
  /// upper-left) plus a 0...100 correction strength. Empty regions = identity
  /// regardless of strength, so legacy payloads (missing keys) render unchanged.
  public var redEyeRegions: [RedEyeRegion]
  public var redEyeStrength: Int
  /// Curves section (D2): per-channel tone curves as point arrays in unit
  /// `0...1` space. Empty = identity (legacy payloads missing these keys
  /// decode to `[]` and render identically).
  public var curvesMaster: [CurvePoint]
  public var curvesRed: [CurvePoint]
  public var curvesGreen: [CurvePoint]
  public var curvesBlue: [CurvePoint]
  /// Recipe/pipeline versions (on-device-AI §13.2; full v2 migration is E1's).
  /// 0 = legacy unversioned payload; new saves write 1.
  public var recipeVersion: Int
  public var rendererVersion: Int

  public init(
    exposure: Int = 0, brilliance: Int = 0, highlights: Int = 0, shadows: Int = 0,
    contrast: Int = 0, brightness: Int = 0, blackPoint: Int = 0, saturation: Int = 0,
    vibrance: Int = 0, warmth: Int = 0, tint: Int = 0, sharpness: Int = 0,
    definition: Int = 0, noiseReduction: Int = 0, vignette: Int = 0, autoEnhance: Bool = false,
    cast: Int = 0, bwIntensity: Int = 0, bwNeutrals: Int = 0, bwTone: Int = 0, grain: Int = 0,
    wbTemperature: Int = 0, wbTint: Int = 0, sharpenEdges: Int = 0, sharpenFalloff: Int = 0,
    vignetteStrength: Int = 0, vignetteRadius: Int = 0, vignetteSoftness: Int = 0,
    levelsInBlack: Int = 0, levelsInWhite: Int = 100,
    levelsOutBlack: Int = 0, levelsOutWhite: Int = 100,
    selRedHue: Int = 0, selRedSat: Int = 0, selRedLum: Int = 0, selRedRange: Int = 0,
    selOrangeHue: Int = 0, selOrangeSat: Int = 0, selOrangeLum: Int = 0, selOrangeRange: Int = 0,
    selYellowHue: Int = 0, selYellowSat: Int = 0, selYellowLum: Int = 0, selYellowRange: Int = 0,
    selGreenHue: Int = 0, selGreenSat: Int = 0, selGreenLum: Int = 0, selGreenRange: Int = 0,
    selBlueHue: Int = 0, selBlueSat: Int = 0, selBlueLum: Int = 0, selBlueRange: Int = 0,
    selMagentaHue: Int = 0, selMagentaSat: Int = 0, selMagentaLum: Int = 0, selMagentaRange: Int = 0,
    redEyeRegions: [RedEyeRegion] = [], redEyeStrength: Int = 0,
    curvesMaster: [CurvePoint] = [], curvesRed: [CurvePoint] = [],
    curvesGreen: [CurvePoint] = [], curvesBlue: [CurvePoint] = [],
    recipeVersion: Int = 1, rendererVersion: Int = 1
  ) {
    self.exposure = Self.clamp(exposure)
    self.brilliance = Self.clamp(brilliance)
    self.highlights = Self.clamp(highlights)
    self.shadows = Self.clamp(shadows)
    self.contrast = Self.clamp(contrast)
    self.brightness = Self.clamp(brightness)
    self.blackPoint = Self.clamp(blackPoint)
    self.saturation = Self.clamp(saturation)
    self.vibrance = Self.clamp(vibrance)
    self.warmth = Self.clamp(warmth)
    self.tint = Self.clamp(tint)
    self.sharpness = Self.clamp(sharpness)
    self.definition = Self.clamp(definition)
    self.noiseReduction = Self.clamp(noiseReduction)
    self.vignette = Self.clamp(vignette)
    self.autoEnhance = autoEnhance
    self.cast = Self.clamp(cast)
    self.bwIntensity = Self.clamp(bwIntensity)
    self.bwNeutrals = Self.clamp(bwNeutrals)
    self.bwTone = Self.clamp(bwTone)
    self.grain = Self.clamp(grain)
    self.wbTemperature = Self.clamp(wbTemperature)
    self.wbTint = Self.clamp(wbTint)
    self.sharpenEdges = Self.clamp(sharpenEdges)
    self.sharpenFalloff = Self.clamp(sharpenFalloff)
    self.vignetteStrength = Self.clamp(vignetteStrength)
    self.vignetteRadius = Self.clamp(vignetteRadius)
    self.vignetteSoftness = Self.clamp(vignetteSoftness)
    self.levelsInBlack = Self.clamp(levelsInBlack)
    self.levelsInWhite = Self.clamp(levelsInWhite)
    self.levelsOutBlack = Self.clamp(levelsOutBlack)
    self.levelsOutWhite = Self.clamp(levelsOutWhite)
    self.selRedHue = Self.clamp(selRedHue)
    self.selRedSat = Self.clamp(selRedSat)
    self.selRedLum = Self.clamp(selRedLum)
    self.selRedRange = Self.clampRange(selRedRange)
    self.selOrangeHue = Self.clamp(selOrangeHue)
    self.selOrangeSat = Self.clamp(selOrangeSat)
    self.selOrangeLum = Self.clamp(selOrangeLum)
    self.selOrangeRange = Self.clampRange(selOrangeRange)
    self.selYellowHue = Self.clamp(selYellowHue)
    self.selYellowSat = Self.clamp(selYellowSat)
    self.selYellowLum = Self.clamp(selYellowLum)
    self.selYellowRange = Self.clampRange(selYellowRange)
    self.selGreenHue = Self.clamp(selGreenHue)
    self.selGreenSat = Self.clamp(selGreenSat)
    self.selGreenLum = Self.clamp(selGreenLum)
    self.selGreenRange = Self.clampRange(selGreenRange)
    self.selBlueHue = Self.clamp(selBlueHue)
    self.selBlueSat = Self.clamp(selBlueSat)
    self.selBlueLum = Self.clamp(selBlueLum)
    self.selBlueRange = Self.clampRange(selBlueRange)
    self.selMagentaHue = Self.clamp(selMagentaHue)
    self.selMagentaSat = Self.clamp(selMagentaSat)
    self.selMagentaLum = Self.clamp(selMagentaLum)
    self.selMagentaRange = Self.clampRange(selMagentaRange)
    self.redEyeRegions = redEyeRegions.map { $0.clamped() }
    self.redEyeStrength = Self.clamp(redEyeStrength)
    self.curvesMaster = Self.clampCurve(curvesMaster)
    self.curvesRed = Self.clampCurve(curvesRed)
    self.curvesGreen = Self.clampCurve(curvesGreen)
    self.curvesBlue = Self.clampCurve(curvesBlue)
    self.recipeVersion = recipeVersion
    self.rendererVersion = rendererVersion
  }

  public static func clamp(_ v: Int) -> Int { min(100, max(-100, v)) }

  /// 0...100 clamp for Selective Color Range keys.
  public static func clampRange(_ v: Int) -> Int { min(100, max(0, v)) }
  /// Per-channel point cap: bounds worst-case recipe payload (D6a notes recipes
  /// are ~1KB JSON; 64 points × 4 channels stays well inside that).
  public static let maxCurvePoints = 64

  /// Clamps every point into unit space (via `CurvePoint.init`) and caps length.
  public static func clampCurve(_ pts: [CurvePoint]) -> [CurvePoint] {
    Array(pts.prefix(maxCurvePoints).map { CurvePoint(x: $0.x, y: $0.y) })
  }

  public var isEmpty: Bool { self == AdjustRecipe() }

  /// Slider value -> unit float in `-1...1`.
  public func unit(_ v: Int) -> Double { Double(v) / 100.0 }

  /// True when any Selective Color (D1) shift is non-zero. Range keys alone
  /// never trigger the kernel — they only shape the falloff of a shift.
  public var isSelectiveActive: Bool {
    selRedHue != 0 || selRedSat != 0 || selRedLum != 0
      || selOrangeHue != 0 || selOrangeSat != 0 || selOrangeLum != 0
      || selYellowHue != 0 || selYellowSat != 0 || selYellowLum != 0
      || selGreenHue != 0 || selGreenSat != 0 || selGreenLum != 0
      || selBlueHue != 0 || selBlueSat != 0 || selBlueLum != 0
      || selMagentaHue != 0 || selMagentaSat != 0 || selMagentaLum != 0
  }
}

extension AdjustRecipe: Codable {
  private enum CodingKeys: String, CodingKey {
    case exposure, brilliance, highlights, shadows, contrast, brightness, blackPoint,
      saturation, vibrance, warmth, tint, sharpness, definition, noiseReduction, vignette,
      autoEnhance, cast, bwIntensity, bwNeutrals, bwTone, grain, wbTemperature, wbTint,
      sharpenEdges, sharpenFalloff, vignetteStrength, vignetteRadius, vignetteSoftness,
      levelsInBlack, levelsInWhite, levelsOutBlack, levelsOutWhite,
      selRedHue, selRedSat, selRedLum, selRedRange,
      selOrangeHue, selOrangeSat, selOrangeLum, selOrangeRange,
      selYellowHue, selYellowSat, selYellowLum, selYellowRange,
      selGreenHue, selGreenSat, selGreenLum, selGreenRange,
      selBlueHue, selBlueSat, selBlueLum, selBlueRange,
      selMagentaHue, selMagentaSat, selMagentaLum, selMagentaRange,
      redEyeRegions, redEyeStrength,
      curvesMaster, curvesRed, curvesGreen, curvesBlue,
      recipeVersion, rendererVersion
  }

  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    func v(_ k: CodingKeys) -> Int {
      guard let outer = (try? c.decodeIfPresent(Int.self, forKey: k)) else { return 0 }
      return outer ?? 0
    }
    /// Missing key decodes to `dflt` (for keys whose default isn't 0, so
    /// legacy payloads keep identity semantics).
    func vd(_ k: CodingKeys, dflt: Int) -> Int {
      guard let outer = (try? c.decodeIfPresent(Int.self, forKey: k)) else { return dflt }
      return outer ?? dflt
    }
    /// Missing point-array key decodes to `[]` (identity), clamping + capping
    /// whatever a newer writer stored, so legacy payloads render identically.
    func vp(_ k: CodingKeys) -> [CurvePoint] {
      guard let outer = (try? c.decodeIfPresent([CurvePoint].self, forKey: k)) else { return [] }
      return AdjustRecipe.clampCurve(outer ?? [])
    }
    let autoEnhance: Bool = {
      guard let outer = (try? c.decodeIfPresent(Bool.self, forKey: .autoEnhance)) else { return false }
      return outer ?? false
    }()
    self.init(
      exposure: v(.exposure), brilliance: v(.brilliance), highlights: v(.highlights),
      shadows: v(.shadows), contrast: v(.contrast), brightness: v(.brightness),
      blackPoint: v(.blackPoint), saturation: v(.saturation), vibrance: v(.vibrance),
      warmth: v(.warmth), tint: v(.tint), sharpness: v(.sharpness),
      definition: v(.definition), noiseReduction: v(.noiseReduction), vignette: v(.vignette),
      autoEnhance: autoEnhance,
      cast: v(.cast), bwIntensity: v(.bwIntensity), bwNeutrals: v(.bwNeutrals),
      bwTone: v(.bwTone), grain: v(.grain), wbTemperature: v(.wbTemperature),
      wbTint: v(.wbTint), sharpenEdges: v(.sharpenEdges), sharpenFalloff: v(.sharpenFalloff),
      vignetteStrength: v(.vignetteStrength), vignetteRadius: v(.vignetteRadius),
      vignetteSoftness: v(.vignetteSoftness),
      levelsInBlack: v(.levelsInBlack), levelsInWhite: vd(.levelsInWhite, dflt: 100),
      levelsOutBlack: v(.levelsOutBlack), levelsOutWhite: vd(.levelsOutWhite, dflt: 100),
      selRedHue: v(.selRedHue), selRedSat: v(.selRedSat), selRedLum: v(.selRedLum),
      selRedRange: v(.selRedRange),
      selOrangeHue: v(.selOrangeHue), selOrangeSat: v(.selOrangeSat), selOrangeLum: v(.selOrangeLum),
      selOrangeRange: v(.selOrangeRange),
      selYellowHue: v(.selYellowHue), selYellowSat: v(.selYellowSat), selYellowLum: v(.selYellowLum),
      selYellowRange: v(.selYellowRange),
      selGreenHue: v(.selGreenHue), selGreenSat: v(.selGreenSat), selGreenLum: v(.selGreenLum),
      selGreenRange: v(.selGreenRange),
      selBlueHue: v(.selBlueHue), selBlueSat: v(.selBlueSat), selBlueLum: v(.selBlueLum),
      selBlueRange: v(.selBlueRange),
      selMagentaHue: v(.selMagentaHue), selMagentaSat: v(.selMagentaSat),
      selMagentaLum: v(.selMagentaLum), selMagentaRange: v(.selMagentaRange),
      redEyeRegions: (try? c.decodeIfPresent([RedEyeRegion].self, forKey: .redEyeRegions)) ?? [],
      redEyeStrength: v(.redEyeStrength),
      curvesMaster: vp(.curvesMaster), curvesRed: vp(.curvesRed),
      curvesGreen: vp(.curvesGreen), curvesBlue: vp(.curvesBlue),
      recipeVersion: v(.recipeVersion), rendererVersion: v(.rendererVersion))
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(exposure, forKey: .exposure)
    try c.encode(brilliance, forKey: .brilliance)
    try c.encode(highlights, forKey: .highlights)
    try c.encode(shadows, forKey: .shadows)
    try c.encode(contrast, forKey: .contrast)
    try c.encode(brightness, forKey: .brightness)
    try c.encode(blackPoint, forKey: .blackPoint)
    try c.encode(saturation, forKey: .saturation)
    try c.encode(vibrance, forKey: .vibrance)
    try c.encode(warmth, forKey: .warmth)
    try c.encode(tint, forKey: .tint)
    try c.encode(sharpness, forKey: .sharpness)
    try c.encode(definition, forKey: .definition)
    try c.encode(noiseReduction, forKey: .noiseReduction)
    try c.encode(vignette, forKey: .vignette)
    try c.encode(autoEnhance, forKey: .autoEnhance)
    try c.encode(cast, forKey: .cast)
    try c.encode(bwIntensity, forKey: .bwIntensity)
    try c.encode(bwNeutrals, forKey: .bwNeutrals)
    try c.encode(bwTone, forKey: .bwTone)
    try c.encode(grain, forKey: .grain)
    try c.encode(wbTemperature, forKey: .wbTemperature)
    try c.encode(wbTint, forKey: .wbTint)
    try c.encode(sharpenEdges, forKey: .sharpenEdges)
    try c.encode(sharpenFalloff, forKey: .sharpenFalloff)
    try c.encode(vignetteStrength, forKey: .vignetteStrength)
    try c.encode(vignetteRadius, forKey: .vignetteRadius)
    try c.encode(vignetteSoftness, forKey: .vignetteSoftness)
    try c.encode(levelsInBlack, forKey: .levelsInBlack)
    try c.encode(levelsInWhite, forKey: .levelsInWhite)
    try c.encode(levelsOutBlack, forKey: .levelsOutBlack)
    try c.encode(levelsOutWhite, forKey: .levelsOutWhite)
    try c.encode(selRedHue, forKey: .selRedHue)
    try c.encode(selRedSat, forKey: .selRedSat)
    try c.encode(selRedLum, forKey: .selRedLum)
    try c.encode(selRedRange, forKey: .selRedRange)
    try c.encode(selOrangeHue, forKey: .selOrangeHue)
    try c.encode(selOrangeSat, forKey: .selOrangeSat)
    try c.encode(selOrangeLum, forKey: .selOrangeLum)
    try c.encode(selOrangeRange, forKey: .selOrangeRange)
    try c.encode(selYellowHue, forKey: .selYellowHue)
    try c.encode(selYellowSat, forKey: .selYellowSat)
    try c.encode(selYellowLum, forKey: .selYellowLum)
    try c.encode(selYellowRange, forKey: .selYellowRange)
    try c.encode(selGreenHue, forKey: .selGreenHue)
    try c.encode(selGreenSat, forKey: .selGreenSat)
    try c.encode(selGreenLum, forKey: .selGreenLum)
    try c.encode(selGreenRange, forKey: .selGreenRange)
    try c.encode(selBlueHue, forKey: .selBlueHue)
    try c.encode(selBlueSat, forKey: .selBlueSat)
    try c.encode(selBlueLum, forKey: .selBlueLum)
    try c.encode(selBlueRange, forKey: .selBlueRange)
    try c.encode(selMagentaHue, forKey: .selMagentaHue)
    try c.encode(selMagentaSat, forKey: .selMagentaSat)
    try c.encode(selMagentaLum, forKey: .selMagentaLum)
    try c.encode(selMagentaRange, forKey: .selMagentaRange)
    try c.encode(redEyeRegions, forKey: .redEyeRegions)
    try c.encode(redEyeStrength, forKey: .redEyeStrength)
    try c.encode(curvesMaster, forKey: .curvesMaster)
    try c.encode(curvesRed, forKey: .curvesRed)
    try c.encode(curvesGreen, forKey: .curvesGreen)
    try c.encode(curvesBlue, forKey: .curvesBlue)
    try c.encode(recipeVersion, forKey: .recipeVersion)
    try c.encode(rendererVersion, forKey: .rendererVersion)
  }
}

/// A named style preset plus intensity `0...100`. Style color science is our own
/// (parameterised Core Image chains — see `EditStyles`); only the *names* follow the
/// Photos-like vocabulary the brief asks for. Never an Apple LUT copy.
public struct StyleRecipe: Sendable, Codable, Equatable {
  public var style: EditStyle
  public var intensity: Int

  public init(style: EditStyle, intensity: Int = 100) {
    self.style = style
    self.intensity = min(100, max(0, intensity))
  }

  public var isNeutral: Bool { intensity == 0 || style == .none }
}

/// Crop/straighten/perspective. Only a plain rect + quarter turns + flips are
/// upstream-expressible; any straighten angle or perspective amount forces the
/// client-render path (see `isUpstreamExpressible`).
public struct CropRecipe: Sendable, Codable, Equatable {
  /// Normalized crop rectangle, origin upper-left, `0...1`. `nil` means full frame.
  public var rect: NormalizedRect?
  /// Free rotation in degrees (`-45...45`); quarter turns live in `quarterTurns`.
  public var straightenDegrees: Double
  /// Perspective correction `-100...100` (vertical / horizontal keystone).
  public var perspectiveVertical: Int
  public var perspectiveHorizontal: Int
  /// Clockwise quarter turns `0...3` — maps to upstream `rotate` (`angle = quarterTurns * 90`).
  public var quarterTurns: Int
  public var flipHorizontal: Bool
  public var flipVertical: Bool
  /// Aspect preset the rect was composed under (bookkeeping for the UI; `nil` = free).
  public var aspect: CropAspect?

  public init(
    rect: NormalizedRect? = nil,
    straightenDegrees: Double = 0,
    perspectiveVertical: Int = 0,
    perspectiveHorizontal: Int = 0,
    quarterTurns: Int = 0,
    flipHorizontal: Bool = false,
    flipVertical: Bool = false,
    aspect: CropAspect? = nil
  ) {
    self.rect = rect
    self.straightenDegrees = straightenDegrees
    self.perspectiveVertical = perspectiveVertical
    self.perspectiveHorizontal = perspectiveHorizontal
    self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    self.flipHorizontal = flipHorizontal
    self.flipVertical = flipVertical
    self.aspect = aspect
  }

  public var isUpstreamExpressible: Bool {
    straightenDegrees == 0 && perspectiveVertical == 0 && perspectiveHorizontal == 0
  }
}

public struct NormalizedRect: Sendable, Codable, Equatable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  /// Pixel rectangle for upstream `crop` params (origin top-left), clamped into `imageSize`.
  public func pixels(in imageSize: CGSize) -> CGRect {
    let r = CGRect(
      x: x * imageSize.width, y: y * imageSize.height,
      width: width * imageSize.width, height: height * imageSize.height)
    return r.intersection(CGRect(origin: .zero, size: imageSize))
  }
}

/// Crop orientation toggle for the Aspect list (WP-E E6): a preset ratio flips
/// under portrait orientation (16:9 <-> 9:16, 4:3 <-> 3:4, …).
public enum CropOrientation: String, Sendable, Codable, CaseIterable {
  case landscape, portrait
}

public enum CropAspect: String, Sendable, Codable, CaseIterable {
  case free
  case original = "Original"
  case square = "1:1"
  case sixteenNine = "16:9"
  case fourFive = "4:5"
  case fiveSeven = "5:7"
  case fourThree = "4:3"
  case threeFive = "3:5"
  case threeTwo = "3:2"
  case nineSixteen = "9:16"
  case custom = "Custom"

  /// Landscape ratio (width / height), or nil when the rect is unconstrained
  /// (free/custom) or source-defined (original).
  public var ratio: Double? {
    switch self {
    case .free, .original, .custom: return nil
    case .square: return 1
    case .sixteenNine: return 16.0 / 9.0
    case .fourFive: return 4.0 / 5.0
    case .fiveSeven: return 5.0 / 7.0
    case .fourThree: return 4.0 / 3.0
    case .threeFive: return 3.0 / 5.0
    case .threeTwo: return 3.0 / 2.0
    case .nineSixteen: return 9.0 / 16.0
    }
  }

  /// Ratio honoring the portrait/landscape toggle (portrait inverts the ratio).
  public func ratio(orientation: CropOrientation) -> Double? {
    guard let r = ratio else { return nil }
    switch orientation {
    case .landscape: return r >= 1 ? r : 1 / r
    case .portrait: return r >= 1 ? 1 / r : r
    }
  }

  /// Display name for the Aspect list (raw values stay stable for recipes).
  public var displayName: String {
    switch self {
    case .free: return "Freeform"
    case .original: return "Original"
    case .square: return "Square"
    case .custom: return "Custom…"
    default: return rawValue
    }
  }
}

/// Portrait depth effect. Requires depth/disparity data in the source file; the
/// renderer reports unavailability and the UIs disable the tab (brief section 4).
public struct PortraitRecipe: Sendable, Codable, Equatable {
  /// Aperture f-stop `1.4...16`; larger values = less blur.
  public var aperture: Double
  /// Focus point, normalized to the source image (`0...1`, origin upper-left).
  public var focus: NormalizedPoint

  public init(aperture: Double = 2.8, focus: NormalizedPoint = .init(x: 0.5, y: 0.5)) {
    self.aperture = min(16, max(1.4, aperture))
    self.focus = focus
  }
}

public struct NormalizedPoint: Sendable, Codable, Equatable {
  public var x: Double
  public var y: Double
  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// One Red-Eye correction target (D4): tap-to-select eye center, normalized
/// `0...1` with origin upper-left (same convention as `CropRecipe.rect`), plus
/// a correction radius as a fraction of image width. Values are clamped on
/// set so foreign/tap payloads can never push the crop math off-frame.
public struct RedEyeRegion: Sendable, Codable, Equatable {
  public var x: Double
  public var y: Double
  public var radius: Double

  public init(x: Double, y: Double, radius: Double = 0.04) {
    self.x = x
    self.y = y
    self.radius = radius
  }

  /// Value-clamped copy (used by `AdjustRecipe.init` so decoded regions are
  /// always frame-safe).
  public func clamped() -> RedEyeRegion {
    RedEyeRegion(
      x: min(1, max(0, x)),
      y: min(1, max(0, y)),
      radius: min(0.25, max(0.01, radius)))
  }
}

/// Markup marker. The vector ink itself is platform-owned: on iOS PencilKit strokes live in
/// the session and are flattened into the rendered upload; on macOS the vector elements ARE
/// serializable (`MacMarkupElement`) and round-trip through the recipe. Either way the
/// original asset bytes are never touched.
public struct MarkupRecipe: Sendable, Codable, Equatable {
  /// macOS vector elements (nil on iOS — see `hasFlattenedInk`).
  public var elements: [MacMarkupElement]?
  /// True when iOS PencilKit ink was flattened into the rendered upload.
  public var hasFlattenedInk: Bool

  public init(elements: [MacMarkupElement]? = nil, hasFlattenedInk: Bool = false) {
    self.elements = elements
    self.hasFlattenedInk = hasFlattenedInk
  }
}

/// Trim/mute/rotate for videos; mute + motion-trim + key-frame for Live Photos.
public struct VideoRecipe: Sendable, Codable, Equatable {
  /// Trim range in seconds from the start of the timeline; `nil` = full length.
  public var trimStart: Double?
  public var trimEnd: Double?
  public var muted: Bool
  /// Clockwise quarter turns applied at export.
  public var quarterTurns: Int
  /// Live Photo only: key-frame time in seconds (still image choice).
  public var livePhotoKeyFrame: Double?

  public init(
    trimStart: Double? = nil, trimEnd: Double? = nil, muted: Bool = false,
    quarterTurns: Int = 0, livePhotoKeyFrame: Double? = nil
  ) {
    self.trimStart = trimStart
    self.trimEnd = trimEnd
    self.muted = muted
    self.quarterTurns = ((quarterTurns % 4) + 4) % 4
    self.livePhotoKeyFrame = livePhotoKeyFrame
  }

  public var isEmpty: Bool {
    trimStart == nil && trimEnd == nil && !muted && quarterTurns == 0 && livePhotoKeyFrame == nil
  }
}
