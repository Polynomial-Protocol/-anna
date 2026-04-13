import Foundation
import NaturalLanguage

/// Generates 512-dimensional sentence embeddings using Apple's built-in NLEmbedding.
/// Zero external dependencies, runs 100% on-device, free.
actor EmbeddingService {
    private let model: NLEmbedding?

    init() {
        self.model = NLEmbedding.sentenceEmbedding(for: .english)
    }

    var isAvailable: Bool { model != nil }

    /// Generate an embedding vector for the given text.
    func embed(_ text: String) -> [Float]? {
        guard let model else { return nil }
        guard let vector = model.vector(for: text) else { return nil }
        return vector.map { Float($0) }
    }

    /// Compute cosine similarity between two vectors.
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        var magA: Float = 0
        var magB: Float = 0
        for i in 0..<a.count {
            dot += a[i] * b[i]
            magA += a[i] * a[i]
            magB += b[i] * b[i]
        }
        let denom = sqrt(magA) * sqrt(magB)
        guard denom > 0 else { return 0 }
        return dot / denom
    }

    /// Find the top-K most similar entries from a set of pre-computed embeddings.
    func topK(query: String, entries: [(id: Int64, embedding: [Float])], k: Int = 5) -> [(id: Int64, score: Float)] {
        guard let queryVec = embed(query) else { return [] }
        var scored = entries.map { (id: $0.id, score: cosineSimilarity(queryVec, $0.embedding)) }
        scored.sort { $0.score > $1.score }
        return Array(scored.prefix(k))
    }
}
