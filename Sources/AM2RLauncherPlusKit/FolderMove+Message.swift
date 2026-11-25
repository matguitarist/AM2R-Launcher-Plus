import FileKit
import Foundation

/// The words for a failed data folder move (S-013). The move itself is FileKit's `FolderMove`.
extension FolderMove.Failure {
    public var message: String {
        switch self {
        case .destinationExists(let name): "That folder already has an item named “\(name)”. Choose another folder."
        case .insideItself: "Choose a folder outside the current data folder."
        case .notEnoughSpace(let needed, let available):
            "Not enough space: the data needs \(needed.formatted(.byteCount(style: .file))), the disk has \(available.formatted(.byteCount(style: .file)))."
        case .copyFailed: "Unable to copy the data. The old folder is unchanged."
        case .verifyFailed(let path): "The copy doesn't match the original (\(path)). The old folder is unchanged."
        }
    }
}
