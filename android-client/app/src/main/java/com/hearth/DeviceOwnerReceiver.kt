package com.hearth

import android.app.admin.DeviceAdminReceiver

/**
 * The DPC. Deliberately empty: policy is applied by [Appliance.enterKiosk]
 * on every resume rather than once in onEnabled, so a policy added in an
 * update reaches a device that was provisioned before the update existed.
 *
 * The class lives in package `com.hearth`, not `com.hearth.app`, so the
 * provisioning one-shot resolves exactly as the plan documents it:
 *
 *     adb shell dpm set-device-owner com.hearth/.DeviceOwnerReceiver
 *
 * Off the appliance this receiver is never enabled and nothing here runs.
 */
class DeviceOwnerReceiver : DeviceAdminReceiver()
