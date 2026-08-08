//
//  Hearth_WidgetBundle.swift
//  Hearth Widget
//
//  Created by Joshua Jones on 8/8/26.
//

import WidgetKit
import SwiftUI

@main
struct Hearth_WidgetBundle: WidgetBundle {
    var body: some Widget {
        Hearth_Widget()
        Hearth_WidgetControl()
        Hearth_WidgetLiveActivity()
    }
}
