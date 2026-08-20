package com.hearth.app

import android.app.Application

/**
 * Process entry. Deliberately thin: singletons that need a Context are built
 * here as the client grows (config, token vault, the socket), matching iOS
 * where `HearthApp` only wires the root and lifecycle.
 */
class HearthApp : Application()
