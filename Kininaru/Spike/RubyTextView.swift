#if DEBUG
import CoreText
import SwiftUI
import UIKit

enum RubyAttributedString {
    static func make(tokens: [FuriganaToken], baseColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let baseFont = UIFont.preferredFont(forTextStyle: .title2)
        let rubyFont = UIFont.systemFont(ofSize: 12)
        for token in tokens {
            let piece = NSMutableAttributedString(string: token.surface)
            let range = NSRange(location: 0, length: piece.length)
            guard range.length > 0 else { continue }
            piece.addAttribute(.font, value: baseFont, range: range)
            piece.addAttribute(.foregroundColor, value: baseColor, range: range)
            piece.addAttribute(
                NSAttributedString.Key(kCTForegroundColorAttributeName as String),
                value: baseColor.cgColor,
                range: range
            )
            let reading = token.hiragana.isEmpty ? token.latin : token.hiragana
            if !reading.isEmpty && !token.surface.allSatisfy({ $0.isPunctuation || $0.isWhitespace }) {
                let attributes = [
                    kCTFontAttributeName: rubyFont,
                    kCTForegroundColorAttributeName: baseColor.cgColor,
                ] as CFDictionary
                let ruby = CTRubyAnnotationCreateWithAttributes(
                    CTRubyAlignment.auto,
                    CTRubyOverhang.auto,
                    CTRubyPosition.before,
                    reading as CFString,
                    attributes
                )
                piece.addAttribute(
                    NSAttributedString.Key(kCTRubyAnnotationAttributeName as String),
                    value: ruby,
                    range: range
                )
            }
            result.append(piece)
        }
        let full = NSRange(location: 0, length: result.length)
        if full.length > 0 {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 18
            paragraph.minimumLineHeight = 44
            result.addAttribute(.paragraphStyle, value: paragraph, range: full)
        }
        return result
    }
}

final class RubyDrawView: UIView {
    var attributedText: NSAttributedString = NSAttributedString() {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) {
        nil
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 88)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard attributedText.length > 0, let context = UIGraphicsGetCurrentContext() else { return }
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let path = CGPath(rect: bounds.insetBy(dx: 4, dy: 6), transform: nil)
        let framesetter = CTFramesetterCreateWithAttributedString(attributedText)
        let frame = CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: attributedText.length),
            path,
            nil
        )
        CTFrameDraw(frame, context)
        context.restoreGState()
    }
}

struct RubyLine: UIViewRepresentable {
    var tokens: [FuriganaToken]

    func makeUIView(context: Context) -> RubyDrawView {
        RubyDrawView()
    }

    func updateUIView(_ uiView: RubyDrawView, context: Context) {
        uiView.attributedText = RubyAttributedString.make(tokens: tokens, baseColor: .label)
    }
}
#endif
