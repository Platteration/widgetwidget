import Foundation
import UIKit

enum MemeImageProcessor {
    static let maxDimension: CGFloat = 2_048
    static let jpegQuality: CGFloat = 0.82

    static func prepare(_ data: Data) throws -> Data {
        guard let image = UIImage(data: data) else {
            throw MemeImageProcessingError.invalidImage
        }

        let targetSize = scaledSize(for: image.size)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }

        if rendered.hasAlpha, let png = rendered.pngData() {
            return png
        }

        guard let jpeg = rendered.jpegData(compressionQuality: jpegQuality) else {
            throw MemeImageProcessingError.encodingFailed
        }

        return jpeg
    }

    private static func scaledSize(for size: CGSize) -> CGSize {
        let longestSide = max(size.width, size.height)
        guard longestSide > maxDimension else {
            return size
        }

        let scale = maxDimension / longestSide
        return CGSize(
            width: max(1, (size.width * scale).rounded()),
            height: max(1, (size.height * scale).rounded())
        )
    }
}

private extension UIImage {
    var hasAlpha: Bool {
        guard let alphaInfo = cgImage?.alphaInfo else {
            return false
        }

        switch alphaInfo {
        case .first, .last, .premultipliedFirst, .premultipliedLast:
            return true
        default:
            return false
        }
    }
}

enum MemeImageProcessingError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "That image could not be decoded."
        case .encodingFailed:
            return "That image could not be prepared for the widget."
        }
    }
}
