import SwiftUI

struct TopBarView: View {
    @Binding var searchText: String
    var onSettings: (() -> Void)? = nil
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        HStack(spacing: 12) {
            if horizontalSizeClass != .compact {
                Text("MiniClone")
                    .font(.title2)
                    .foregroundColor(.white)
                    .padding(.leading, 20)
            }
            
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
            .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 300)
            .background(Color.white.opacity(0.1))
            .cornerRadius(4)
            .padding(.horizontal, horizontalSizeClass == .compact ? 12 : 0)
            
            if horizontalSizeClass == .compact {
                Button(action: { onSettings?() }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.white)
                }
                .padding(.trailing, 12)
            } else {
                Spacer()
                    .frame(width: 20)
            }
        }
        .frame(height: 60)
        .background(appTheme.chromeBackground)
    }
}
