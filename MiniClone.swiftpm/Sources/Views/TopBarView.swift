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
                    .font(.system(size: 20, weight: .regular, design: .serif))
                    .foregroundColor(.white)
                    .padding(.leading, 20)
            }
            
            Spacer()
            
            HStack {
                TextField("Search resources...", text: $searchText)
                    .textFieldStyle(PlainTextFieldStyle())
                    .foregroundColor(.white)
                    .font(.system(size: 13))
                    .padding(8)
                
                Button(action: {
                    if !searchText.isEmpty {
                        searchText = ""
                    }
                }) {
                    Image(systemName: searchText.isEmpty ? "magnifyingglass" : "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 13))
                }
                .padding(.trailing, 8)
                
                Divider()
                    .background(Color.white.opacity(0.3))
                    .frame(height: 18)
                
                Button(action: {
                    NotificationCenter.default.post(name: NSNotification.Name("ShowSearchByDraw"), object: nil)
                }) {
                    Image(systemName: "scribble")
                        .foregroundColor(.white.opacity(0.7))
                        .font(.system(size: 13))
                }
                .padding(.trailing, 8)
            }
            .frame(maxWidth: horizontalSizeClass == .compact ? .infinity : 280)
            .background(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .cornerRadius(4)
            .padding(.horizontal, horizontalSizeClass == .compact ? 12 : 0)
            
            if horizontalSizeClass == .compact {
                Button(action: { onSettings?() }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 18))
                        .foregroundColor(.white.opacity(0.7))
                }
                .padding(.trailing, 12)
            } else {
                Spacer()
                    .frame(width: 20)
            }
        }
        .frame(height: 56)
        .background(appTheme.chromeBackground)
    }
}
