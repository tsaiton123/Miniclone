import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [NoteItem]
    @State private var selectedItem: NoteItem?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedItem) {
                ForEach(items) { item in
                    NavigationLink(value: item) {
                        Text(item.title)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
                ToolbarItem {
                    Button(action: addItem) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let item = selectedItem {
                BlackboardView(note: item)
                    .id(item.id) // Force refresh when switching
            } else {
                Text("Select a note")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func addItem() {
        withAnimation {
            let newItem = NoteItem(title: "New Note")
            modelContext.insert(newItem)
            selectedItem = newItem
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}
