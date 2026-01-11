import SwiftUI

struct TopBarView: View {
    @Binding var searchText: String
    
    var body: some View {
        HStack {
            Text("Cognote")
                .font(.title2)
                .foregroundColor(.white) // Reference has white text on dark background
                .padding(.leading, 20)
            
            Spacer()
            
            HStack {
                TextField("Search resources...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .padding(8)
                
                Button(action: {
                    // Search action
                }) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.white)
                }
                .padding(.trailing, 8)
            }
            .frame(width: 300)
            .background(Color.white.opacity(0.1)) // Dark transparent background
            .cornerRadius(4)
            .padding(.trailing, 20)
        }
        .frame(height: 60)
        .background(Color(hex: "1a1a1a")) // Dark background like reference
    }
}


