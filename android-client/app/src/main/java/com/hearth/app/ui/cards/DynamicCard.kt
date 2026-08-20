package com.hearth.app.ui.cards

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.hearth.core.cards.CardDescriptor
import kotlinx.coroutines.delay
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.max

/**
 * The card registry, ported from the iOS `DynamicComponent`.
 *
 * Every prop name here comes from the house's own contract
 * (backend/harness/valar/tools/card_catalog.yaml), not from guessing at the
 * Swift: the catalog is the server-side source of truth for what each card
 * carries, and reading it is why these fields match on the first try.
 *
 * An unknown type renders NOTHING. That is the forward-compatibility half of
 * the tolerant decode: the house can ship a card this build has never heard
 * of, and the client shows the rest of the conversation rather than an error.
 */
@Composable
fun DynamicCard(
    card: CardDescriptor,
    modifier: Modifier = Modifier,
    onChoice: (String) -> Unit = {},
    onPermission: (String, Boolean) -> Unit = { _, _ -> },
) {
    when (card.type) {
        CardDescriptor.CLOCK -> ClockCard(card, modifier)
        CardDescriptor.WEATHER -> WeatherCard(card, modifier)
        CardDescriptor.TIMER -> TimerCard(card, modifier)
        CardDescriptor.BRIEF_TEXT -> BriefTextCard(card, modifier)
        CardDescriptor.CAPTIONS -> CaptionsCard(card, modifier)
        CardDescriptor.GENERATED_VIEW -> GeneratedViewCard(card, modifier)
        CardDescriptor.TERMINAL -> TerminalCard(card, modifier)
        CardDescriptor.IMAGE -> ImageCard(card, modifier)
        CardDescriptor.PERMISSION -> PermissionCard(card, modifier, onPermission)
        CardDescriptor.CHOICE -> ChoiceCard(card, modifier, onChoice)
        // slideshow needs image loading; it arrives with the image work.
        else -> Unit
    }
}

/** The shared chrome every card sits in. */
@Composable
private fun CardSurface(
    modifier: Modifier = Modifier,
    eyebrow: String? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Surface(
        shape = RoundedCornerShape(18.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.padding(16.dp)) {
            eyebrow?.let {
                Text(
                    it.uppercase(),
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(bottom = 6.dp),
                )
            }
            content()
        }
    }
}

// ---- the cards ------------------------------------------------------------

@Composable
private fun ClockCard(card: CardDescriptor, modifier: Modifier) {
    // The house may send time and date, but a clock that does not tick is
    // worse than no clock, so a card without them keeps its own time.
    val now by produceState(initialValue = Date()) {
        while (true) {
            value = Date()
            delay(20_000)
        }
    }
    val time = card.str("time").ifEmpty {
        SimpleDateFormat("h:mm a", Locale.getDefault()).format(now)
    }
    val date = card.str("date").ifEmpty {
        SimpleDateFormat("EEEE, MMM d", Locale.getDefault()).format(now)
    }
    CardSurface(modifier) {
        Column(
            modifier = Modifier.fillMaxWidth(),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(time, style = MaterialTheme.typography.displaySmall)
            Text(
                date,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun WeatherCard(card: CardDescriptor, modifier: Modifier) {
    CardSurface(modifier, eyebrow = card.str("day", "today")) {
        Text(
            card.str("location"),
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp),
            verticalAlignment = Alignment.Bottom,
            horizontalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(card.str("temp"), style = MaterialTheme.typography.displaySmall)
            Text(
                card.str("condition"),
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(bottom = 6.dp),
            )
        }
        val high = card.str("high")
        val low = card.str("low")
        if (high.isNotEmpty() || low.isNotEmpty()) {
            Text(
                listOfNotNull(
                    high.ifEmpty { null }?.let { "High $it" },
                    low.ifEmpty { null }?.let { "Low $it" },
                ).joinToString("   "),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun TimerCard(card: CardDescriptor, modifier: Modifier) {
    // fire_at is epoch seconds; the countdown runs CLIENT side so the card
    // stays live between emits rather than freezing at whatever the house
    // last said.
    val now by produceState(initialValue = System.currentTimeMillis()) {
        while (true) {
            value = System.currentTimeMillis()
            delay(1000)
        }
    }
    val timers = card.objList("timers")
    if (timers.isEmpty()) return
    CardSurface(modifier, eyebrow = "Timers") {
        for (timer in timers) {
            val label = timer.optString("label").ifEmpty { "Timer" }
            val fireAt = timer.optLong("fire_at") * 1000
            val remaining = max(0L, (fireAt - now) / 1000)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                Text(label, style = MaterialTheme.typography.bodyLarge)
                Text(
                    "%d:%02d".format(remaining / 60, remaining % 60),
                    style = MaterialTheme.typography.titleMedium,
                    color = MaterialTheme.colorScheme.primary,
                )
            }
        }
    }
}

@Composable
private fun BriefTextCard(card: CardDescriptor, modifier: Modifier) {
    CardSurface(modifier, eyebrow = card.str("title").ifEmpty { null }) {
        Text(card.str("body"), style = MaterialTheme.typography.bodyMedium)
    }
}

@Composable
private fun CaptionsCard(card: CardDescriptor, modifier: Modifier) {
    CardSurface(modifier) {
        Text(
            card.str("text"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun GeneratedViewCard(card: CardDescriptor, modifier: Modifier) {
    // The fallback carrier: text, stats, stat rows and dividers in a few
    // templates. Caps match iOS (12 sections, 4 stats a row) so a runaway
    // payload cannot push the persona off the stage.
    CardSurface(modifier, eyebrow = card.str("title").ifEmpty { null }) {
        for (section in card.objList("sections").take(12)) {
            when (section.optString("kind")) {
                "text" -> Text(
                    section.optString("text"),
                    style = MaterialTheme.typography.bodyMedium,
                    modifier = Modifier.padding(vertical = 4.dp),
                )

                "stat" -> StatBlock(
                    label = section.optString("label"),
                    value = section.optString("value"),
                )

                "stat_row" -> Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    val stats = section.optJSONArray("stats")
                    val count = minOf(stats?.length() ?: 0, 4)
                    for (i in 0 until count) {
                        val stat = stats?.optJSONObject(i) ?: continue
                        StatBlock(
                            label = stat.optString("label"),
                            value = stat.optString("value"),
                        )
                    }
                }

                "divider" -> HorizontalDivider(
                    modifier = Modifier.padding(vertical = 8.dp)
                )

                // image sections arrive with the image work.
                else -> Unit
            }
        }
    }
}

@Composable
private fun StatBlock(label: String, value: String) {
    Column {
        Text(value, style = MaterialTheme.typography.titleLarge)
        Text(
            label,
            style = MaterialTheme.typography.labelMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun TerminalCard(card: CardDescriptor, modifier: Modifier) {
    CardSurface(modifier, eyebrow = card.str("status", "running")) {
        val title = card.str("title")
        if (title.isNotEmpty()) {
            Text(title, style = MaterialTheme.typography.titleMedium)
        }
        val subtitle = card.str("subtitle")
        if (subtitle.isNotEmpty()) {
            Text(
                subtitle,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(
            card.str("body"),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            modifier = Modifier.padding(top = 8.dp),
        )
    }
}

@Composable
private fun ImageCard(card: CardDescriptor, modifier: Modifier) {
    // The card lands at COMMISSION time, empty, and settles in place when the
    // render finishes. Until the image loader lands it reports its own state
    // honestly rather than showing a blank frame.
    CardSurface(modifier, eyebrow = card.str("status", "running")) {
        val title = card.str("title").ifEmpty { card.str("prompt") }
        if (title.isNotEmpty()) {
            Text(title, style = MaterialTheme.typography.titleMedium)
        }
        val note = card.str("note").ifEmpty {
            when (card.str("status")) {
                "done" -> "The drawing is ready."
                "error" -> "The easel could not finish this one."
                else -> "At the easel..."
            }
        }
        Text(
            note,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(top = 4.dp),
        )
    }
}

@Composable
private fun PermissionCard(
    card: CardDescriptor,
    modifier: Modifier,
    onDecide: (String, Boolean) -> Unit,
) {
    val requestId = card.str("request_id")
    val decided = card.str("status", "pending") != "pending"
    CardSurface(modifier, eyebrow = "Permission") {
        Text(
            "May I ${card.str("action", "read")} this?",
            style = MaterialTheme.typography.titleMedium,
        )
        Text(
            card.str("path"),
            style = MaterialTheme.typography.bodySmall,
            fontFamily = androidx.compose.ui.text.font.FontFamily.Monospace,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(vertical = 6.dp),
        )
        if (!decided) {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(onClick = { onDecide(requestId, true) }) { Text("Allow") }
                TextButton(onClick = { onDecide(requestId, false) }) { Text("Deny") }
            }
        } else {
            Text(
                card.str("status"),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}

@Composable
private fun ChoiceCard(
    card: CardDescriptor,
    modifier: Modifier,
    onChoice: (String) -> Unit,
) {
    CardSurface(modifier, eyebrow = card.str("title").ifEmpty { null }) {
        val question = card.str("question")
        if (question.isNotEmpty()) {
            Text(question, style = MaterialTheme.typography.titleMedium)
        }
        Row(
            modifier = Modifier.padding(top = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            // A pick is re-sent as a user turn, so the conversation reads as
            // though the person said the word themselves.
            for (option in card.strList("options").take(4)) {
                OutlinedButton(onClick = { onChoice(option) }) { Text(option) }
            }
        }
    }
}
