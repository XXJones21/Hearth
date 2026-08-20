package com.hearth.core.models

/**
 * The five states a turn moves through, ported from iOS `HearthState.swift`.
 * The whole UI reads from this, and the face director takes it per tick.
 */
enum class HearthState {
    LOADING,
    IDLE,
    LISTENING,
    THINKING,
    SPEAKING,
}
