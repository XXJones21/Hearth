package com.hearth.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.outlined.Book
import androidx.compose.material.icons.outlined.ChatBubbleOutline
import androidx.compose.material.icons.outlined.GridView
import androidx.compose.material.icons.outlined.Person
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Forum
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hearth.app.ui.theme.HearthColors

/**
 * The house shelf, ported from the iOS drawer.
 *
 * Shape notes, all of them from the iOS screen rather than invented:
 *   - it comes in from the RIGHT, not the left
 *   - it is DARK over a cream stage, so it reads as a drawer pulled over the
 *     room rather than another page of it
 *   - personas carry a round initial and the current one is ticked
 *   - every row has an icon
 *   - Chat log is a SWITCH pinned to the bottom next to Settings, because it
 *     changes the room you are looking at rather than taking you somewhere
 */
@Composable
fun HouseShelf(
    personas: List<String>,
    currentPersona: String,
    connected: Boolean,
    onPersona: (String) -> Unit,
    onOpen: (HouseDestination) -> Unit,
    transcriptShown: Boolean,
    onToggleTranscript: (Boolean) -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxHeight()
            .width(320.dp)
            .background(HearthColors.night)
            .systemBarsPadding(),
    ) {
        Column(modifier = Modifier.padding(horizontal = 24.dp, vertical = 18.dp)) {
            Text(
                "Hearth",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.SemiBold,
                color = HearthColors.cream,
            )
            Text(
                if (connected) "Connected as $currentPersona" else "Not connected",
                style = MaterialTheme.typography.bodyMedium,
                color = HearthColors.fawn,
            )
        }
        HorizontalDivider(color = HearthColors.fawn.copy(alpha = 0.25f))

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState()),
        ) {
            SectionLabel("PERSONAS")
            for (name in personas) {
                PersonaRow(
                    name = name,
                    current = name == currentPersona,
                    onClick = { onPersona(name) },
                )
            }

            HorizontalDivider(
                color = HearthColors.fawn.copy(alpha = 0.25f),
                modifier = Modifier.padding(vertical = 10.dp),
            )

            for (destination in HouseDestination.entries) {
                ShelfRow(
                    label = destination.label,
                    icon = destination.icon,
                    onClick = { onOpen(destination) },
                )
            }
        }

        HorizontalDivider(color = HearthColors.fawn.copy(alpha = 0.25f))

        // The two that live at the bottom: one changes this room, one leaves it.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { onToggleTranscript(!transcriptShown) }
                .padding(horizontal = 24.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Outlined.Forum,
                contentDescription = null,
                tint = HearthColors.fawn,
                modifier = Modifier.size(22.dp),
            )
            Spacer(Modifier.width(16.dp))
            Text(
                "Chat log",
                style = MaterialTheme.typography.bodyLarge,
                color = HearthColors.cream,
                modifier = Modifier.weight(1f),
            )
            Switch(
                checked = transcriptShown,
                onCheckedChange = onToggleTranscript,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = HearthColors.cream,
                    checkedTrackColor = HearthColors.fennec,
                    uncheckedThumbColor = HearthColors.cream,
                    uncheckedTrackColor = HearthColors.fawn.copy(alpha = 0.4f),
                ),
            )
        }

        ShelfRow(
            label = "Settings",
            icon = Icons.Outlined.Settings,
            onClick = { onOpen(HouseDestination.SETTINGS) },
        )
        Spacer(Modifier.padding(bottom = 8.dp))
    }
}

/** The destinations, minus Settings, which sits with Chat log at the bottom. */
enum class HouseDestination(val label: String, val icon: ImageVector) {
    SESSIONS("Sessions", Icons.Outlined.ChatBubbleOutline),
    JOURNAL("Journal", Icons.Outlined.Book),
    PERSONA("Persona", Icons.Outlined.Person),
    APPS("Apps & Extensions", Icons.Outlined.GridView),
    SETTINGS("Settings", Icons.Outlined.Settings);

    companion object {
        /** What the middle list shows: Settings is pinned below instead. */
        val entries: List<HouseDestination>
            get() = listOf(SESSIONS, JOURNAL, PERSONA, APPS)
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelSmall,
        color = HearthColors.fawn,
        fontSize = 12.sp,
        letterSpacing = 1.sp,
        modifier = Modifier.padding(horizontal = 24.dp, vertical = 10.dp),
    )
}

@Composable
private fun PersonaRow(name: String, current: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(
            modifier = Modifier
                .size(34.dp)
                .background(
                    if (current) HearthColors.fennec else HearthColors.honey,
                    CircleShape,
                ),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                name.take(1).uppercase(),
                style = MaterialTheme.typography.labelLarge,
                color = HearthColors.roast,
                fontWeight = FontWeight.SemiBold,
            )
        }
        Text(
            name,
            style = MaterialTheme.typography.bodyLarge,
            color = HearthColors.cream,
            fontWeight = if (current) FontWeight.SemiBold else FontWeight.Normal,
            modifier = Modifier.weight(1f),
        )
        if (current) {
            Icon(
                Icons.Filled.Check,
                contentDescription = "Here",
                tint = HearthColors.fennec,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun ShelfRow(label: String, icon: ImageVector, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 24.dp, vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = HearthColors.fawn,
            modifier = Modifier.size(22.dp),
        )
        Spacer(Modifier.width(16.dp))
        Text(
            label,
            style = MaterialTheme.typography.bodyLarge,
            color = HearthColors.cream,
        )
    }
}
