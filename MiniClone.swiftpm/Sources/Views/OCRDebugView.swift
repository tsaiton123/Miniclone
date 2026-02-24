import SwiftUI
import SwiftData

struct OCRDebugView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var allNotes: [NoteItem]
    @State private var ocrData: [String: String] = [:]
    
    // Helper to find a note name by its ID string
    private func noteName(for idString: String) -> String {
        let parts = idString.components(separatedBy: "_")
        let noteIdString = parts.first ?? idString
        let pageSuffix = parts.count > 1 ? " (Page \(Int(parts[1]) ?? 0 + 1))" : ""
        
        if let uuid = UUID(uuidString: noteIdString),
           let note = allNotes.first(where: { $0.id == uuid }) {
            return note.title + pageSuffix
        }
        return "Unknown Note" + pageSuffix
    }
    
    var body: some View {
        List {
            Section(header: Text("Indexed Notes"), footer: Text("This shows the raw text extracted from your handwritten pages. Names are resolved live from your note database.")) {
                if ocrData.isEmpty {
                    Text("No notes indexed yet.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(Array(ocrData.keys).sorted(), id: \.self) { pageId in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(noteName(for: pageId))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button {
                                    UIPasteboard.general.string = ocrData[pageId]
                                } label: {
                                    Image(systemName: "doc.on.doc")
                                        .font(.caption)
                                }
                            }
                            
                            Text("ID: \(pageId.prefix(8))...")
                                .font(.caption2)
                                .monospaced()
                                .foregroundColor(.secondary)
                            
                            Text(ocrData[pageId] ?? "")
                                .font(.system(.body, design: .monospaced))
                                .padding(8)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(4)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("OCR Debug")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            ocrData = HandwritingIndexService.shared.getFullTextIndex()
        }
    }
}

#Preview {
    NavigationView {
        OCRDebugView()
    }
}
