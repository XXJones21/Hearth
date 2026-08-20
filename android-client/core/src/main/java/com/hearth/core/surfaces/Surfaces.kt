package com.hearth.core.surfaces

import com.hearth.core.config.ServerConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * The read-only house surfaces, ported from the iOS `*Surface` models.
 *
 * Every one of them is the same shape: GET a JSON document through the single
 * origin, decode it FIELD BY FIELD with a fallback, and hand back a data
 * class. Decoding is deliberately tolerant rather than strict: a house one
 * version ahead adds a key, and a client that throws on it shows an error
 * screen where it should have shown a slightly older view of a working house.
 *
 * Shapes were read off the live house rather than inferred, which is why the
 * key names here are the ones the gateway actually writes.
 */

private val client = OkHttpClient.Builder()
    .connectTimeout(8, TimeUnit.SECONDS)
    .readTimeout(8, TimeUnit.SECONDS)
    .build()

/** One GET against the house, or null. Never throws: a surface that cannot
 *  load reports itself unavailable, which is honest. */
internal suspend fun fetch(config: ServerConfig, path: String): JSONObject? =
    withContext(Dispatchers.IO) {
        val request = config.request(path) ?: return@withContext null
        try {
            client.newCall(request).execute().use { response ->
                if (!response.isSuccessful) return@withContext null
                JSONObject(response.body?.string().orEmpty())
            }
        } catch (e: Exception) {
            null
        }
    }

private fun JSONArray?.objects(): List<JSONObject> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { optJSONObject(it) }
}

private fun JSONArray?.strings(): List<String> {
    if (this == null) return emptyList()
    return (0 until length()).mapNotNull { optString(it).ifEmpty { null } }
}

// ---- apps -----------------------------------------------------------------

data class HouseApp(
    val key: String,
    val name: String,
    val kind: String,
    val tagline: String,
    val transport: String,
    val tools: List<String>,
    /** active | setup | available. The page groups on this. */
    val state: String,
    /** Which personas are offered it. */
    val who: List<String>,
    /** What it is still waiting on, when state is setup. */
    val needs: List<String>,
    /** Tools beyond the ones listed. */
    val more: Int,
    /** read | write | control: how much this app can do. */
    val risk: String,
)

data class CardKind(
    val type: String,
    val purpose: String,
    val state: String,
)

data class AppsSurface(
    val apps: List<HouseApp>,
    val cards: List<CardKind>,
    val toolsEnabled: Boolean,
) {
    companion object {
        suspend fun load(config: ServerConfig): AppsSurface? {
            val json = fetch(config, "/apps/surface") ?: return null
            return AppsSurface(
                apps = json.optJSONArray("apps").objects().map {
                    HouseApp(
                        key = it.optString("key"),
                        name = it.optString("name"),
                        kind = it.optString("kind"),
                        tagline = it.optString("tagline"),
                        transport = it.optString("transport"),
                        tools = it.optJSONArray("tools").strings(),
                        state = it.optString("state").ifEmpty { "available" },
                        who = it.optJSONArray("who").strings(),
                        needs = it.optJSONArray("needs").strings(),
                        more = it.optInt("more"),
                        risk = it.optString("risk"),
                    )
                },
                cards = json.optJSONArray("cards").objects().map {
                    CardKind(
                        type = it.optString("type"),
                        purpose = it.optString("purpose"),
                        state = it.optString("state"),
                    )
                },
                toolsEnabled = json.optBoolean("tools_enabled"),
            )
        }
    }
}

// ---- settings -------------------------------------------------------------

data class HouseFolder(
    val key: String,
    val name: String,
    val path: String,
    val detail: String,
    val exists: Boolean,
)

data class Connection(
    val key: String,
    val name: String,
    val role: String,
    val state: String,
    val detail: String,
)

data class EngramStatus(
    val path: String,
    val connected: Boolean,
    val exists: Boolean,
    val entries: Int,
)

data class SettingsSurface(
    val folders: List<HouseFolder>,
    val engram: EngramStatus?,
    val connections: List<Connection>,
    val serverVersion: String,
    val brainBackend: String,
) {
    companion object {
        suspend fun load(config: ServerConfig): SettingsSurface? {
            val json = fetch(config, "/settings/surface") ?: return null
            val server = json.optJSONObject("server")
            val engram = json.optJSONObject("engram")
            return SettingsSurface(
                folders = json.optJSONArray("folders").objects().map {
                    HouseFolder(
                        key = it.optString("key"),
                        name = it.optString("name"),
                        path = it.optString("path"),
                        detail = it.optString("detail"),
                        exists = it.optBoolean("exists"),
                    )
                },
                engram = engram?.let {
                    EngramStatus(
                        path = it.optString("path"),
                        connected = it.optBoolean("connected"),
                        exists = it.optBoolean("exists"),
                        entries = it.optInt("entries"),
                    )
                },
                connections = json.optJSONArray("connections").objects().map {
                    Connection(
                        key = it.optString("key"),
                        name = it.optString("name"),
                        role = it.optString("role"),
                        state = it.optString("state"),
                        detail = it.optString("detail"),
                    )
                },
                serverVersion = server?.optString("version").orEmpty(),
                brainBackend = server?.optString("brain_backend").orEmpty(),
            )
        }
    }
}

// ---- personas -------------------------------------------------------------

data class PersonaEntry(
    val key: String,
    val name: String,
    val description: String,
    val classification: String,
    val systemPrompt: String,
    /**
     * The voice block is an OBJECT, not a name. Rendering it as a string put
     * raw JSON on the page where iOS shows three readable rows.
     */
    val voiceManner: String,
    val voiceClip: String,
    val voiceLine: String,
    val form: String,
    val internal: Boolean,
)

data class PersonaSurface(val personas: List<PersonaEntry>) {
    companion object {
        suspend fun load(config: ServerConfig): PersonaSurface? {
            val json = fetch(config, "/personas/surface") ?: return null
            return PersonaSurface(
                personas = json.optJSONArray("personas").objects().map {
                    PersonaEntry(
                        key = it.optString("key"),
                        name = it.optString("name"),
                        description = it.optString("description"),
                        classification = it.optString("classification"),
                        systemPrompt = it.optString("system_prompt"),
                        voiceManner = it.optJSONObject("voice")
                            ?.optString("voice_description").orEmpty(),
                        voiceClip = it.optJSONObject("voice")
                            ?.optString("reference_audio").orEmpty()
                            .substringAfterLast('/'),
                        voiceLine = it.optJSONObject("voice")
                            ?.optString("reference_text").orEmpty(),
                        form = it.optString("form"),
                        internal = it.optBoolean("internal"),
                    )
                }
            )
        }
    }
}

// ---- sessions -------------------------------------------------------------

/**
 * A conversation, from either shelf.
 *
 * The house keeps two: `/sessions` is the live record (every conversation,
 * synced or not) and `/journal/sessions` is what has been written up. They
 * overlap, so [SessionMerge] dedupes them the way iOS does rather than showing
 * the same afternoon twice.
 */
data class SessionRow(
    val sessionId: String,
    val title: String,
    val date: String,
    val persona: String,
    val turns: Int,
    val summary: String,
    val synced: Boolean,
    /**
     * A journal row resumes by SLUG, a live record by session id. They are
     * different verbs against the house and picking the wrong one silently
     * resumes nothing.
     */
    val fromJournal: Boolean,
    val slug: String = "",
) {
    /** Nothing to pick back up when no transcript was kept. */
    val resumable: Boolean
        get() = if (fromJournal) slug.isNotEmpty() else sessionId.isNotEmpty() && turns > 0
}

data class SessionsSurface(val rows: List<SessionRow>) {
    /** Newest first, grouped by day, as the Sessions screen renders them. */
    fun grouped(): List<Pair<String, List<SessionRow>>> =
        rows.groupBy { it.date.take(10) }
            .toList()
            .sortedByDescending { it.first }
            .map { (day, rows) -> day to rows }

    companion object {
        suspend fun load(config: ServerConfig): SessionsSurface {
            val live = fetch(config, "/sessions")?.optJSONArray("sessions").objects().map {
                SessionRow(
                    sessionId = it.optString("session_id"),
                    title = it.optString("title").ifEmpty { "Untitled" },
                    date = it.optString("last_turn_at").ifEmpty { it.optString("started_at") },
                    persona = it.optString("persona"),
                    turns = it.optInt("turns"),
                    summary = "",
                    synced = it.optBoolean("synced"),
                    fromJournal = false,
                )
            }
            val written = fetch(config, "/journal/sessions")
                ?.optJSONArray("sessions").objects().map {
                    SessionRow(
                        sessionId = it.optString("session_id"),
                        title = it.optString("title").ifEmpty { "Untitled" },
                        date = it.optString("date"),
                        persona = it.optString("persona"),
                        turns = 0,
                        summary = it.optString("summary"),
                        fromJournal = true,
                        synced = true,
                        slug = it.optString("slug")
                            .ifEmpty { it.optString("thought_slug") },
                    )
                }

            // Dedupe by session id, preferring the written-up copy: it carries
            // the summary, and a row with a summary is the better one to show.
            val byId = linkedMapOf<String, SessionRow>()
            for (row in live) if (row.sessionId.isNotEmpty()) byId[row.sessionId] = row
            for (row in written) {
                if (row.sessionId.isEmpty()) continue
                val existing = byId[row.sessionId]
                byId[row.sessionId] = if (existing == null) row else row.copy(turns = existing.turns)
            }
            return SessionsSurface(byId.values.sortedByDescending { it.date })
        }
    }
}

// ---- journal ---------------------------------------------------------------

/** One page in a book: a session, a review, or a durable fact. */
data class JournalEntry(
    val title: String,
    val date: String,
    val synopsis: String,
    val persona: String,
    val slug: String = "",
    val hasTranscript: Boolean = false,
)

/**
 * A book on the shelf. [shelf] decides which room it stands in.
 *
 * A project with one page or fewer is a SEEDLING and stands in the
 * conservatory rather than the forge: the library is arranged by how alive a
 * thing is, not by what kind of thing it is.
 */
data class JournalBook(
    val title: String,
    val pages: Int,
    val summary: String,
    val entries: List<JournalEntry> = emptyList(),
    val shelf: Shelf = Shelf.PROJECT,
) {
    enum class Shelf { HEART, LIFE, PROJECT, SEEDLING }

    val isSeedling: Boolean get() = pages <= 1
}

/**
 * The library, in Selene's locked room order. Ported from the iOS
 * `JournalLibrary`.
 *
 * The Heart's three volumes do not exist on the server: they are composed
 * here from the sessions, reviews and facts endpoints, because they are
 * VIEWS of a living record rather than files on a shelf.
 */
data class JournalLibrary(
    val heart: List<JournalBook>,
    val life: List<JournalBook>,
    val projects: List<JournalBook>,
    val seedlings: List<JournalBook>,
) {
    val isEmpty: Boolean
        get() = heart.isEmpty() && life.isEmpty() &&
            projects.isEmpty() && seedlings.isEmpty()

    companion object {
        suspend fun load(config: ServerConfig): JournalLibrary {
            val shelf = fetch(config, "/journal/shelf")
            val sessions = fetch(config, "/journal/sessions")
            val reviews = fetch(config, "/journal/reviews")
            val facts = fetch(config, "/journal/facts")

            fun books(key: String, shelfKind: JournalBook.Shelf) =
                shelf?.optJSONArray(key).objects().map {
                    JournalBook(
                        title = it.optString("title"),
                        pages = it.optInt("pages"),
                        summary = it.optString("summary"),
                        shelf = shelfKind,
                    )
                }

            val allProjects = books("projects", JournalBook.Shelf.PROJECT)
            return JournalLibrary(
                heart = livingVolumes(sessions, reviews, facts),
                life = books("life", JournalBook.Shelf.LIFE),
                projects = allProjects
                    .filterNot { it.isSeedling }
                    .sortedByDescending { it.pages },
                seedlings = allProjects
                    .filter { it.isSeedling }
                    .map { it.copy(shelf = JournalBook.Shelf.SEEDLING) },
            )
        }

        /**
         * The three volumes that live and grow: the Journal, what the house
         * knows about you, and Selene's nightly consolidations.
         */
        private fun livingVolumes(
            sessions: JSONObject?,
            reviews: JSONObject?,
            facts: JSONObject?,
        ): List<JournalBook> {
            val out = mutableListOf<JournalBook>()

            val sessionRows = sessions?.optJSONArray("sessions").objects()
            if (sessionRows.isNotEmpty()) {
                out.add(
                    JournalBook(
                        title = "The Journal",
                        pages = sessionRows.size,
                        summary = "The working record of what was built, decided " +
                            "and left open on each day. This volume and the Ledger " +
                            "are the two that grow almost daily.",
                        entries = sessionRows.map {
                            JournalEntry(
                                title = it.optString("title").ifEmpty { "Session" },
                                date = it.optString("date"),
                                synopsis = it.optString("summary"),
                                persona = it.optString("persona")
                                    .substringBefore(' ')
                                    .ifEmpty { "Sulivan" },
                                slug = it.optString("slug")
                                    .ifEmpty { it.optString("thought_slug") },
                                hasTranscript = it.optBoolean("has_transcript"),
                            )
                        },
                        shelf = JournalBook.Shelf.HEART,
                    )
                )
            }

            // "- [2026-05-28] [tag] the fact itself"
            val factLines = facts?.optString("body").orEmpty()
                .split("\n")
                .filter { it.startsWith("- [") }
            if (factLines.isNotEmpty()) {
                out.add(
                    JournalBook(
                        title = "About you",
                        pages = factLines.size,
                        summary = "What the house knows about you, held as durable " +
                            "facts rather than transcript. One living page, " +
                            "refreshed rather than appended. Curation is " +
                            "conversational: ask Selene to forget something and " +
                            "she will.",
                        entries = factLines.map { line ->
                            val date = line.drop(3).takeWhile { it != ']' }
                            val text = line.dropWhile { it != ']' }.drop(1).trim()
                            JournalEntry(
                                title = text.take(70),
                                date = date,
                                synopsis = text,
                                persona = "Selene",
                            )
                        },
                        shelf = JournalBook.Shelf.HEART,
                    )
                )
            }

            val reviewRows = reviews?.optJSONArray("reviews").objects()
            if (reviewRows.isNotEmpty()) {
                out.add(
                    JournalBook(
                        title = "Selene's Ledger",
                        pages = reviewRows.size,
                        summary = "Nightly consolidations. Each one reads the day " +
                            "and keeps what will still matter next month. Where " +
                            "the Journal records, the Ledger decides what endures.",
                        entries = reviewRows
                            .sortedByDescending { it.optString("date") }
                            .map {
                                JournalEntry(
                                    title = "Daily review",
                                    date = it.optString("date"),
                                    synopsis = it.optString("body"),
                                    persona = "Selene",
                                )
                            },
                        shelf = JournalBook.Shelf.HEART,
                    )
                )
            }
            return out
        }
    }
}

// ---- the health probe ------------------------------------------------------

data class HealthProbe(
    val latencyMs: Long,
    val brainReady: Boolean,
    val brainBackend: String,
)

/**
 * Ask a house whether it is there. Settings' Test button uses this against
 * whatever is TYPED rather than what is saved, so a wrong address is found
 * without taking the live socket down.
 */
suspend fun probeHealth(config: ServerConfig): HealthProbe? {
    val started = System.currentTimeMillis()
    val json = fetch(config, "/health") ?: return null
    return HealthProbe(
        latencyMs = System.currentTimeMillis() - started,
        brainReady = json.optBoolean("brain_ready"),
        brainBackend = json.optString("brain_backend").ifEmpty { "unknown" },
    )
}

/**
 * Write persona edits back. The house takes a map of persona key to the
 * fields that changed, so an untouched field is absent rather than sent
 * back at its current value.
 *
 * Batched behind Save on purpose: a persona is hours of writing, and a
 * field-by-field autosave turns a stray keystroke into a permanent edit.
 */
suspend fun applyPersonaEdits(
    config: ServerConfig,
    key: String,
    edits: JSONObject,
): String? = withContext(Dispatchers.IO) {
    val url = config.url("/personas/apply") ?: return@withContext "No house configured."
    val body = JSONObject().put("edits", JSONObject().put(key, edits))
    val builder = okhttp3.Request.Builder()
        .url(url)
        .post(
            body.toString().toRequestBody("application/json".toMediaType())
        )
    config.authorize(builder)
    try {
        client.newCall(builder.build()).execute().use { response ->
            val text = response.body?.string().orEmpty()
            if (!response.isSuccessful) return@withContext "The house refused the change."
            val json = JSONObject(text)
            if (json.optBoolean("ok", true)) null
            else json.optString("error").ifEmpty { "The house refused the change." }
        }
    } catch (e: Exception) {
        "Could not reach the house."
    }
}
