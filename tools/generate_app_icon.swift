#!/usr/bin/env swift
import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

// 게임의 Theme.display와 같은 번들 글꼴로 앱 아이콘을 만든다.
// 사용: swift tools/generate_app_icon.swift
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let fontURL = root.appendingPathComponent("Ccutu/Resources/Fonts/BlackHanSans-Regular.ttf")
let output = root.appendingPathComponent("Ccutu/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png")
guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(fontURL as CFURL) as? [CTFontDescriptor],
      let descriptor = descriptors.first,
      let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                              bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
    fatalError("아이콘 글꼴·그리기 컨텍스트를 만들지 못했습니다.")
}
let font = CTFontCreateWithFontDescriptor(descriptor, 360, nil)
precondition(CTFontCopyPostScriptName(font) as String == "BlackHanSans-Regular")
context.setFillColor(red: 0, green: 122.0 / 255, blue: 1, alpha: 1)
context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024))
context.setFillColor(CGColor.white)
for (top, width) in [(160.0, 560.0), (256.0, 400.0), (352.0, 240.0)] {
    context.addPath(CGPath(roundedRect: CGRect(x: 160, y: 1024 - top - 56, width: width, height: 56),
                           cornerWidth: 28, cornerHeight: 28, transform: nil))
    context.fillPath()
}
let line = CTLineCreateWithAttributedString(NSAttributedString(string: "모투", attributes: [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
    NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor.white,
]))
// 글꼴 힌팅으로 가장자리가 1px 이동하지 않게 글자 외곽 경로를 직접 그린다.
let wordPath = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
    for index in 0..<count {
        if let path = CTFontCreatePathForGlyph(font, glyphs[index], nil) {
            wordPath.addPath(path, transform: CGAffineTransform(translationX: positions[index].x, y: positions[index].y))
        }
    }
}
let bounds = wordPath.boundingBoxOfPath
let area = CGRect(x: 160, y: 168, width: 704, height: 280)
let scale = min(area.width / bounds.width, area.height / bounds.height)
// 글자 외곽의 왼쪽을 세 줄의 시작점(x=160)에 맞춘다.
context.translateBy(x: area.minX - bounds.minX * scale, y: area.midY - bounds.midY * scale)
context.scaleBy(x: scale, y: scale)
context.addPath(wordPath)
context.fillPath()
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("아이콘 PNG를 만들지 못했습니다.")
}
CGImageDestinationAddImage(destination, image, nil)
precondition(CGImageDestinationFinalize(destination), "아이콘 PNG를 저장하지 못했습니다.")
print("Generated \(output.path) · \(CTFontCopyPostScriptName(font)) · 1024×1024")
