package com.hearth.app.ui

import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.hearth.app.ui.theme.HearthColors
import com.hearth.core.models.HearthState

/**
 * The quiet strip above the composer: who in the house is doing what, right
 * now. Ported from the iOS `HouseStatusBar`.
 *
 * It renders NOTHING when the house is idle. The resting screen stays calm and
 * the bar never reserves space it is not using, which is why this returns
 * early rather than drawing an empty row.
 */
@Composable
fun HouseStatusBar(
    state: HearthState,
    personaName: String,
    activeTools: List<String>,
    /** The cover screen: the same line, with less room around it. */
    compact: Boolean = false,
) {
    val label = statusLabel(state, personaName, activeTools) ?: return

    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(
                horizontal = if (compact) 12.dp else 20.dp,
                vertical = if (compact) 1.dp else 4.dp,
            ),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        PulsingDot()
        Text(
            label,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}

/**
 * The tool line wins over the generic persona state: "Checking the weather"
 * is strictly more informative than "Sulivan is thinking".
 */
private fun statusLabel(
    state: HearthState,
    personaName: String,
    activeTools: List<String>,
): String? {
    toolLabel(activeTools)?.let { return "$it..." }
    return when (state) {
        HearthState.THINKING -> "$personaName is thinking..."
        HearthState.SPEAKING -> "$personaName is speaking"
        HearthState.LISTENING -> "Listening"
        else -> null
    }
}

/**
 * House language for the tools, mirroring the iOS table. An unmapped tool
 * still says something honest rather than going silent.
 */
private val TOOL_LABELS: List<Pair<String, String>> = listOf(
    "consult_memory" to "Consulting Selene in the library",
    "recall" to "Leafing through memory",
    "remember" to "Leafing through memory",
    "forge_card" to "Commissioning the workshop",
    "list_cards" to "Checking the workshop inventory",
    "generate_image" to "Setting up the easel",
    "check_image" to "Checking the easel",
    "get_weather" to "Checking the weather",
    "web_search" to "Looking that up",
    "news_headlines" to "Looking that up",
    "set_timer" to "Minding the timers",
    "list_timers" to "Minding the timers",
    "cancel_timer" to "Minding the timers",
)

internal fun toolLabel(names: List<String>): String? {
    for (name in names) {
        TOOL_LABELS.firstOrNull { name.startsWith(it.first) }?.let { return it.second }
    }
    return names.firstOrNull()?.let { "Working: $it" }
}

/** The small fennec dot that breathes while something is running. */
@Composable
private fun PulsingDot() {
    val transition = rememberInfiniteTransition(label = "dot")
    val alpha by transition.animateFloat(
        initialValue = 1f,
        targetValue = 0.35f,
        animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
        label = "dotAlpha",
    )
    androidx.compose.foundation.layout.Box(
        modifier = Modifier
            .size(6.dp)
            .alpha(alpha)
            .clip(CircleShape)
            .background(HearthColors.fennec)
    )
}
