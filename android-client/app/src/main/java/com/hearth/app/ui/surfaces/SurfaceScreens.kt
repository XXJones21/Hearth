package com.hearth.app.ui.surfaces

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.AppsSurface
import com.hearth.core.surfaces.PersonaSurface
import com.hearth.core.surfaces.SessionRow
import com.hearth.core.surfaces.SessionsSurface
import com.hearth.core.surfaces.SettingsSurface

/**
 * The house surfaces, ported from the iOS screens of the same names.
 *
 * They are READ-ONLY here, deliberately and for now: iOS makes exactly two
 * things writable (the persona prompt and its state colours, batched behind
 * Save) and everything else on these screens is a mirror of what the house
 * already knows. Rendering the mirror first means the surfaces are useful on
 * the appliance before any editing exists, and there is no half-written state
 * to reconcile.
 *
 * Each screen owns its loader and shows one of three honest states: loading,
 * the content, or "this surface is unavailable" when the house did not answer.
 */

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SurfaceScaffold(
    title: String,
    onBack: () -> Unit,
    content: @Composable (PaddingValues) -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title) },
                navigationIcon = { TextButton(onClick = onBack) { Text("Back") } },
            )
        },
        content = content,
    )
}

@Composable
internal fun SurfaceUnavailable(padding: PaddingValues) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding)
            .padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            "The house did not answer for this.",
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
internal fun SurfaceLoading(padding: PaddingValues) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) { CircularProgressIndicator() }
}

@Composable
internal fun SurfaceRowItem(title: String, detail: String?, trailing: String? = null, onClick: (() -> Unit)? = null) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .then(if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier)
            .padding(horizontal = 20.dp, vertical = 12.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // The title takes the room and ellipsises; without the weight a
            // long one squeezes the trailing label into a vertical stack of
            // single letters.
            Text(
                title,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            trailing?.let {
                Text(
                    it,
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.primary,
                    maxLines = 1,
                    modifier = Modifier.padding(start = 12.dp),
                )
            }
        }
        if (!detail.isNullOrBlank()) {
            Text(
                detail,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ---- conversations --------------------------------------------------------

/**
 * Every conversation, newest first, grouped by day.
 *
 * Two taps, not one: the row expands to show what the conversation WAS, and
 * Resume is a separate deliberate press. Resuming ends the live session and
 * repaints the stage, which is too much to do to someone who was browsing.
 */
@Composable
fun SessionsScreen(
    config: ServerConfig,
    canAct: Boolean,
    onResumeSession: (String) -> Unit,
    onResumeSlug: (String) -> Unit,
    onNewSession: () -> Unit,
    onBack: () -> Unit,
) {
    var surface by remember { mutableStateOf<SessionsSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    var expanded by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(Unit) {
        surface = SessionsSurface.load(config)
        loading = false
    }

    SurfaceScaffold("Sessions", onBack) { padding ->
        val rows = surface?.rows
        when {
            loading -> SurfaceLoading(padding)
            rows.isNullOrEmpty() -> SurfaceUnavailable(padding)
            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                item(key = "new") {
                    SurfaceRowItem(
                        title = "Start a new conversation",
                        detail = "Puts the current one away and begins fresh.",
                        onClick = if (canAct) onNewSession else null,
                    )
                }
                item(key = "new-div") { HorizontalDivider() }

                for ((day, dayRows) in surface!!.grouped()) {
                    item(key = "day-$day") { SurfaceSectionLabel(day) }
                    items(dayRows, key = { it.sessionId + it.fromJournal }) { row ->
                        SessionRowView(
                            row = row,
                            expanded = expanded == row.sessionId + row.fromJournal,
                            canAct = canAct,
                            onToggle = {
                                val id = row.sessionId + row.fromJournal
                                expanded = if (expanded == id) null else id
                            },
                            onResume = {
                                if (row.fromJournal) onResumeSlug(row.slug)
                                else onResumeSession(row.sessionId)
                            },
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun SurfaceSectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(horizontal = 20.dp, vertical = 10.dp),
    )
}

@Composable
private fun SessionRowView(
    row: SessionRow,
    expanded: Boolean,
    canAct: Boolean,
    onToggle: () -> Unit,
    onResume: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .background(
                if (expanded) MaterialTheme.colorScheme.surfaceVariant
                else Color.Transparent
            )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable(onClick = onToggle)
                .padding(horizontal = 20.dp, vertical = 10.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                row.title,
                style = MaterialTheme.typography.bodyLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            if (row.persona.isNotEmpty()) {
                Text(
                    row.persona,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(start = 8.dp),
                )
            }
        }

        if (expanded) {
            Column(
                modifier = Modifier.padding(
                    start = 20.dp, end = 20.dp, top = 2.dp, bottom = 14.dp,
                ),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                if (row.summary.isNotBlank()) {
                    Text(
                        row.summary,
                        style = MaterialTheme.typography.bodyMedium,
                        maxLines = 6,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
                if (row.turns > 0) {
                    Text(
                        "${row.turns} turn${if (row.turns == 1) "" else "s"}" +
                            if (row.synced) " - written up in the Journal"
                            else " - not written up yet",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                if (row.resumable) {
                    Button(onClick = onResume, enabled = canAct) { Text("Resume") }
                } else {
                    Text(
                        "No full transcript was kept for this one.",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

// ---- journal --------------------------------------------------------------
