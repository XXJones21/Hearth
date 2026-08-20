package com.hearth.app.ui.surfaces

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.requiredWidth
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
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
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.hearth.app.ui.theme.HearthColors
import com.hearth.core.config.ServerConfig
import com.hearth.core.surfaces.JournalBook
import com.hearth.core.surfaces.JournalEntry
import com.hearth.core.surfaces.JournalLibrary

/**
 * Selene's library, ported from the iOS `JournalView`.
 *
 * The rooms are in Selene's locked order and the arrangement is by how ALIVE
 * a thing is rather than what kind it is. The Heart's volumes stand FACE OUT
 * on a shelf because they are the ones being read; every other room shows
 * spines, because a shelf of spines is how you hold forty books in the space
 * three face-out ones would take.
 */
@Composable
fun JournalScreen(
    config: ServerConfig,
    onStartSession: (String) -> Unit,
    onBack: () -> Unit,
) {
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
        book != null -> BookPage(
            book = book,
            onOpenEntry = { openEntry = it },
            onStartSession = { onStartSession(book.title) },
            onBack = { openBook = null },
        )

        else -> SurfaceBackground {
            LazyColumn {
                item { SurfaceTopBar(onBack = onBack) }
                item {
                    OutlinedTextField(
                        value = query,
                        onValueChange = { query = it },
                        placeholder = { Text("Search the library") },
                        singleLine = true,
                        shape = RoundedCornerShape(28.dp),
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 6.dp),
                    )
                }
                item { SurfaceTitle("Journal", "kept by Selene") }

                val current = library
                when {
                    loading -> item { SurfaceLoadingBlock() }
                    current == null || current.isEmpty -> item { SurfaceUnavailableBlock() }
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

                        faceOutRoom(
                            "The Heart of the Library",
                            "on display, the volumes that live and grow",
                            heart,
                        ) { openBook = it }

                        spineRoom(
                            "The Curator's Alcove",
                            "the person before the works",
                            life,
                        ) { openBook = it }

                        spineRoom(
                            "The Active Forge",
                            "works in motion",
                            projects,
                        ) { openBook = it }

                        spineRoom(
                            "The Glass Conservatory",
                            "seedlings, one page each",
                            seedlings,
                            short = true,
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

/** The Heart: volumes standing face out, with the shelf under them. */
private fun LazyListScope.faceOutRoom(
    label: String,
    caption: String,
    books: List<JournalBook>,
    onOpen: (JournalBook) -> Unit,
) {
    if (books.isEmpty()) return
    item(key = "head-$label") { SectionHeading(label, caption) }
    item(key = "shelf-$label") {
        Column {
            Row(
                modifier = Modifier
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(10.dp),
            ) {
                for (book in books) FaceOutBook(book) { onOpen(book) }
            }
            Shelf()
        }
    }
}

@Composable
private fun FaceOutBook(book: JournalBook, onOpen: () -> Unit) {
    Surface(
        shape = RoundedCornerShape(6.dp),
        color = HearthColors.fennec,
        modifier = Modifier
            .width(150.dp)
            .height(150.dp)
            .clickable(onClick = onOpen),
    ) {
        Column(
            modifier = Modifier.padding(14.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Text(
                book.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.Bold,
                color = HearthColors.cream,
                textAlign = TextAlign.Center,
            )
            Text(
                bookCaption(book),
                style = MaterialTheme.typography.labelMedium,
                color = HearthColors.cream.copy(alpha = 0.8f),
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(top = 6.dp),
            )
            Text(
                "${book.pages}",
                style = MaterialTheme.typography.labelMedium,
                color = HearthColors.cream.copy(alpha = 0.85f),
                modifier = Modifier.padding(top = 14.dp),
            )
        }
    }
}

/** What each living volume is, in three words. */
private fun bookCaption(book: JournalBook): String = when {
    book.title.startsWith("The Journal") -> "daily sessions"
    book.title.startsWith("About") -> "operator facts"
    book.title.contains("Ledger") -> "nightly reviews"
    else -> "${book.pages} pages"
}

/** Every other room: spines, because forty books do not stand face out. */
private fun LazyListScope.spineRoom(
    label: String,
    caption: String,
    books: List<JournalBook>,
    short: Boolean = false,
    onOpen: (JournalBook) -> Unit,
) {
    if (books.isEmpty()) return
    item(key = "head-$label") { SectionHeading(label, caption) }
    item(key = "spines-$label") {
        Column {
            Row(
                modifier = Modifier
                    .horizontalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp),
                horizontalArrangement = Arrangement.spacedBy(6.dp),
                verticalAlignment = Alignment.Bottom,
            ) {
                for (book in books) Spine(book, short) { onOpen(book) }
            }
            Shelf()
        }
    }
}

@Composable
private fun Spine(book: JournalBook, short: Boolean, onOpen: () -> Unit) {
    // A spine varies with what is in the book, but only a little: the label
    // is laid out along the spine's LENGTH, so a short spine is a truncated
    // title. The first cut ranged 150 to 230dp and turned Resources into
    // "Reso...".
    val height = if (short) 130.dp else (176 + book.pages.coerceAtMost(24)).dp
    Box(
        modifier = Modifier
            .width(46.dp)
            .height(height)
            .clip(RoundedCornerShape(topStart = 4.dp, topEnd = 4.dp))
            .background(spineTint(book))
            .clickable(onClick = onOpen),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            book.title,
            style = MaterialTheme.typography.labelLarge,
            color = HearthColors.cream,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            // requiredWidth, not width: the spine Box is 46dp wide and a
            // plain width() is still clamped by it, so the label was being
            // measured at 46dp and every title longer than "Career" came out
            // as "Reso...". requiredWidth ignores the parent's constraint and
            // lays the text out along the spine's LENGTH before turning it.
            modifier = Modifier
                .requiredWidth(height - 18.dp)
                .graphicsLayer { rotationZ = -90f },
        )
    }
}

private fun spineTint(book: JournalBook): Color {
    // A stable but varied wash, so a shelf reads as many books rather than
    // one long block of colour.
    val shades = listOf(
        Color(0xFF6E4630), Color(0xFF7C4E33), Color(0xFF8A5A3C),
        Color(0xFF95643F), Color(0xFF63402C),
    )
    return shades[(book.title.hashCode().mod(shades.size))]
}

/** The board the books stand on. */
@Composable
private fun Shelf() {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 12.dp)
            .height(9.dp)
            .clip(RoundedCornerShape(3.dp))
            .background(HearthColors.ember.copy(alpha = 0.55f))
    )
}

@Composable
private fun Sanctum() {
    Surface(
        shape = RoundedCornerShape(14.dp),
        color = MaterialTheme.colorScheme.surfaceVariant.copy(alpha = 0.4f),
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 26.dp),
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text("The Sanctum of Reflection", style = MaterialTheme.typography.titleSmall)
            Text(
                "where memory is composed, not stored",
                style = MaterialTheme.typography.labelMedium,
                fontStyle = FontStyle.Italic,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/** A book opened: what it is, how much is in it, and its pages. */
@Composable
private fun BookPage(
    book: JournalBook,
    onOpenEntry: (JournalEntry) -> Unit,
    onStartSession: () -> Unit,
    onBack: () -> Unit,
) {
    SurfaceBackground {
        LazyColumn {
            item { SurfaceTopBar(onBack = onBack) }
            item {
                GroupCard {
                    Column(modifier = Modifier.padding(16.dp)) {
                        Text(
                            book.title,
                            style = MaterialTheme.typography.headlineSmall,
                            fontWeight = FontWeight.Bold,
                        )
                        Text(
                            "${book.pages} pages",
                            style = MaterialTheme.typography.labelMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        Text(
                            book.summary,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(top = 10.dp),
                        )
                        Text(
                            "Selene, keeper of the library",
                            style = MaterialTheme.typography.labelMedium,
                            fontStyle = FontStyle.Italic,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            textAlign = TextAlign.End,
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(top = 10.dp),
                        )
                    }
                }
            }
            item {
                Box(modifier = Modifier.padding(vertical = 12.dp)) {
                    StatTiles(
                        listOf(
                            "${book.pages}" to "Entries",
                            "${book.entries.size}" to "Shown",
                            (book.entries.firstOrNull()?.date ?: "-") to "Latest",
                        )
                    )
                }
            }
            item {
                Button(
                    onClick = onStartSession,
                    shape = RoundedCornerShape(14.dp),
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 16.dp),
                ) { Text("Start a session for ${book.title}") }
            }

            item { SectionHeading("Entries") }
            if (book.entries.isEmpty()) {
                item {
                    Text(
                        "This volume has no pages yet.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(horizontal = 20.dp, vertical = 16.dp),
                    )
                }
            }
            items(book.entries, key = { it.date + it.title }) { entry ->
                Box(modifier = Modifier.padding(bottom = 8.dp)) {
                    GroupCard(modifier = Modifier.clickable { onOpenEntry(entry) }) {
                        Column(modifier = Modifier.padding(14.dp)) {
                            Text(entry.title, style = MaterialTheme.typography.bodyLarge)
                            if (entry.synopsis.isNotBlank()) {
                                Text(
                                    entry.synopsis,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                    maxLines = 3,
                                    overflow = TextOverflow.Ellipsis,
                                    modifier = Modifier.padding(top = 2.dp),
                                )
                            }
                            Row(
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .padding(top = 10.dp),
                                horizontalArrangement = Arrangement.SpaceBetween,
                                verticalAlignment = Alignment.CenterVertically,
                            ) {
                                Chip(entry.persona, HearthColors.fennec)
                                Text(
                                    entry.date,
                                    style = MaterialTheme.typography.labelMedium,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun EntryPage(entry: JournalEntry, onBack: () -> Unit) {
    SurfaceBackground {
        LazyColumn {
            item { SurfaceTopBar(onBack = onBack) }
            item { SurfaceTitle(entry.title.take(60)) }
            item {
                Row(
                    modifier = Modifier.padding(horizontal = 20.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (entry.persona.isNotBlank()) {
                        Chip(entry.persona, HearthColors.fennec)
                    }
                    Text(
                        entry.date,
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
            item {
                Box(modifier = Modifier.padding(top = 14.dp)) {
                    GroupCard {
                        Text(
                            entry.synopsis,
                            style = MaterialTheme.typography.bodyMedium,
                            modifier = Modifier.padding(16.dp),
                        )
                    }
                }
            }
        }
    }
}
