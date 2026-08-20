package com.hearth.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Surface
import com.hearth.app.ui.theme.HearthTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.lifecycle.lifecycleScope
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.rememberDrawerState
import com.hearth.app.ui.FirstRunScreen
import com.hearth.app.ui.HearthMainScreen
import com.hearth.app.ui.HouseDestination
import com.hearth.app.ui.HouseShelf
import com.hearth.app.ui.surfaces.AppsScreen
import com.hearth.app.ui.surfaces.JournalScreen
import com.hearth.app.ui.surfaces.PersonaScreen
import com.hearth.app.ui.surfaces.SessionsScreen
import com.hearth.app.ui.surfaces.SettingsScreen
import com.hearth.core.config.Pairing
import kotlinx.coroutines.launch
import androidx.core.content.ContextCompat
import com.hearth.core.audio.SpeechRecognitionManager
import com.hearth.core.audio.TtsStreamPlayer
import com.hearth.core.models.HearthState
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
    private lateinit var micPermission: ActivityResultLauncher<String>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        config = ServerConfig.get(this)
        socket = HearthWebSocketClient(config)
        viewModel = ChatViewModel(
            config = config,
            scope = lifecycleScope,
            socket = socket,
            player = TtsStreamPlayer(),
            speech = SpeechRecognitionManager(this),
        )

        // One deliberate moment for the mic, as on iOS, rather than a system
        // alert on the first tap of the button.
        micPermission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { }

        setContent {
            HearthTheme {
                Surface(modifier = Modifier.fillMaxSize()) {
                    // Null until the Keystore has been read on a background
                    // thread. Reading it during composition is what stalled
                    // the first frame for seconds on a real device.
                    var ready by remember { mutableStateOf<Boolean?>(null) }
                    LaunchedEffect(Unit) {
                        config.warm()
                        ready = config.isConfigured && config.isPaired
                        if (ready == true) viewModel.connect()
                    }

                    if (ready == null) {
                        Splash()
                    } else if (ready == false) {
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
                        val caption by viewModel.caption.collectAsState()
                        val ttsLevel by viewModel.ttsAmplitude.collectAsState()
                        val micLevel by viewModel.micLevel.collectAsState()
                        val partial by viewModel.partialTranscript.collectAsState()
                        val palette by viewModel.palette.collectAsState()
                        val faceGeometry by viewModel.faceGeometry.collectAsState()
                        val faceCue by viewModel.faceCue.collectAsState()

                        val personas by viewModel.personas.collectAsState()
                        val drawerState = rememberDrawerState(DrawerValue.Closed)
                        val scope = rememberCoroutineScope()
                        var destination by remember {
                            mutableStateOf<HouseDestination?>(null)
                        }

                        // A live turn holds the screen awake. Without this the
                        // display times out while the house is thinking, the
                        // activity stops, the socket is torn down, and the
                        // follow-up the operator speaks has nowhere to go.
                        // That is exactly what happened on the first device
                        // run: the house logged "1 turns, reason=disconnect".
                        KeepScreenOn(
                            state != HearthState.IDLE && state != HearthState.LOADING
                        )

                        // A surface is a full-screen visit, as on iOS: the
                        // stage stays underneath and Back returns to it.
                        when (destination) {
                            HouseDestination.SESSIONS -> SessionsScreen(
                                config = config,
                                onResume = { id ->
                                    viewModel.resumeSession(id)
                                    destination = null
                                },
                                onBack = { destination = null },
                            )

                            HouseDestination.JOURNAL ->
                                JournalScreen(config) { destination = null }

                            HouseDestination.APPS ->
                                AppsScreen(config) { destination = null }

                            HouseDestination.PERSONA ->
                                PersonaScreen(config) { destination = null }

                            HouseDestination.SETTINGS -> SettingsScreen(
                                config = config,
                                onForget = {
                                    Pairing.forget(config)
                                    destination = null
                                    ready = false
                                },
                                onBack = { destination = null },
                            )

                            null -> ModalNavigationDrawer(
                                drawerState = drawerState,
                                drawerContent = {
                                    HouseShelf(
                                        personas = personas,
                                        currentPersona = persona,
                                        onPersona = {
                                            viewModel.switchPersona(it)
                                            scope.launch { drawerState.close() }
                                        },
                                        onOpen = {
                                            destination = it
                                            scope.launch { drawerState.close() }
                                        },
                                        onNewSession = {
                                            viewModel.newSession()
                                            scope.launch { drawerState.close() }
                                        },
                                    )
                                },
                            ) {
                                HearthMainScreen(
                                    state = state,
                                    connected = connected,
                                    personaName = persona,
                                    thinkingStage = stage,
                                    messages = messages,
                                    palette = palette,
                                    faceGeometry = faceGeometry,
                                    faceCue = faceCue,
                                    caption = caption,
                                    ttsAmplitude = ttsLevel,
                                    micLevel = micLevel,
                                    partialTranscript = partial,
                                    onSend = viewModel::sendText,
                                    onMic = {
                                        if (hasMic()) viewModel.toggleListening()
                                        else micPermission.launch(Manifest.permission.RECORD_AUDIO)
                                    },
                                    onShelf = { scope.launch { drawerState.open() } },
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    /**
     * Hold the display awake while a turn is live. The window flag is the
     * right tool rather than a wake lock: it needs no permission and it dies
     * with the window.
     */
    @androidx.compose.runtime.Composable
    private fun KeepScreenOn(keep: Boolean) {
        androidx.compose.runtime.DisposableEffect(keep) {
            if (keep) {
                window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
            onDispose {
                window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    @androidx.compose.runtime.Composable
    private fun Splash() {
        androidx.compose.foundation.layout.Box(
            modifier = Modifier.fillMaxSize(),
            contentAlignment = androidx.compose.ui.Alignment.Center,
        ) {
            androidx.compose.material3.Text(
                "Hearth",
                style = androidx.compose.material3.MaterialTheme.typography.headlineLarge,
            )
        }
    }

    private fun hasMic(): Boolean = ContextCompat.checkSelfPermission(
        this, Manifest.permission.RECORD_AUDIO
    ) == PackageManager.PERMISSION_GRANTED

    override fun onStart() {
        super.onStart()
        // isPaired can touch the Keystore, so the check happens off the main
        // thread; warm() is a no-op once primed.
        lifecycleScope.launch {
            config.warm()
            if (config.isConfigured && config.isPaired) viewModel.enterForeground()
        }
    }

    override fun onStop() {
        super.onStop()
        viewModel.enterBackground()
    }
}
