package com.hearth.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import com.hearth.app.ui.theme.HearthTheme
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.LayoutDirection
import androidx.lifecycle.lifecycleScope
import androidx.compose.material3.DrawerValue
import androidx.compose.material3.ModalNavigationDrawer
import androidx.compose.material3.rememberDrawerState
import com.hearth.Appliance
import com.hearth.app.ui.FirstRunScreen
import com.hearth.app.ui.HearthMainScreen
import com.hearth.app.ui.HouseDestination
import com.hearth.app.ui.HouseShelf
import com.hearth.app.ui.PairingReason
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
    private lateinit var speechManager: SpeechRecognitionManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        config = ServerConfig.get(this)
        speechManager = SpeechRecognitionManager(this)
        socket = HearthWebSocketClient(config)
        viewModel = ChatViewModel(
            config = config,
            scope = lifecycleScope,
            socket = socket,
            player = TtsStreamPlayer(),
            speech = speechManager,
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

                    // THE HOUSE REFUSED THIS DEVICE. `ready` is computed once
                    // at startup, from a token that may since have been
                    // revoked or pointed at a different house -- so without
                    // this the stage sits reading "not connected" with no
                    // explanation and no route back, which is exactly what a
                    // paired-then-unpaired phone did.
                    val needsPairing by viewModel.needsPairing.collectAsState()
                    LaunchedEffect(needsPairing) {
                        if (needsPairing && ready == true) ready = false
                    }

                    // THE WAY BACK IN, and it lives OUT HERE rather than
                    // beside the stage on purpose. An appliance that boots
                    // unpaired -- house down, token revoked -- still pins
                    // itself on resume, and the first version of this put the
                    // only escape on the paired stage, where a first-run
                    // client never reaches it. That is the exact shape of the
                    // failure this whole hatch exists for.
                    var handBack by remember { mutableStateOf(false) }
                    if (handBack) {
                        AlertDialog(
                            onDismissRequest = { handBack = false },
                            title = { Text("Hand the phone back?") },
                            text = {
                                Text(
                                    "Unpins Hearth and opens Developer " +
                                        "options, so USB debugging can be " +
                                        "turned on without adb. The house " +
                                        "keeps running, and the kiosk closes " +
                                        "again the next time Hearth comes " +
                                        "forward."
                                )
                            },
                            confirmButton = {
                                TextButton(onClick = {
                                    handBack = false
                                    Appliance.handBack(this@MainActivity)
                                }) { Text("Hand it back") }
                            },
                            dismissButton = {
                                TextButton(onClick = { handBack = false }) {
                                    Text("Cancel")
                                }
                            },
                        )
                    }

                    if (ready == null) {
                        Splash()
                    } else if (ready == false) {
                        FirstRunScreen(
                            config = config,
                            // Re-pairing rather than a first run: the house is
                            // known and it turned this device away.
                            reason = if (needsPairing) PairingReason.REFUSED
                            else PairingReason.FIRST_RUN,
                            // The unpaired client's only way out: hold the
                            // title. There is no house button on this screen.
                            onTitleHold = {
                                if (Appliance.isOwner(this@MainActivity)) {
                                    handBack = true
                                }
                            },
                            onDone = {
                                ready = true
                                // Pairing just landed, so onStart has already
                                // been and gone without an address to dial.
                                // Without this the stage opens reading "Not
                                // connected" and waits for a foreground that
                                // never comes.
                                viewModel.pairedAgain()
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
                        val tools by viewModel.activeTools.collectAsState()
                        val cards by viewModel.cardStore.cards.collectAsState()
                        val palette by viewModel.palette.collectAsState()
                        val faceGeometry by viewModel.faceGeometry.collectAsState()
                        val personaForm by viewModel.personaForm.collectAsState()
                        val faceCue by viewModel.faceCue.collectAsState()

                        val personas by viewModel.personas.collectAsState()
                        val drawerState = rememberDrawerState(DrawerValue.Closed)
                        val scope = rememberCoroutineScope()
                        var destination by remember {
                            mutableStateOf<HouseDestination?>(null)
                        }
                        // The transcript is opt-in, as on iOS: the resting
                        // state is the stage alone, because history does not
                        // need to be on screen while the persona is talking.
                        var transcriptShown by remember { mutableStateOf(false) }
                        var autoReconnect by remember { mutableStateOf(true) }

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
                                // Session verbs need a live socket and no turn
                                // in flight; the screen dims rather than
                                // letting a tap fail into a system row.
                                canAct = connected && state != HearthState.THINKING,
                                onResumeSession = { id ->
                                    viewModel.resumeSession(id)
                                    destination = null
                                },
                                onResumeSlug = { slug ->
                                    viewModel.resumeSlug(slug)
                                    destination = null
                                },
                                onNewSession = {
                                    viewModel.newSession()
                                    destination = null
                                },
                                onBack = { destination = null },
                            )

                            HouseDestination.JOURNAL -> JournalScreen(
                                config = config,
                                onStartSession = { title ->
                                    viewModel.startTopicSession(title)
                                    destination = null
                                },
                                onBack = { destination = null },
                            )

                            HouseDestination.APPS -> AppsScreen(
                                config = config,
                                speechAvailable = speechManager.isAvailable,
                                onCards = { },
                                onBack = { destination = null },
                            )

                            HouseDestination.PERSONA ->
                                PersonaScreen(config) { destination = null }

                            HouseDestination.SETTINGS -> SettingsScreen(
                                config = config,
                                // The hold on the house button is the backup;
                                // this row is the route a person can FIND.
                                // Null off the appliance, where the row would
                                // be an unpin with no kiosk behind it.
                                onHandBack = if (Appliance.isOwner(this@MainActivity)) {
                                    { handBack = true }
                                } else null,
                                autoReconnect = autoReconnect,
                                onAutoReconnect = {
                                    autoReconnect = it
                                    viewModel.setAutoReconnect(it)
                                },
                                onApply = {
                                    destination = null
                                    // Committing a NEW HOST surrenders the old
                                    // house's key, so there is nothing to dial
                                    // with. Going to pairing beats redialling
                                    // into a refusal and waiting to be told.
                                    if (config.isPaired) viewModel.reconnectNow()
                                    else ready = false
                                },
                                onPair = {
                                    destination = null
                                    ready = false
                                },
                                onForget = {
                                    Pairing.forget(config)
                                    destination = null
                                    ready = false
                                },
                                onBack = { destination = null },
                            )

                            // ONLY the drawer host is right-to-left, and its
                            // contents are flipped back inside. Wrapping the
                            // whole branch set flipped every surface screen
                            // too: titles right-aligned, Back on the wrong
                            // side, and sentences with the full stop leading.
                            null -> CompositionLocalProvider(
                                LocalLayoutDirection provides LayoutDirection.Rtl
                            ) {
                            ModalNavigationDrawer(
                                drawerState = drawerState,
                                drawerContent = {
                                    // The shelf comes in from the RIGHT, as on
                                    // iOS. Compose only opens drawers from the
                                    // start edge, so the drawer is composed in
                                    // RTL and its contents flipped back.
                                    CompositionLocalProvider(
                                        LocalLayoutDirection provides LayoutDirection.Ltr
                                    ) {
                                        HouseShelf(
                                            personas = personas,
                                            currentPersona = persona,
                                            connected = connected,
                                            onPersona = {
                                                viewModel.switchPersona(it)
                                                scope.launch { drawerState.close() }
                                            },
                                            onOpen = {
                                                destination = it
                                                scope.launch { drawerState.close() }
                                            },
                                            transcriptShown = transcriptShown,
                                            onToggleTranscript = {
                                                transcriptShown = it
                                                scope.launch { drawerState.close() }
                                            },
                                        )
                                    }
                                },
                            ) {
                                CompositionLocalProvider(
                                    LocalLayoutDirection provides LayoutDirection.Ltr
                                ) {
                                HearthMainScreen(
                                    state = state,
                                    connected = connected,
                                    personaName = persona,
                                    activeTools = tools,
                                    messages = messages,
                                    palette = palette,
                                    faceGeometry = faceGeometry,
                                    personaForm = personaForm,
                                    faceCue = faceCue,
                                    caption = caption,
                                    cards = cards,
                                    ttsAmplitude = ttsLevel,
                                    micLevel = micLevel,
                                    partialTranscript = partial,
                                    transcriptShown = transcriptShown,
                                    onChoice = viewModel::pickChoice,
                                    onSend = viewModel::sendText,
                                    onTalk = {
                                        if (hasMic()) viewModel.toggleListening()
                                        else micPermission.launch(Manifest.permission.RECORD_AUDIO)
                                    },
                                    onStageTap = {
                                        when (state) {
                                            HearthState.SPEAKING -> viewModel.interruptSpeaking()
                                            HearthState.LISTENING -> viewModel.discardListening()
                                            HearthState.IDLE ->
                                                if (connected) {
                                                    if (hasMic()) viewModel.toggleListening()
                                                    else micPermission.launch(
                                                        Manifest.permission.RECORD_AUDIO
                                                    )
                                                }
                                            else -> Unit
                                        }
                                    },
                                    onShelf = { scope.launch { drawerState.open() } },
                                    onShelfHold = {
                                        if (Appliance.isOwner(this@MainActivity)) {
                                            handBack = true
                                        }
                                    },
                                )
                                }
                            }
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

    override fun onResume() {
        super.onResume()
        // On the appliance this applies the kiosk policy and pins; on every
        // other device it returns on its first line. Resume rather than
        // create, because startLockTask wants a foreground activity.
        com.hearth.Appliance.enterKiosk(this)
    }

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
