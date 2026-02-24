import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [NoteItem]
    @State private var selectedItem: NoteItem?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        FileSystemView(modelContext: modelContext)
    }
}
