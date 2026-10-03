import SwiftUI

@MainActor
final class CandidateModel: ObservableObject {
    @Published var candidates: [Candidate] = []
    @Published var selectedIndex: Int = 0
}

struct CandidateView: View {
    @ObservedObject var model: CandidateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.candidates.enumerated()), id: \.offset) { idx, cand in
                row(index: idx, candidate: cand)
            }
        }
        .padding(6)
        .background(.background)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .allowsHitTesting(false)
    }

    private func row(index: Int, candidate: Candidate) -> some View {
        HStack(spacing: 8) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 14, alignment: .trailing)
            Text(candidate.output)
                .font(.system(size: 16))
                .foregroundStyle(index == model.selectedIndex ? Color.white : Color.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(index == model.selectedIndex ? Color.accentColor : Color.clear)
        )
    }
}
