import CoreImage
import Foundation

/// Off-main filmstrip thumbnails for the WP-E Adjust section smart sliders (E3/E4).
///
/// Pure and `Sendable`: takes a `CIImage`, renders one small thumb per strength by
/// writing the strength into `keyPath`, and returns `CGImage`s. Callers invoke it
/// from a detached task and publish the results; nothing here touches the main
/// thread (the renderer is `@unchecked Sendable` and `CIContext` is thread-safe).
public enum EditFilmstrip {
  /// Renders one thumb per entry in `strengths` at `maxPixel` working size.
  public static func thumbs(
    source: CIImage,
    base: EditRecipe,
    keyPath: WritableKeyPath<AdjustRecipe, Int>,
    strengths: [Int],
    maxPixel: Int = 128
  ) -> [CGImage?] {
    thumbs(
      source: source,
      recipes: strengths.map { strength in
        var recipe = base
        recipe.adjust[keyPath: keyPath] = strength
        return recipe
      },
      maxPixel: maxPixel)
  }

  /// Renders one thumb per recipe. The caller precomputes the per-strength recipes
  /// (key paths are not `Sendable`, so they must not cross the isolation boundary —
  /// only `Sendable` recipes travel into the detached task).
  public static func thumbs(
    source: CIImage, recipes: [EditRecipe], maxPixel: Int = 128
  ) -> [CGImage?] {
    let renderer = EditRenderer()
    return recipes.map { recipe in
      renderer.cgImage(source: source, recipe: recipe, previewMaxPixel: maxPixel)
    }
  }
}
