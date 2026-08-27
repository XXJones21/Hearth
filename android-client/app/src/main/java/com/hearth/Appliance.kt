package com.hearth

import android.app.Activity
import android.app.ActivityManager
import android.app.admin.DevicePolicyManager
import android.content.ActivityNotFoundException
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.UserManager
import android.provider.Settings
import android.util.Log
import com.hearth.app.MainActivity

/**
 * The appliance side of the client, per wiki/raw/android-appliance-plan.md.
 * Everything in this file is gated on "am I device owner", which is only
 * ever true on a device provisioned with the dpm one-shot. On a normal
 * phone [enterKiosk] returns on its first line and the APK behaves exactly
 * as it did before this file existed.
 */
object Appliance {

    private const val TAG = "HearthAppliance"

    /**
     * What may draw an activity while Hearth is pinned. GMS and the speech
     * app because STT rides them; the live RecognitionService on the Razr
     * is com.google.android.tts (Speech Recognition and Synthesis), read
     * from `settings get secure voice_recognition_service`, NOT the Search
     * app. Tailscale because stripping the VPN's ability to run strands
     * the appliance the moment it leaves the house.
     */
    private val LOCK_TASK_PACKAGES = arrayOf(
        "com.hearth",
        "com.google.android.gms",
        "com.google.android.tts",
        "com.tailscale.ipn",
        // Settings is on the list so [handBack] has somewhere to land even
        // if the unpin has not taken effect yet. It is not reachable from a
        // running kiosk on its own: nothing launches it but the hand-back.
        "com.android.settings",
    )

    /** Ten minutes; the DPC pins the timeout so a settings strip can't shorten it. */
    private const val SCREEN_TIMEOUT_MS = "600000"

    fun isOwner(context: Context): Boolean {
        val dpm = context.getSystemService(DevicePolicyManager::class.java)
        return dpm?.isDeviceOwnerApp(context.packageName) == true
    }

    /**
     * Apply the kiosk policy and pin. Idempotent, called from every
     * onResume rather than once at provisioning: policy survives updates,
     * and a boot or a crash relaunch re-enters Lock Task without ceremony.
     */
    fun enterKiosk(activity: Activity) {
        val dpm = activity.getSystemService(DevicePolicyManager::class.java) ?: return
        if (!dpm.isDeviceOwnerApp(activity.packageName)) return
        val admin = ComponentName(activity, DeviceOwnerReceiver::class.java)

        try {
            // Power-on lands in the persona: Hearth is the persistent HOME.
            val home = IntentFilter(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_HOME)
                addCategory(Intent.CATEGORY_DEFAULT)
            }
            dpm.addPersistentPreferredActivity(
                admin, home, ComponentName(activity, MainActivity::class.java)
            )

            // The cover seat too. Motorola marks its cover launcher
            // non-disable, so the strip cannot remove it; the persistent
            // preference is what actually takes the seat from it.
            val coverHome = IntentFilter(Intent.ACTION_MAIN).apply {
                addCategory("android.intent.category.SECONDARY_HOME")
                addCategory(Intent.CATEGORY_DEFAULT)
            }
            dpm.addPersistentPreferredActivity(
                admin, coverHome, ComponentName(activity, MainActivity::class.java)
            )

            dpm.setLockTaskPackages(admin, LOCK_TASK_PACKAGES)
            // The power menu stays (a held device must be able to shut
            // down); the shade and system info flags stay OFF, so stock
            // notifications never render. Their content routes through the
            // persona's voice instead, when the listener lands.
            dpm.setLockTaskFeatures(
                admin, DevicePolicyManager.LOCK_TASK_FEATURE_GLOBAL_ACTIONS
            )
            dpm.setStatusBarDisabled(admin, true)
            // No lockscreen on a held wifi appliance.
            dpm.setKeyguardDisabled(admin, true)
            // Safe boot is a kiosk escape. DISALLOW_FACTORY_RESET and adb
            // restrictions are deliberately NOT set: reset is the approved
            // recovery and adb is the dev line, and this device cannot be
            // reflashed if we lock ourselves out.
            dpm.addUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)

            dpm.setGlobalSetting(
                admin,
                Settings.Global.STAY_ON_WHILE_PLUGGED_IN,
                (BatteryManager.BATTERY_PLUGGED_AC
                    or BatteryManager.BATTERY_PLUGGED_USB
                    or BatteryManager.BATTERY_PLUGGED_WIRELESS).toString(),
            )
            dpm.setSystemSetting(
                admin, Settings.System.SCREEN_OFF_TIMEOUT, SCREEN_TIMEOUT_MS
            )

            // The VPN must come up on boot without a person: the first tier 1
            // reboot proved it, landing in a persona that could not reach the
            // house because Tailscale sat waiting to be opened. Lockdown stays
            // false so a broken VPN degrades to LAN rather than to nothing.
            try {
                dpm.setAlwaysOnVpnPackage(admin, "com.tailscale.ipn", false)
            } catch (e: Exception) {
                // Tailscale not installed yet; the runbook installs it and the
                // next resume picks it up.
                Log.w(TAG, "always-on VPN not set", e)
            }
        } catch (e: SecurityException) {
            // A policy refused mid-flight (an OEM quirk, a stale admin) must
            // not take the client down with it; the persona still renders.
            Log.w(TAG, "kiosk policy refused", e)
        }

        // THE DEV LINE STAYS OPEN ACROSS REBOOTS. On 2026-08-26 the appliance
        // came up from a power cycle with adb_enabled back at 0, and every
        // rung of the runbook's recovery ladder below the factory reset needs
        // adb, so the phone was unreachable. ADB_ENABLED is one of the few
        // globals a device owner may write; DEVELOPMENT_SETTINGS_ENABLED is
        // NOT on that allowlist, which is why the hand-back below exists to
        // open the Developer options screen by intent instead.
        //
        // Its own try: this throws on a build that narrows the allowlist, and
        // inside the block above that would have skipped every policy after
        // it. Appliance-only either way, since the whole function returns
        // early when Hearth is not device owner.
        try {
            dpm.setGlobalSetting(admin, Settings.Global.ADB_ENABLED, "1")
        } catch (e: Exception) {
            Log.w(TAG, "could not pin adb_enabled", e)
        }

        val am = activity.getSystemService(ActivityManager::class.java)
        if (am?.lockTaskModeState == ActivityManager.LOCK_TASK_MODE_NONE) {
            activity.startLockTask()
        }
    }

    /**
     * The debug exit. Clearing the lock task allowlist is what actually
     * unpins (the platform kicks any task whose package leaves the list);
     * the rest hands the phone back: shade, keyguard, HOME.
     */
    fun exitKiosk(context: Context) {
        val dpm = context.getSystemService(DevicePolicyManager::class.java) ?: return
        if (!dpm.isDeviceOwnerApp(context.packageName)) return
        val admin = ComponentName(context, DeviceOwnerReceiver::class.java)

        dpm.setLockTaskPackages(admin, emptyArray())
        dpm.setStatusBarDisabled(admin, false)
        dpm.setKeyguardDisabled(admin, false)
        dpm.clearUserRestriction(admin, UserManager.DISALLOW_SAFE_BOOT)
        dpm.clearPackagePersistentPreferredActivities(admin, context.packageName)
        Log.w(TAG, "kiosk exited by debug broadcast")
    }

    /**
     * THE RUNG THAT NEEDS NO ADB. Hand the phone to the person holding it:
     * unpin, give the shade and the keyguard back, and open Developer
     * options so USB debugging can be turned on FROM the device.
     *
     * This exists because the runbook's recovery ladder opened rung 2 with
     * "adb stays alive" and on 2026-08-26 that was false: a reboot left the
     * appliance with adb off, the client launches nothing but itself, and
     * every other way out had been stripped or disabled. The only remaining
     * option was a factory reset.
     *
     * Deliberately NOT sticky. The next [enterKiosk] -- Hearth's own onResume
     * -- pins the appliance again, so backing out of Settings returns the
     * house to itself rather than leaving a kiosk that quietly stopped being
     * one. The window is long enough to flip a toggle, which is the whole
     * job.
     */
    fun handBack(activity: Activity) {
        if (!isOwner(activity)) return
        exitKiosk(activity)
        // Clearing the allowlist unpins on the platform's next check;
        // stopLockTask returns the nav bar NOW, which is what a person with
        // the phone in their hand is waiting for.
        try {
            activity.stopLockTask()
        } catch (e: IllegalStateException) {
            // Not in Lock Task. Nothing to stop, and nothing to report.
        }
        Log.w(TAG, "kiosk handed back from the device")

        // Straight to the toggle. Falling back to the Settings root rather
        // than to nothing: Developer options is hidden until the build number
        // ceremony, and this activity does not exist until then.
        val screens = listOf(
            Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS,
            Settings.ACTION_SETTINGS,
        )
        for (action in screens) {
            try {
                activity.startActivity(
                    Intent(action).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                return
            } catch (e: ActivityNotFoundException) {
                Log.w(TAG, "no activity for $action", e)
            }
        }
    }
}

/**
 * Relaunch after a power cycle. Belt and braces beside the persistent
 * preferred HOME: HOME covers the normal boot, this covers the odd path
 * where the launcher intent is consumed elsewhere. Device owners are
 * exempt from background-activity-start restrictions, so the launch is
 * allowed here. Off the appliance the owner check makes this a no-op.
 */
class ApplianceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        if (!Appliance.isOwner(context)) return
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        )
    }
}

/**
 * The dev escape hatch, from the plan's recovery ladder:
 *
 *     adb shell am broadcast -a com.hearth.appliance.EXIT --es confirm hearth
 *
 * The extra is a speed bump, not a lock: a co-installed app that knows it
 * could unpin the kiosk. On the appliance almost nothing else is installed,
 * and the worst case is an unpinned screen, so the simple guard is the
 * right size. The owner check inside exitKiosk keeps this inert everywhere
 * else.
 */
class ApplianceExitReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.getStringExtra("confirm") != "hearth") return
        Appliance.exitKiosk(context)
    }
}
