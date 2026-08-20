package com.hearth.app.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp

/**
 * The drawer, ported from the iOS `HouseShelf`: the personas you can switch
 * to, the four house surfaces, and settings.
 *
 * iOS reaches these from a right-edge drawer rather than a tab bar, because
 * the stage is the app and everything else is somewhere you visit. The same
 * shape here, as a Compose ModalDrawerSheet.
 */
@Composable
fun HouseShelf(
    personas: List<String>,
    currentPersona: String,
    onPersona: (String) -> Unit,
    onOpen: (HouseDestination) -> Unit,
    onNewSession: () -> Unit,
) {
    ModalDrawerSheet {
        Column(
            modifier = Modifier
                .systemBarsPadding()
                .verticalScroll(rememberScrollState())
                .padding(vertical = 12.dp),
        ) {
            Text(
                "Personas",
                style = MaterialTheme.typography.labelLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            )
            for (name in personas) {
                ShelfRow(
                    label = name,
                    trailing = if (name == currentPersona) "Here" else null,
                    onClick = { onPersona(name) },
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 12.dp))

            ShelfRow(label = "New conversation", onClick = onNewSession)
            for (destination in HouseDestination.entries) {
                ShelfRow(label = destination.label, onClick = { onOpen(destination) })
            }
        }
    }
}

enum class HouseDestination(val label: String) {
    SESSIONS("Conversations"),
    JOURNAL("Journal"),
    PERSONA("Persona"),
    APPS("Apps"),
    SETTINGS("Settings"),
}

@Composable
private fun ShelfRow(label: String, trailing: String? = null, onClick: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(horizontal = 20.dp, vertical = 14.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = MaterialTheme.typography.bodyLarge)
        trailing?.let {
            Text(
                it,
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
    }
}
