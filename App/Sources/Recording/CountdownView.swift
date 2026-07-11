// App/Sources/Recording/CountdownView.swift
import SwiftUI

struct CountdownView: View {
    let value: Int

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.7))
                .frame(width: 120, height: 120)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 6)

            Text("\(value)")
                .font(.system(size: 72, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .id(value)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.5).combined(with: .opacity),
                    removal: .scale(scale: 0.8).combined(with: .opacity)
                ))
        }
        .frame(width: 120, height: 120)
    }
}
