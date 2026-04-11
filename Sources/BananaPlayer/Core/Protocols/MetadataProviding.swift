import Foundation

protocol MetadataProviding: Sendable {
    func readMetadata(for fileURL: URL) -> TrackMetadata
}
