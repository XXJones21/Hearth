package com.hearth.core.config

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Trading a six-digit code for a device token. Ported from the iOS
 * `Pairing.swift`.
 *
 * The house exempts loopback and requires a token from everything else, and a
 * phone is never loopback. So pairing is not an optional hardening step on
 * this client, it is how the phone gets in at all.
 *
 * Deliberately the ONE request in the client that does not carry a token:
 * `/pair` is the door, and a device asking to be let in has nothing to present
 * yet. Everything after this goes through [ServerConfig.request].
 */
sealed class PairingError(message: String) : Exception(message) {

    data object NotConfigured : PairingError("No house address yet.")

    /**
     * The house answers one way for wrong, expired and locked-out, because
     * telling them apart is a free hint to anyone guessing. The client must
     * not invent a more specific story than it was told.
     */
    data object Rejected :
        PairingError("That code was not accepted. Ask the house for a new one.")

    class Unreachable(detail: String) : PairingError(detail)
}

object Pairing {

    private val client = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(10, TimeUnit.SECONDS)
        .build()

    private val JSON = "application/json".toMediaType()

    /**
     * Redeem a code. On success the token is stored and every later request
     * carries it.
     *
     * [deviceName] is what the person will see in the house's device list when
     * they come to revoke something, so it should be the phone's own name:
     * "which of these three is the one I lost" is the only question that list
     * has to answer.
     */
    suspend fun pair(config: ServerConfig, code: String, deviceName: String): String =
        withContext(Dispatchers.IO) {
            val url = config.url("/pair") ?: throw PairingError.NotConfigured

            val body = JSONObject()
                .put("code", code.trim())
                .put("device_name", deviceName)
                .toString()
                .toRequestBody(JSON)

            val request = Request.Builder().url(url).post(body).build()

            val response = try {
                client.newCall(request).execute()
            } catch (e: Exception) {
                // A house that cannot be reached and a house that refuses are
                // different problems with different fixes -- check the address
                // versus check the code -- so they must not share a message.
                throw PairingError.Unreachable(
                    "Could not reach ${config.address}. Check the address."
                )
            }

            response.use {
                if (it.code == 404) {
                    // A house too old to know about pairing. Saying so beats
                    // "that code was wrong" when the code was never the problem.
                    throw PairingError.Unreachable(
                        "That house does not support pairing yet. " +
                            "Update Hearth on the machine running it."
                    )
                }
                if (!it.isSuccessful) throw PairingError.Rejected

                val payload = it.body?.string().orEmpty()
                val token = try {
                    JSONObject(payload).optString("token")
                } catch (e: Exception) {
                    ""
                }
                if (token.isEmpty()) {
                    throw PairingError.Unreachable(
                        "The house accepted the code but sent no token."
                    )
                }
                config.deviceToken = token
                token
            }
        }

    /**
     * Forget this device's token. The house still lists it until someone
     * revokes it there -- this is the local half only, and the copy around it
     * should not promise more than that.
     */
    fun forget(config: ServerConfig) {
        config.deviceToken = null
    }
}
