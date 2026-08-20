package com.hearth.core.surfaces

import com.hearth.core.config.ServerConfig
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
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
    val voice: String,
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
                        voice = it.optString("voice"),
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
    val fromJournal: Boolean,
)

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

// ---- journal --------------------------------------------------------------

data class JournalBook(
    val title: String,
    val summary: String,
    val pages: Int,
    val entries: Int,
)

/**
 * The shelf, in the house's own two halves: what you are building
 * (`projects`) and what you are living (`life`).
 */
data class JournalShelf(
    val projects: List<JournalBook>,
    val life: List<JournalBook>,
) {
    companion object {
        private fun books(array: JSONArray?): List<JournalBook> =
            array.objects().map {
                JournalBook(
                    title = it.optString("title"),
                    summary = it.optString("summary"),
                    pages = it.optInt("pages"),
                    entries = it.optInt("entries"),
                )
            }

        suspend fun load(config: ServerConfig): JournalShelf? {
            val json = fetch(config, "/journal/shelf") ?: return null
            return JournalShelf(
                projects = books(json.optJSONArray("projects")),
                life = books(json.optJSONArray("life")),
            )
        }
    }
}
