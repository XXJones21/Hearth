package com.hearth.app.ui.surfaces

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.JournalBook
import com.hearth.core.surfaces.JournalEntry
import com.hearth.core.surfaces.JournalLibrary

/**
 * Selene's library, ported from the iOS `JournalView`.
 *
 * The rooms are in Selene's locked order and each one says what it is for.
 * The arrangement is by how ALIVE a thing is rather than what kind of thing
 * it is: a project with one page is a seedling in the conservatory, not a
 * small book in the forge.
 *
 * Search filters every room at once, and a room with nothing matching simply
 * does not appear.
 */
@Composable
fun JournalScreen(config: ServerConfig, onBack: () -> Unit) {
    var library by remember { mutableStateOf<JournalLibrary?>(null) }
    var loading by remember { mutableStateOf(true) }
    var query by remember { mutableStateOf("") }
    var openBook by remember { mutableStateOf<JournalBook?>(null) }
    var openEntry by remember { mutableStateOf<JournalEntry?>(null) }

    LaunchedEffect(Unit) {
        library = JournalLibrary.load(config)
        loading = false
    }

    val entry = openEntry
    val book = openBook
    when {
        entry != null -> EntryPage(entry) { openEntry = null }
        book != null -> BookPage(book, onOpenEntry = { openEntry = it }) { openBook = null }
        else -> SurfaceScaffold("Journal", onBack) { padding ->
            val current = library
            when {
                loading -> SurfaceLoading(padding)
                current == null || current.isEmpty -> SurfaceUnavailable(padding)
                else -> {
                    fun matching(books: List<JournalBook>) =
                        if (query.isBlank()) books
                        else books.filter {
                            it.title.contains(query, ignoreCase = true) ||
                                it.summary.contains(query, ignoreCase = true)
                        }

                    val heart = matching(current.heart)
                    val life = matching(current.life)
                    val projects = matching(current.projects)
                    val seedlings = matching(current.seedlings)

                    LazyColumn(modifier = Modifier.padding(padding)) {
                        item {
                            OutlinedTextField(
                                value = query,
                                onValueChange = { query = it },
                                placeholder = { Text("Search the library") },
                                singleLine = true,
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(horizontal = 20.dp, vertical = 8.dp),
                            )
                        }

                        room(
                            "The Heart of the Library",
                            "on display, the volumes that live and grow",
                            heart,
                        ) { openBook = it }

                        room(
                            "The Curator's Alcove",
                            "the person before the works",
                            life,
                        ) { openBook = it }

                        room(
                            "The Active Forge",
                            "works in motion",
                            projects,
                        ) { openBook = it }

                        room(
                            "The Glass Conservatory",
                            "seedlings, one page each",
                            seedlings,
                        ) { openBook = it }

                        if (heart.isEmpty() && life.isEmpty() &&
                            projects.isEmpty() && seedlings.isEmpty()
                        ) {
                            item {
                                Text(
                                    "No book answers to \"$query\".",
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .padding(top = 40.dp),
                                )
                            }
                        }

                        item { Sanctum() }
                    }
                }
            }
        }
    }
}

/** A room, and the books standing in it. Empty rooms do not appear. */
private fun androidx.compose.foundation.lazy.LazyListScope.room(
    label: String,
    caption: String,
    books: List<JournalBook>,
    onOpen: (JournalBook) -> Unit,
) {
    if (books.isEmpty()) return
    item(key = "room-$label") {
        Column(modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp)) {
            Text(
                label,
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onBackground,
            )
            Text(
                caption,
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    items(books, key = { "$label-${it.title}" }) { book ->
        SurfaceRowItem(
            title = book.title,
            detail = book.summary,
            trailing = "${book.pages}",
            onClick = { onOpen(book) },
        )
    }
}

/** The footer that names what the library is for. */
@Composable
private fun Sanctum() {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 20.dp, vertical = 24.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                "The Sanctum of Reflection",
                style = MaterialTheme.typography.titleSmall,
            )
            Text(
                "where memory is composed, not stored",
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun BookPage(
    book: JournalBook,
    onOpenEntry: (JournalEntry) -> Unit,
    onBack: () -> Unit,
) {
    SurfaceScaffold(book.title, onBack) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                Text(
                    book.summary,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
                )
            }
            if (book.entries.isEmpty()) {
                item {
                    Text(
                        "This volume has no pages yet.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 20.dp),
                    )
                }
            }
            items(book.entries, key = { it.date + it.title }) { entry ->
                Column(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpenEntry(entry) }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                    ) {
                        Text(
                            entry.title,
                            style = MaterialTheme.typography.bodyLarge,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.weight(1f, fill = false),
                        )
                        Text(
                            entry.date,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 8.dp),
                        )
                    }
                    if (entry.synopsis.isNotBlank()) {
                        Text(
                            entry.synopsis,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun EntryPage(entry: JournalEntry, onBack: () -> Unit) {
    SurfaceScaffold(entry.title.take(40), onBack) { padding ->
        LazyColumn(modifier = Modifier.padding(padding)) {
            item {
                Column(modifier = Modifier.padding(20.dp)) {
                    Text(
                        listOfNotNull(
                            entry.date.ifBlank { null },
                            entry.persona.ifBlank { null },
                        ).joinToString(" - "),
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        entry.synopsis,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(top = 12.dp),
                    )
                }
            }
        }
    }
}
