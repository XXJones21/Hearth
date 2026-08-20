package com.hearth.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import com.hearth.app.ui.FirstRunScreen
import com.hearth.app.ui.HearthMainScreen
import com.hearth.core.config.ServerConfig
import com.hearth.core.transport.HearthWebSocketClient
import com.hearth.core.viewmodel.ChatViewModel

/**
 * The single window, branching the way iOS `HearthApp` does: an unconfigured
 * or unpaired client shows first run and never dials, everything else opens
 * on the stage.
 */
class MainActivity : ComponentActivity() {

    private lateinit var config: ServerConfig
    private lateinit var socket: HearthWebSocketClient
    private lateinit var viewModel: ChatViewModel

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        config = ServerConfig.get(this)
        socket = HearthWebSocketClient(config)
        viewModel = ChatViewModel(config, lifecycleScope, socket)

        setContent {
            MaterialTheme(colorScheme = darkColorScheme()) {
                Surface(modifier = Modifier.fillMaxSize()) {
                    var ready by remember {
                        mutableStateOf(config.isConfigured && config.isPaired)
                    }
                    if (!ready) {
                        FirstRunScreen(
                            config = config,
                            onDone = {
                                ready = true
                                // Pairing just landed, so onStart has already
                                // been and gone without an address to dial.
                                // Without this the stage opens reading "Not
                                // connected" and waits for a foreground that
                                // never comes.
                                viewModel.connect()
                            },
                        )
                    } else {
                        val state by viewModel.state.collectAsState()
                        val connected by viewModel.connected.collectAsState()
                        val persona by viewModel.personaName.collectAsState()
                        val stage by viewModel.thinkingStage.collectAsState()
                        val messages by viewModel.messages.collectAsState()

                        HearthMainScreen(
                            state = state,
                            connected = connected,
                            personaName = persona,
                            thinkingStage = stage,
                            messages = messages,
                            onSend = viewModel::sendText,
                        )
                    }
                }
            }
        }
    }

    override fun onStart() {
        super.onStart()
        if (config.isConfigured && config.isPaired) viewModel.enterForeground()
    }

    override fun onStop() {
        super.onStop()
        viewModel.enterBackground()
    }
}
