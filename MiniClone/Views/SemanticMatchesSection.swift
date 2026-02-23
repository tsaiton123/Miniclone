import SwiftUI
import SwiftData

/// Shows semantic (MobileCLIP embedding) search results alongside the
/// standard keyword results in the dashboard.
struct SemanticMatchesSection: View {
    let results: [SemanticSearchResult]
    let allItems: [NoteItem]
    let isSearching: Bool
    let onSelect: (NoteItem) -> Void
    
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader
            
            if isSearching {
                loadingRow
            } else {
                ForEach(results) { result in
                    if let note = note(for: result) {
                        SemanticMatchCard(
                            title: note.title,
                            score: result.score,
                            tint: appTheme.accentColor
                        ) {
                            onSelect(note)
                        }
                    }
                }
            }
        }
    }
    
    // MARK: - Private Helpers
    
    private var sectionHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkle.magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(appTheme.accentColor)
            Text("Semantic Matches")
                .font(.headline)
            Spacer()
            Text("powered by MobileCLIP")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }
    
    private var loadingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Searching…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
    }
    
    private func note(for result: SemanticSearchResult) -> NoteItem? {
        guard let uuid = UUID(uuidString: result.pageId) else { return nil }
        return allItems.first { $0.id == uuid && !$0.isFolder }
    }
}

// MARK: - SemanticMatchCard

struct SemanticMatchCard: View {
    let title: String
    let score: Float
    let tint: Color
    let onTap: () -> Void
    
    @Environment(\.appTheme) private var appTheme
    
    var scorePercent: Int { Int((score * 100).rounded()) }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(tint.opacity(0.12))
                        .frame(width: 48, height: 48)
                    Image(systemName: "sparkles")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(tint)
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                    Text("Matched handwriting")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
                // Similarity badge
                Text("\(scorePercent)%")
                    .font(.caption.bold())
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(
                        Capsule()
                            .fill(tint.opacity(0.15))
                    )
                    .foregroundColor(tint)
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 3)
            )
            .padding(.horizontal, 20)
        }
        .buttonStyle(.plain)
    }
}
