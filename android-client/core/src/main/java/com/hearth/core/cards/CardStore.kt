package com.hearth.core.cards

import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject
import java.util.UUID

/**
 * One generative-UI card, as the house describes it. Ported from the iOS
 * `UiComponentDescriptor`.
 *
 * The id is unique PER INSTANCE, not per type. The feed is a transcript, so
 * two emits of the same type are two entries that both keep their place: the
 * desktop learned live that keying by type made the earlier card vanish and
 * the newer one appear to "move down".
 *
 * Decoding is tolerant by contract: unknown keys are ignored, missing keys
 * fall back, and only a missing type or an unspeakable version makes a
 * payload unusable. An unknown TYPE parses fine and renders nothing, which is
 * what lets the house ship a new card before the client learns it.
 */
data class CardDescriptor(
    val id: String,
    val type: String,
    val version: Int,
    val props: JSONObject,
    val receivedAt: Long,
) {
    // Defensive accessors. Props are strings end to end on the wire, but a
    // handler that sends a number must not blank the field.
    fun str(key: String, fallback: String = ""): String {
        if (!props.has(key) || props.isNull(key)) return fallback
        return props.optString(key, fallback).ifEmpty { fallback }
    }

    fun int(key: String, fallback: Int = 0): Int = props.optInt(key, fallback)

    fun long(key: String, fallback: Long = 0L): Long = props.optLong(key, fallback)

    fun objList(key: String): List<JSONObject> {
        val array = props.optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optJSONObject(it) }
    }

    fun strList(key: String): List<String> {
        val array = props.optJSONArray(key) ?: return emptyList()
        return (0 until array.length()).mapNotNull { array.optString(it).ifEmpty { null } }
    }

    companion object {
        const val SUPPORTED_VERSION = 1

        // The server vocabulary, from backend tools/card_catalog.yaml.
        const val CLOCK = "clock"
        const val WEATHER = "weather_card"
        const val TIMER = "timer_card"
        const val BRIEF_TEXT = "brief_text"
        const val CAPTIONS = "captions"
        const val SLIDESHOW = "slideshow"
        const val GENERATED_VIEW = "generated_view"
        const val IMAGE = "image_card"
        const val TERMINAL = "terminal_card"
        const val PERMISSION = "permission_card"
        const val CHOICE = "choice_card"

        fun from(raw: JSONObject): CardDescriptor? {
            val type = raw.optString("type").trim()
            if (type.isEmpty()) return null
            val version = raw.optInt("version", SUPPORTED_VERSION)
            if (version != SUPPORTED_VERSION) return null
            return CardDescriptor(
                id = UUID.randomUUID().toString(),
                type = type,
                version = version,
                props = raw.optJSONObject("props") ?: JSONObject(),
                receivedAt = System.currentTimeMillis(),
            )
        }
    }
}

/**
 * The cards the house has drawn this session. Ported from the iOS
 * `CardStore`.
 *
 * The op vocabulary is the Echo client's (upsert, clear, clear_all; an absent
 * op means upsert), but the RETENTION model is the desktop's: cards are
 * TRANSCRIPT HISTORY, not a status board. Every upsert APPENDS a new
 * instance, and a re-emit of a type never replaces or moves a card the person
 * has already scrolled past. `clear` still drops every instance of a type.
 */
class CardStore(private val scope: CoroutineScope) {

    private val _cards = MutableStateFlow<List<CardDescriptor>>(emptyList())

    /** Card history, oldest first. Many instances per type are expected. */
    val cards: StateFlow<List<CardDescriptor>> = _cards.asStateFlow()

    /** Pending expiry jobs, keyed by card INSTANCE id. */
    private val ttlJobs = mutableMapOf<String, Job>()

    fun apply(raw: JSONObject) {
        when (val op = raw.optString("op").ifEmpty { "upsert" }) {
            "clear" -> {
                val type = raw.optString("type").trim()
                if (type.isNotEmpty()) dismissType(type)
                return
            }

            "clear_all" -> {
                clearAll()
                return
            }

            "upsert" -> Unit

            // Unknown op: ignore, for forward compatibility.
            else -> {
                Log.i(TAG, "unknown card op '$op'")
                return
            }
        }

        val card = CardDescriptor.from(raw) ?: run {
            Log.i(TAG, "card payload unusable (bad type or version); ignored")
            return
        }

        val next = _cards.value + card
        _cards.value =
            if (next.size > MAX_CARDS) {
                next.takeLast(MAX_CARDS).also { kept ->
                    val keptIds = kept.map { it.id }.toSet()
                    next.filterNot { it.id in keptIds }.forEach { cancelTtl(it.id) }
                }
            } else {
                next
            }

        Log.i(TAG, "append ${card.type} (${_cards.value.size} in feed)")
        scheduleTtl(raw, card)
    }

    fun clearAll() {
        ttlJobs.values.forEach { it.cancel() }
        ttlJobs.clear()
        _cards.value = emptyList()
    }

    /** Dismiss one instance: a close button, or a gallery pick. */
    fun dismiss(id: String) {
        cancelTtl(id)
        _cards.value = _cards.value.filterNot { it.id == id }
    }

    /** Drop every instance of a type: the `clear` op. */
    fun dismissType(type: String) {
        _cards.value.filter { it.type == type }.forEach { cancelTtl(it.id) }
        _cards.value = _cards.value.filterNot { it.type == type }
    }

    /** `ttl_s` is a top-level field; tolerate a number or a numeric string. */
    private fun scheduleTtl(raw: JSONObject, card: CardDescriptor) {
        val ttl = when {
            raw.has("ttl_s") -> raw.optDouble("ttl_s", 0.0)
            else -> 0.0
        }
        if (ttl <= 0) return
        ttlJobs[card.id] = scope.launch {
            delay((ttl * 1000).toLong())
            _cards.value = _cards.value.filterNot { it.id == card.id }
            ttlJobs.remove(card.id)
            Log.i(TAG, "expired ${card.type} (ttl=${ttl}s)")
        }
    }

    private fun cancelTtl(id: String) {
        ttlJobs.remove(id)?.cancel()
    }

    companion object {
        private const val TAG = "HearthCards"

        /** Matches the desktop's slice(-40). */
        private const val MAX_CARDS = 40
    }
}
