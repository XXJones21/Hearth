//
//  Hearth_WidgetLiveActivity.swift
//  Hearth Widget
//
//  Created by Joshua Jones on 8/8/26.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct Hearth_WidgetAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct Hearth_WidgetLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: Hearth_WidgetAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension Hearth_WidgetAttributes {
    fileprivate static var preview: Hearth_WidgetAttributes {
        Hearth_WidgetAttributes(name: "World")
    }
}

extension Hearth_WidgetAttributes.ContentState {
    fileprivate static var smiley: Hearth_WidgetAttributes.ContentState {
        Hearth_WidgetAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: Hearth_WidgetAttributes.ContentState {
         Hearth_WidgetAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: Hearth_WidgetAttributes.preview) {
   Hearth_WidgetLiveActivity()
} contentStates: {
    Hearth_WidgetAttributes.ContentState.smiley
    Hearth_WidgetAttributes.ContentState.starEyes
}
