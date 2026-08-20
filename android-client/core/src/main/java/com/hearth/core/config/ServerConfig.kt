package com.hearth.core.config

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.Request

/**
 * Where the house is, and the one type that builds an origin. Ported from the
 * iOS `ServerConfig.swift`; the parser carries across because it was paid for
 * in bugs.
 *
 * The token lives in EncryptedSharedPreferences (the Keystore-backed
 * counterpart of the iOS Keychain vault) rather than plain preferences, which
 * are readable from an unencrypted backup.
 */
class ServerConfig private constructor(context: Context) {

    private val prefs: SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /**
     * Keystore-backed store for the one secret this client holds.
     *
     * Building this does real Keystore crypto, which takes long enough on a
     * cold start to be a visible stall. It must therefore never be touched
     * from the main thread: [warm] primes it on a background dispatcher and
     * [cachedToken] answers every later read from memory.
     */
    private val secure: SharedPreferences by lazy {
        val key = MasterKey.Builder(context.applicationContext)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context.applicationContext,
            SECURE_PREFS,
            key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    /**
     * **There is deliberately no default host.**
     *
     * A phone supervises nothing and is never the machine running the backend,
     * so neither available default is honest: 127.0.0.1 on a phone is the
     * phone, and a LAN literal is one machine on one home network compiled
     * into a product. Unset is a distinct state rather than a missing value,
     * and the app in that state does not dial: it renders the bundled persona
     * and asks where the house is.
     */
    var serverHost: String?
        get() = prefs.getString(KEY_HOST, null)?.takeIf { it.isNotEmpty() }
        set(value) {
            val trimmed = value?.trim()
            prefs.edit().apply {
                if (!trimmed.isNullOrEmpty()) putString(KEY_HOST, trimmed) else remove(KEY_HOST)
            }.apply()
        }

    var serverPort: Int
        get() = prefs.getInt(KEY_PORT, 0).takeIf { it > 0 } ?: DEFAULT_PORT
        set(value) = prefs.edit().putInt(KEY_PORT, value).apply()

    /**
     * The device token this phone was given when it paired, or null. A house
     * exempts loopback and requires a token from everything else, so a phone
     * always needs one.
     */
    @Volatile
    private var cachedToken: String? = null

    @Volatile
    private var tokenLoaded = false

    var deviceToken: String?
        get() {
            if (tokenLoaded) return cachedToken
            // A read before warm() finished. Rare (the UI waits on warm), but
            // it must answer correctly rather than lie, so it pays the cost
            // once and caches.
            cachedToken = secure.getString(KEY_TOKEN, null)?.takeIf { it.isNotEmpty() }
            tokenLoaded = true
            return cachedToken
        }
        set(value) {
            val trimmed = value?.trim()?.takeIf { it.isNotEmpty() }
            cachedToken = trimmed
            tokenLoaded = true
            secure.edit().apply {
                if (trimmed != null) putString(KEY_TOKEN, trimmed) else remove(KEY_TOKEN)
            }.apply()
        }

    /**
     * Prime the Keystore off the main thread. Called once at startup before
     * anything reads [isPaired]; until it returns, the UI has nothing to show
     * but a splash anyway.
     */
    suspend fun warm() = withContext(Dispatchers.IO) {
        if (!tokenLoaded) {
            cachedToken = secure.getString(KEY_TOKEN, null)?.takeIf { it.isNotEmpty() }
            tokenLoaded = true
        }
    }

    /** True when someone has told this client where the house is. */
    val isConfigured: Boolean get() = serverHost != null

    /**
     * True when this phone has both an address AND a way in. Knowing where the
     * house is and being allowed through its door are two different states,
     * and a client that conflates them shows "connecting" forever instead of
     * "you need to pair".
     */
    val isPaired: Boolean get() = deviceToken != null

    /**
     * What the Connection field shows and accepts: `host` or `host:port`.
     * Clearing it clears the host rather than restoring a build-time default.
     */
    var address: String
        get() {
            val host = serverHost ?: return ""
            return if (serverPort == DEFAULT_PORT) host else "$host:$serverPort"
        }
        set(value) {
            val trimmed = value.trim()
            if (trimmed.isEmpty()) {
                serverHost = null
                serverPort = DEFAULT_PORT
                return
            }
            // Strip a pasted scheme; people paste URLs.
            var v = trimmed
            for (scheme in listOf("ws://", "wss://", "http://", "https://")) {
                if (v.startsWith(scheme)) v = v.removePrefix(scheme)
            }
            v = v.trim('/')

            // Rightmost colon only, and only when what follows is a port -- an
            // IPv6 literal is full of colons and must not be split.
            val colon = v.lastIndexOf(':')
            val port = if (colon >= 0) v.substring(colon + 1).toIntOrNull() else null
            if (colon >= 0 && port != null && port in 1..65535) {
                serverHost = v.substring(0, colon)
                serverPort = port
            } else {
                serverHost = v
                serverPort = DEFAULT_PORT
            }
        }

    /**
     * Commit a new address the way Apply and first run mean it: pointing this
     * phone at a DIFFERENT house also surrenders the old house's token.
     * Presenting house A's token to house B earns a 1008 close and nothing but
     * a reconnect loop behind it. The raw [address] setter stays token-neutral
     * on purpose, because a Test probe must not cost the pairing.
     */
    fun commitAddress(newValue: String) {
        val oldHost = serverHost
        address = newValue
        val newHost = serverHost
        if (oldHost != null && newHost != null && !newHost.equals(oldHost, ignoreCase = true)) {
            deviceToken = null
        }
    }

    /** null until configured, so a caller cannot accidentally dial nowhere. */
    val serverUrl: String? get() = serverHost?.let { "ws://$it:$serverPort" }

    /**
     * The single origin. Everything the server hands over as a relative path
     * resolves against this. Exactly one type constructs an origin and no port
     * literal appears anywhere else in the source; if some asset class is not
     * reachable through the gateway that is a server bug to file, not a second
     * port for the client to learn.
     */
    val httpOrigin: String? get() = serverHost?.let { "http://$it:$serverPort" }

    /**
     * Build a URL against the single origin, or null when no house is
     * configured. Every HTTP call in the client goes through this, so the rule
     * can be checked by grep rather than by reading.
     */
    fun url(path: String): String? = httpOrigin?.let { it + path }

    /**
     * A request against the house, carrying the device token. Every HTTP call
     * goes through this rather than building its own, so "does this carry
     * credentials" is answered by grep instead of by auditing each call site.
     */
    fun request(path: String): Request? {
        val url = url(path) ?: return null
        val builder = Request.Builder().url(url)
        authorize(builder)
        return builder.build()
    }

    /**
     * Attach the token, if there is one. Separate so the WebSocket handshake
     * can use it too.
     */
    fun authorize(builder: Request.Builder) {
        val token = deviceToken ?: return
        builder.header("Authorization", "Bearer $token")
    }

    /**
     * An asset URL with the token in the QUERY STRING, for the one case that
     * cannot send a header. On Android the image loader takes an interceptor,
     * so this is only for a surface that genuinely holds a bare URL; prefer
     * [request] everywhere else. A query string lands in server logs where a
     * header does not.
     */
    fun assetUrl(path: String): String? {
        val base = url(path) ?: return null
        val token = deviceToken ?: return base
        val sep = if (base.contains('?')) "&" else "?"
        return "$base${sep}token=$token"
    }

    companion object {
        private const val PREFS = "hearth.config"
        private const val SECURE_PREFS = "hearth.secure"
        private const val KEY_HOST = "hearth.serverHost"
        private const val KEY_PORT = "hearth.serverPort"
        private const val KEY_TOKEN = "hearth.deviceToken"

        /**
         * 18700 is Hearth's client gateway, and the port is the whole default.
         *
         * NOT 8700. The development machine runs Valinor's stack there, so a
         * Hearth build defaulting to 8700 does not fail -- it connects, and
         * comes up wearing someone else's memory, journal and personas. That
         * is a first run which looks flawless and is the worst outcome
         * available.
         */
        const val DEFAULT_PORT = 18700

        @Volatile
        private var instance: ServerConfig? = null

        fun get(context: Context): ServerConfig =
            instance ?: synchronized(this) {
                instance ?: ServerConfig(context).also { instance = it }
            }
    }
}
