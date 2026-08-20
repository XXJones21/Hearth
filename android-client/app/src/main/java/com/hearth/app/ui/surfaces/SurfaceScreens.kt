package com.hearth.app.ui.surfaces

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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.AppsSurface
import com.hearth.core.surfaces.JournalShelf
import com.hearth.core.surfaces.PersonaSurface
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
private fun SurfaceScaffold(
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
private fun Unavailable(padding: PaddingValues) {
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
private fun Loading(padding: PaddingValues) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(padding),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) { CircularProgressIndicator() }
}

@Composable
private fun RowItem(title: String, detail: String?, trailing: String? = null, onClick: (() -> Unit)? = null) {
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
 * Every conversation, newest first, grouped by day. Tapping one resumes it,
 * which is the same two-step iOS uses: the row shows what it was, the button
 * says what will happen.
 */
@Composable
fun SessionsScreen(config: ServerConfig, onResume: (String) -> Unit, onBack: () -> Unit) {
    var surface by remember { mutableStateOf<SessionsSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        surface = SessionsSurface.load(config)
        loading = false
    }

    SurfaceScaffold("Conversations", onBack) { padding ->
        val rows = surface?.rows
        when {
            loading -> Loading(padding)
            rows.isNullOrEmpty() -> Unavailable(padding)
            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                for ((day, dayRows) in surface!!.grouped()) {
                    item(key = "day-$day") {
                        Text(
                            day,
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                        )
                    }
                    items(dayRows, key = { it.sessionId + it.fromJournal }) { row ->
                        RowItem(
                            title = row.title,
                            detail = row.summary.ifBlank {
                                listOfNotNull(
                                    row.persona.ifBlank { null },
                                    if (row.turns > 0) "${row.turns} turns" else null,
                                ).joinToString(" - ")
                            },
                            trailing = "Resume",
                            onClick = { onResume(row.sessionId) },
                        )
                    }
                    item(key = "div-$day") { HorizontalDivider() }
                }
            }
        }
    }
}

// ---- journal --------------------------------------------------------------

/** The shelf in the house's own two halves: what you build, what you live. */
@Composable
fun JournalScreen(config: ServerConfig, onBack: () -> Unit) {
    var shelf by remember { mutableStateOf<JournalShelf?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        shelf = JournalShelf.load(config)
        loading = false
    }

    SurfaceScaffold("Journal", onBack) { padding ->
        val current = shelf
        when {
            loading -> Loading(padding)
            current == null -> Unavailable(padding)
            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                for ((heading, books) in listOf(
                    "Projects" to current.projects,
                    "Life" to current.life,
                )) {
                    if (books.isEmpty()) continue
                    item(key = "h-$heading") {
                        Text(
                            heading,
                            style = MaterialTheme.typography.labelLarge,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                        )
                    }
                    items(books, key = { heading + it.title }) { book ->
                        RowItem(
                            title = book.title,
                            detail = book.summary,
                            trailing = "${book.entries}",
                        )
                    }
                }
            }
        }
    }
}

// ---- apps -----------------------------------------------------------------

@Composable
fun AppsScreen(config: ServerConfig, onBack: () -> Unit) {
    var surface by remember { mutableStateOf<AppsSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        surface = AppsSurface.load(config)
        loading = false
    }

    SurfaceScaffold("Apps", onBack) { padding ->
        val current = surface
        when {
            loading -> Loading(padding)
            current == null -> Unavailable(padding)
            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                item {
                    Text(
                        if (current.toolsEnabled) "Tools are on" else "Tools are off",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                }
                items(current.apps, key = { it.key }) { app ->
                    RowItem(
                        title = app.name,
                        detail = app.tagline,
                        trailing = app.kind.ifBlank { null },
                    )
                }
                item { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }
                item {
                    Text(
                        "Cards this house can draw",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                }
                items(current.cards, key = { it.type }) { card ->
                    RowItem(title = card.type, detail = card.purpose, trailing = card.state)
                }
            }
        }
    }
}

// ---- persona --------------------------------------------------------------

@Composable
fun PersonaScreen(config: ServerConfig, onBack: () -> Unit) {
    var surface by remember { mutableStateOf<PersonaSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        surface = PersonaSurface.load(config)
        loading = false
    }

    SurfaceScaffold("Persona", onBack) { padding ->
        val people = surface?.personas
        when {
            loading -> Loading(padding)
            people.isNullOrEmpty() -> Unavailable(padding)
            // Internal personas are the house's own machinery, not someone to
            // talk to; iOS hides them here for the same reason.
            else -> LazyColumn(modifier = Modifier.padding(padding)) {
                items(people.filter { !it.internal }, key = { it.key }) { person ->
                    RowItem(
                        title = person.name,
                        detail = person.description,
                        trailing = person.form.ifBlank { null },
                    )
                }
            }
        }
    }
}

// ---- settings -------------------------------------------------------------

/**
 * The house's own state, plus the one thing this client owns: the address it
 * dials and the pairing behind it.
 */
@Composable
fun SettingsScreen(
    config: ServerConfig,
    onForget: () -> Unit,
    onBack: () -> Unit,
) {
    var surface by remember { mutableStateOf<SettingsSurface?>(null) }
    var loading by remember { mutableStateOf(true) }
    LaunchedEffect(Unit) {
        surface = SettingsSurface.load(config)
        loading = false
    }

    SurfaceScaffold("Settings", onBack) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                Text(
                    "This device",
                    style = MaterialTheme.typography.labelLarge,
                    color = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                )
            }
            item {
                RowItem(
                    title = "House address",
                    detail = config.address.ifBlank { "Not set" },
                )
            }
            item {
                RowItem(
                    title = "Paired",
                    detail = if (config.isPaired) "This device has a key" else "Not paired",
                    trailing = if (config.isPaired) "Forget" else null,
                    onClick = if (config.isPaired) onForget else null,
                )
            }

            item { HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp)) }

            val current = surface
            if (loading) {
                item { Loading(PaddingValues(0.dp)) }
            } else if (current == null) {
                item {
                    RowItem(
                        title = "The house",
                        detail = "Did not answer for its own settings.",
                    )
                }
            } else {
                item {
                    Text(
                        "The house",
                        style = MaterialTheme.typography.labelLarge,
                        color = MaterialTheme.colorScheme.primary,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                    )
                }
                item {
                    RowItem(
                        title = "Brain",
                        detail = current.brainBackend.ifBlank { "unknown" },
                        trailing = current.serverVersion.ifBlank { null },
                    )
                }
                current.engram?.let { engram ->
                    item {
                        RowItem(
                            title = "Second brain",
                            detail = if (engram.connected) engram.path else "Not connected",
                            trailing = if (engram.entries > 0) "${engram.entries}" else null,
                        )
                    }
                }
                items(current.connections, key = { it.key }) { connection ->
                    RowItem(
                        title = connection.name,
                        detail = connection.detail,
                        trailing = connection.state,
                    )
                }
            }
        }
    }
}
