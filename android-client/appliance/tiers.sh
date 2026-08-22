# The strip inventory, sourced by strip.sh and restore.sh. Curated from the
# live XT2321-5 package list on 2026-08-22, not from a generic debloat list:
# every entry below was present on the device when this file was written.
# Format: "package|reason". See wiki/raw/android-appliance-plan.md section 2.

# Do not touch, ever. strip.sh refuses these even if they appear in a tier.
ALLOWLIST=(
    "com.hearth"                            # the appliance itself, and the DPC
    "com.tailscale.ipn"                     # stripping the VPN strands the appliance away from home
    "com.google.android.gms"                # GMS: STT rides it
    "com.google.android.gsf"                # GSF: same
    "com.google.android.tts"                # the LIVE RecognitionService on this Razr (settings get secure voice_recognition_service); STT dies without it
    "com.google.android.inputmethod.latin"  # Gboard, the only keyboard; we do not ship one
    "com.google.android.webview"            # system webview
    "com.android.systemui"                  # the render surface
    "com.android.settings"                  # settings
    "com.google.android.packageinstaller"   # the package resolver; sideloads die without it
    "com.google.android.permissioncontroller" # permissions
    "com.google.android.documentsui"        # the file picker
    "com.google.android.providers.media.module" # media storage
    "com.google.android.networkstack"       # wifi and network stack, all four
    "com.google.android.networkstack.tethering"
    "com.google.android.captiveportallogin"
    "com.google.android.wifi.resources"
    "com.google.android.as"                 # Android System Intelligence; backs speech and caption pieces
    "com.motorola.ccc.ota"                  # the OTA path stays
    "com.theboisclub.pokemonred"            # the operator's Gen 1 recomp, requested keeper
)

# Tier 0: telephony and carrier. Zero risk on a wifi-only appliance with no
# SIM and no phone number.
TIER0=(
    "com.android.dialer|dialer, no SIM"
    "com.google.android.apps.messaging|SMS app, no number"
    "com.android.stk|SIM toolkit, no SIM"
    "com.google.android.ims|carrier services (RCS), no carrier"
    "com.google.android.wfcactivation|wifi calling activation, no carrier"
    "com.google.android.cellbroadcastreceiver|emergency alert UI, no cell service"
    "com.motorola.rcsConfigService|RCS config, no carrier"
    "com.motorola.attvowifi|AT&T VoWiFi, no carrier"
    "com.motorola.att.phone.extensions|AT&T phone extensions"
    "com.motorola.callredirectionservice|call redirection, no calls"
    "com.motorola.easyprefix|dialing prefixes, no calls"
    "com.motorola.appdirectedsmsproxy|SMS proxy, no SMS"
    "com.att.mobilesecurity|AT&T ActiveArmor"
    "com.att.myWireless|myAT&T account app"
    "com.att.iqi|AT&T device analytics"
    "com.att.personalcloud|AT&T cloud backup"
    "com.att.mobile.android.vvm|visual voicemail, no number"
    "com.att.csoiam.mobilekey|AT&T mobile key"
    "com.att.deviceunlock|AT&T unlock app"
    "com.att.dh|AT&T device help"
    "com.motorola.omadm.att|carrier device management, AT&T"
    "com.motorola.omadm.vzw|carrier device management, Verizon leftover"
    "com.motorola.omadm.service|carrier device management core"
    "com.aura.oobe.att|DT Ignite preload installer, AT&T; this is what installed Temu"
    "com.aura.oobe.motorola|DT Ignite preload installer, Motorola"
    "com.aura.jet.att|AT&T preload framework"
    "com.aura.appadvisor.att|AT&T app advisor"
    "com.motorola.iqimotmetrics|carrier IQ metrics"
    "com.motorola.vzw.pco.extensions.pcoreceiver|Verizon leftover"
    "com.motorola.sprint.setupext|Sprint leftover"
    "com.motorola.tmo.settingsext|T-Mobile leftover"
    "com.motorola.tmo.setupext|T-Mobile leftover"
)

# Tier 1: Google apps except what the allowlist keeps. Play Store and the
# Search app are deliberately NOT here; they are in TIER_LATE because
# sideloads and the STT verify come first.
TIER1=(
    "com.android.chrome|Chrome; the appliance browses nothing"
    "com.google.android.gm|Gmail; no account, ever"
    "com.google.android.apps.photos|Photos"
    "com.google.android.youtube|YouTube"
    "com.google.android.apps.youtube.music|YouTube Music"
    "com.google.android.videos|Google TV"
    "com.google.android.apps.maps|Maps"
    "com.google.android.apps.docs|Drive"
    "com.google.android.calendar|Calendar"
    "com.google.android.contacts|Contacts app"
    "com.google.android.deskclock|Clock app; the house keeps the timers"
    "com.google.android.calculator|Calculator"
    "com.google.android.apps.googleassistant|Assistant; Sulivan is the assistant"
    "com.google.android.apps.tachyon|Meet"
    "com.google.android.apps.adm|Find My Device; no account"
    "com.google.android.apps.walletnfcrel|Wallet"
    "com.google.android.projection.gearhead|Android Auto"
    "com.google.android.apps.chromecast.app|Google Home"
    "com.google.android.apps.wellbeing|Digital Wellbeing"
    "com.google.android.apps.safetyhub|Personal Safety"
    "com.google.android.apps.restore|device-to-device restore"
    "com.google.android.apps.nbu.files|Files by Google; documentsui stays"
    "com.google.android.marvin.talkback|TalkBack; restore if accessibility is ever needed"
    "com.google.ar.core|ARCore"
    "com.google.android.apps.wallpaper|wallpaper picker"
)

# Tier 2: Motorola bloat and the carrier's partner preloads.
TIER2=(
    "com.motorola.moto|Moto app suite hub"
    "com.motorola.genie|Moto assistant"
    "com.motorola.help|Moto help"
    "com.motorola.help.extlog|Moto help logging"
    "com.motorola.mototour|device tour"
    "com.motorola.motocare|Moto care"
    "com.motorola.discovery|Moto discovery"
    "com.motorola.spaces|Moto spaces"
    "com.motorola.timeweatherwidget|stock widget; the persona is the clock"
    "com.motorola.appforecast|app suggestions"
    "com.motorola.bug2go|bug reporting"
    "com.motorola.play|Moto play services"
    "com.motorola.partner.music|Spotify stub"
    "com.motorola.cn.calculator|Moto calculator"
    "com.motorola.audiorecorder|Moto recorder"
    "com.motorola.screenshoteditor|screenshot editor"
    "com.motorola.personalize|theming"
    "com.motorola.brapps|Brazil preloads"
    "com.motorola.demo|retail demo"
    "com.motorola.retrorazr|retro razr easter egg"
    "com.motorola.retrogames.astro|retro game"
    "com.motorola.gamemode|game mode"
    "com.motorola.securityhub|Moto security hub"
    "com.motorola.securevault|Moto vault"
    "com.motorola.clockfaces.jetset|cover clock faces"
    "com.motorola.clockface|cover clock faces"
    # Partner preloads, the shovelware the aura installer landed.
    "com.facebook.katana|Facebook preload"
    "com.einnovation.temu|Temu preload"
    "com.king.candycrushsaga|Candy Crush preload"
    "com.tripledot.solitaire|Solitaire preload"
    "com.block.juggle|Block Blast preload"
    "com.vitastudio.mahjong|Mahjong preload"
    "in.playsimple.newwordsearch|Word Search preload"
    "com.particlenews.newsbreak|NewsBreak preload"
    "com.aura.news.discovery.news|aura news preload"
    "com.zhiliaoapp.musically|TikTok preload"
    "com.amazon.mShop.android.shopping|Amazon preload"
    "com.aws.android|WeatherBug preload"
    "com.spotify.music|Spotify; the house plays the music"
)

# Prefix groups swept with pm list at run time; twenty wallpaper prebuilts
# do not need twenty lines.
TIER2_PREFIXES=(
    "com.motorola.livewallpaper3|stock live wallpapers, all prebuilts"
)

# Tier 3: stock surfaces the appliance replaces. ONLY after Hearth is HOME
# on both displays and a power cycle proves it. Each of these can leave the
# device with no launcher if stripped early.
TIER3=(
    "com.motorola.launcher3|stock launcher; only after Hearth holds HOME"
    "com.motorola.launcher.secondarydisplay|cover-screen home seat; only after Hearth holds SECONDARY_HOME"
    "com.motorola.leanbacklauncher|leanback launcher"
    "com.motorola.wallpaper.secondarydisplay|cover wallpaper"
    "com.motorola.motodisplay|peek display; the persona owns the resting screen"
)

# Late strips, by hand, after every sideload is done and STT is verified.
TIER_LATE=(
    "com.android.vending|Play Store; only after all sideloads are done"
    "com.google.android.googlequicksearchbox|Google Search app; strip LAST and verify a voice turn immediately after"
)
