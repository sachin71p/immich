import Testing
@testable import Media

@Suite struct MediaFormatTests {
  @Test("[A2-06] still formats classify by extension; RAW/HEIC must view the original")
  func stillClassification() {
    #expect(MediaFormatInfo.classify(fileName: "IMG_001.JPG").kind == .jpeg)
    #expect(MediaFormatInfo.classify(fileName: "shot.png").kind == .png)
    #expect(MediaFormatInfo.classify(fileName: "anim.webp").kind == .webp)
    #expect(MediaFormatInfo.classify(fileName: "IMG_002.HEIC").kind == .heic)
    #expect(MediaFormatInfo.classify(fileName: "IMG_002.HEIC").shouldViewOriginal)
    for raw in ["frame.dng", "frame.ARW", "frame.CR3", "frame.NEF", "frame.RW2"] {
      let info = MediaFormatInfo.classify(fileName: raw)
      #expect(info.kind == .raw, "\(raw)")
      #expect(info.shouldViewOriginal, "\(raw)")
    }
    #expect(MediaFormatInfo.classify(fileName: "clip.mov").kind == .video)
    #expect(MediaFormatInfo.classify(fileName: "clip.mov").shouldViewOriginal)
    #expect(MediaFormatInfo.classify(fileName: "note.txt").kind == .other)
    #expect(MediaFormatInfo.classify(fileName: "note.txt").shouldViewOriginal == false)
  }

  @Test("[A2-06] the viewer HDR flag comes from the EXIF profile description")
  func dynamicRangeFlag() {
    #expect(
      MediaFormatInfo.classify(fileName: "a.heic", profileDescription: "HLG / BT.2100").dynamicRange
        == .hdr)
    #expect(
      MediaFormatInfo.classify(fileName: "a.heic", profileDescription: "SMPTE ST 2084").dynamicRange
        == .hdr)
    #expect(
      MediaFormatInfo.classify(fileName: "a.heic", profileDescription: "Dolby Vision").dynamicRange
        == .hdr)
    #expect(MediaFormatInfo.classify(fileName: "a.heic", profileDescription: "sRGB").dynamicRange == .sdr)
    #expect(MediaFormatInfo.classify(fileName: "a.heic").dynamicRange == .sdr)
    #expect(MediaFormatInfo.classify(fileName: "a.jpg").dynamicRange == .sdr)
  }
}
