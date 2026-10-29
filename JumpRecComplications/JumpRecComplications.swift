import SwiftUI
import WidgetKit

struct JumpRecComplicationEntry: TimelineEntry {
    let date: Date
}

struct JumpRecComplicationProvider: TimelineProvider {
    func placeholder(in _: Context) -> JumpRecComplicationEntry {
        JumpRecComplicationEntry(date: .now)
    }

    func getSnapshot(in _: Context, completion: @escaping (JumpRecComplicationEntry) -> Void) {
        completion(JumpRecComplicationEntry(date: .now))
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<JumpRecComplicationEntry>) -> Void) {
        // The launcher has no changing data, so it does not need scheduled refreshes.
        completion(Timeline(entries: [JumpRecComplicationEntry(date: .now)], policy: .never))
    }
}

struct JumpRecComplicationView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Label {
                    Text("JumpRec")
                } icon: {
                    Image("JumpRecComplicationIcon")
                        .renderingMode(.template)
                }
            case .accessoryRectangular:
                HStack {
                    appIcon
                    VStack(alignment: .leading) {
                        Text("JumpRec")
                            .font(.headline)
                        Text("Open JumpRec")
                            .font(.caption)
                    }
                }
            case .accessoryCorner:
                appIcon
                    .widgetLabel { Text("JumpRec") }
            default:
                ZStack {
                    AccessoryWidgetBackground()
                    appIcon
                }
            }
        }
        .accessibilityLabel("Open JumpRec")
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var appIcon: some View {
        Image("JumpRecComplicationIcon")
            .resizable()
            .scaledToFit()
            .frame(width: 28, height: 28)
            .widgetAccentable()
    }
}

struct JumpRecComplications: Widget {
    let kind = "JumpRecComplications"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: JumpRecComplicationProvider()) { _ in
            JumpRecComplicationView()
        }
        .configurationDisplayName("JumpRec")
        .description("Open JumpRec to start a jump rope workout.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

#Preview(as: .accessoryCircular) {
    JumpRecComplications()
} timeline: {
    JumpRecComplicationEntry(date: .now)
}

#Preview(as: .accessoryRectangular) {
    JumpRecComplications()
} timeline: {
    JumpRecComplicationEntry(date: .now)
}

#Preview(as: .accessoryInline) {
    JumpRecComplications()
} timeline: {
    JumpRecComplicationEntry(date: .now)
}

#Preview(as: .accessoryCorner) {
    JumpRecComplications()
} timeline: {
    JumpRecComplicationEntry(date: .now)
}
