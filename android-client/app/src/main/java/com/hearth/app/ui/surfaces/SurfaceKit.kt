package com.hearth.app.ui.surfaces

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hearth.app.ui.theme.HearthColors

/**
 * The shared vocabulary every house surface is built from, ported from the
 * iOS surface chrome.
 *
 * The screens looked wrong before this existed because each one hand-rolled
 * its own rows: iOS has a small set of pieces used everywhere, and the
 * FAMILY RESEMBLANCE between the screens is most of what makes them read as
 * one app. These are those pieces.
 */

/** The pill that goes back to the stage, and the optional one beside it. */
@Composable
fun SurfaceTopBar(
    onBack: () -> Unit,
    trailingLabel: String? = null,
    onTrailing: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 10.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Pill("Hearth", onBack)
        if (trailingLabel != null && onTrailing != null) Pill(trailingLabel, onTrailing)
    }
}

@Composable
private fun Pill(label: String, onClick: () -> Unit) {
    Surface(
        shape = CircleShape,
        color = Color.Transparent,
        border = androidx.compose.foundation.BorderStroke(
            1.dp,
            HearthColors.ember.copy(alpha = 0.55f),
        ),
        modifier = Modifier.clickable(onClick = onClick),
    ) {
        Text(
            label,
            style = MaterialTheme.typography.titleMedium,
            color = HearthColors.ember,
            modifier = Modifier.padding(horizontal = 22.dp, vertical = 10.dp),
        )
    }
}

/** The screen's own name, with the line that says what it is for. */
@Composable
fun SurfaceTitle(title: String, subtitle: String? = null, note: String? = null) {
    Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp)) {
        Text(
            title,
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
        )
        subtitle?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodyLarge,
                fontStyle = FontStyle.Italic,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        note?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 6.dp),
            )
        }
    }
}

/**
 * A section: ember capitals with an italic caption beside them. The caption
 * is not decoration, it is what tells you why the section exists.
 */
@Composable
fun SectionHeading(label: String, caption: String? = null) {
    // A long label takes the line to itself and the caption sits under it.
    // Side by side, "THE HEART OF THE LIBRARY" left its caption two wrapped
    // lines that collided with the heading.
    val stacked = label.length > 16
    Column(
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 8.dp),
    ) {
        if (stacked) {
            Text(
                label.uppercase(),
                style = MaterialTheme.typography.labelMedium,
                color = HearthColors.ember,
                fontWeight = FontWeight.SemiBold,
                letterSpacing = 1.2.sp,
            )
            caption?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelMedium,
                    fontStyle = FontStyle.Italic,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        } else {
            Row(
                verticalAlignment = Alignment.Bottom,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Text(
                    label.uppercase(),
                    style = MaterialTheme.typography.labelMedium,
                    color = HearthColors.ember,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.2.sp,
                )
                caption?.let {
                    Text(
                        it,
                        style = MaterialTheme.typography.labelMedium,
                        fontStyle = FontStyle.Italic,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** The rounded container a group of rows lives in. */
@Composable
fun GroupCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Surface(
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
    ) {
        Column(content = content)
    }
}

/** A small square badge carrying an initial, as the Apps rows do. */
@Composable
fun InitialBadge(text: String, tint: Color, rounded: Boolean = true) {
    Box(
        modifier = Modifier
            .size(40.dp)
            .clip(if (rounded) RoundedCornerShape(10.dp) else CircleShape)
            .background(tint),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text.take(2),
            style = MaterialTheme.typography.labelLarge,
            color = HearthColors.roast,
            fontWeight = FontWeight.SemiBold,
        )
    }
}

/** A capability chip: ALWAYS ON, WRITE, CLI, THIS PHONE. */
@Composable
fun Chip(label: String, tint: Color = HearthColors.fawn) {
    // A blank chip is not a chip. Rendering one produced a tall empty pill
    // stretched to the row height, which read as a rendering fault.
    if (label.isBlank()) return
    Surface(
        shape = CircleShape,
        color = Color.Transparent,
        border = androidx.compose.foundation.BorderStroke(1.dp, tint.copy(alpha = 0.7f)),
    ) {
        Text(
            label.uppercase(),
            style = MaterialTheme.typography.labelSmall,
            color = tint,
            fontSize = 10.sp,
            letterSpacing = 0.6.sp,
            modifier = Modifier.padding(horizontal = 8.dp, vertical = 3.dp),
        )
    }
}

/**
 * One row inside a [GroupCard]: an optional badge, a title with chips, a
 * detail line, and a chevron when it goes somewhere.
 */
@Composable
fun GroupRow(
    title: String,
    detail: String? = null,
    badge: Pair<String, Color>? = null,
    chips: List<Pair<String, Color>> = emptyList(),
    status: String? = null,
    locked: Boolean = false,
    showChevron: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        badge?.let { InitialBadge(it.first, it.second) }
        Column(modifier = Modifier.weight(1f)) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                Text(title, style = MaterialTheme.typography.bodyLarge)
                for (chip in chips) Chip(chip.first, chip.second)
            }
            detail?.takeIf { it.isNotBlank() }?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            status?.let {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                    modifier = Modifier.padding(top = 4.dp),
                ) {
                    Box(
                        modifier = Modifier
                            .size(7.dp)
                            .clip(CircleShape)
                            .background(HearthColors.fennec)
                    )
                    Text(
                        it,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
        if (locked) {
            Icon(
                Icons.Outlined.Lock,
                contentDescription = "Read only",
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                modifier = Modifier.size(15.dp),
            )
        }
        if (showChevron) {
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** A labelled read-only field, as the persona's Who they are rows are. */
@Composable
fun FieldRow(label: String, value: String, locked: Boolean = true) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 14.dp, vertical = 10.dp),
        verticalAlignment = Alignment.Top,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                label,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(value, style = MaterialTheme.typography.bodyLarge)
        }
        if (locked) {
            Icon(
                Icons.Outlined.Lock,
                contentDescription = "Read only",
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                modifier = Modifier.size(15.dp),
            )
        }
    }
}

@Composable
fun RowDivider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.15f),
        modifier = Modifier.padding(start = 14.dp),
    )
}

/** The three tiles a book page carries: entries, shown, latest. */
@Composable
fun StatTiles(tiles: List<Pair<String, String>>) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        for ((value, label) in tiles) {
            Surface(
                shape = RoundedCornerShape(12.dp),
                color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.weight(1f),
            ) {
                Column(modifier = Modifier.padding(14.dp)) {
                    Text(
                        value,
                        style = MaterialTheme.typography.titleMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        label,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

/** The footer that explains what this screen will and will not change. */
@Composable
fun SurfaceFootnote(vararg lines: String) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 24.dp, vertical = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        for (line in lines) {
            Text(
                line,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            )
        }
    }
}

@Composable
fun SurfaceBackground(content: @Composable () -> Unit) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) { content() }
}

@Composable
fun SurfaceLoadingBlock() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(48.dp),
        contentAlignment = Alignment.Center,
    ) { androidx.compose.material3.CircularProgressIndicator() }
}

@Composable
fun SurfaceUnavailableBlock() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(48.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            "The house did not answer for this.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}
