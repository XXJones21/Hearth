package com.hearth.core.models

import java.util.UUID

/** One line in the transcript. Ported from iOS `ChatMessage.swift`. */
data class ChatMessage(
    val id: String = UUID.randomUUID().toString(),
    val role: Role,
    val text: String,
    val timestamp: Long = System.currentTimeMillis(),
) {
    enum class Role { USER, AI, SYSTEM }
}
