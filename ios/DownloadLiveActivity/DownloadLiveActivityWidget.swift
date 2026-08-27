import ActivityKit
import WidgetKit
import SwiftUI
import UIKit

@available(iOS 16.1, *)
struct DownloadLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
            LockScreenDownloadView(context: context)
                .activityBackgroundTint(.clear)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DownloadIcon(fileName: context.attributes.iconFileName, size: 42)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.appName).font(.headline).lineLimit(1)
                        Text(context.state.statusText).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ProgressControl(context: context, size: 48)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(ByteCountFormatter.string(fromByteCount: context.state.downloadedBytes, countStyle: .file))
                        Spacer()
                        if context.state.totalBytes > 0 {
                            Text(ByteCountFormatter.string(fromByteCount: context.state.totalBytes, countStyle: .file))
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            } compactLeading: {
                DownloadIcon(fileName: context.attributes.iconFileName, size: 24)
            } compactTrailing: {
                CompactProgress(progress: context.state.progress, completed: context.state.status == "completed")
            } minimal: {
                CompactProgress(progress: context.state.progress, completed: context.state.status == "completed")
            }
            .keylineTint(.accentColor)
        }
    }
}

@available(iOS 16.1, *)
private struct LockScreenDownloadView: View {
    let context: ActivityViewContext<DownloadActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            DownloadIcon(fileName: context.attributes.iconFileName, size: 54)
            VStack(alignment: .leading, spacing: 5) {
                Text(context.attributes.appName)
                    .font(.headline.weight(.semibold))
                    .lineLimit(1)
                Text(context.state.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if context.state.totalBytes > 0 {
                    Text("\(Int((context.state.progress * 100).rounded()))%")
                        .font(.caption.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            ProgressControl(context: context, size: 58)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .downloadGlassSurface()
    }
}

@available(iOS 16.1, *)
private struct ProgressControl: View {
    let context: ActivityViewContext<DownloadActivityAttributes>
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, context.state.progress)))
                .stroke(.tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if context.state.status == "completed" {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.28, weight: .bold))
                    .foregroundStyle(.tint)
            } else if context.state.status == "failed" || context.state.status == "cancelled" {
                Image(systemName: "xmark")
                    .font(.system(size: size * 0.25, weight: .bold))
                    .foregroundStyle(.secondary)
            } else if #available(iOS 17.0, *) {
                Button(intent: DownloadControlIntent(downloadId: context.attributes.downloadId, action: context.state.isPaused ? "resume" : "pause")) {
                    Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: size * 0.24, weight: .bold))
                        .frame(width: size * 0.58, height: size * 0.58)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: size * 0.24, weight: .bold))
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

private struct DownloadIcon: View {
    let fileName: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let image = loadImage() {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous).fill(.secondary.opacity(0.12))
                    Image(systemName: "arrow.down.app.fill").font(.system(size: size * 0.44, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
    }

    private func loadImage() -> UIImage? {
        guard let fileName,
              let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: BoomaShared.appGroup) else { return nil }
        return UIImage(contentsOfFile: container.appendingPathComponent(fileName).path)
    }
}

private struct CompactProgress: View {
    let progress: Double
    let completed: Bool
    var body: some View {
        ZStack {
            Circle().stroke(.secondary.opacity(0.25), lineWidth: 2.5)
            Circle().trim(from: 0, to: max(0.001, min(1, progress))).stroke(.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
            if completed { Image(systemName: "checkmark").font(.caption2.bold()) }
        }
        .frame(width: 22, height: 22)
    }
}

private extension View {
    @ViewBuilder
    func downloadGlassSurface() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        } else {
            self.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }
}
