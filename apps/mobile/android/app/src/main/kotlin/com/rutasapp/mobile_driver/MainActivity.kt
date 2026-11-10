package com.rutasapp.mobile_driver

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val CHANNEL = "com.rutasapp.mobile_driver/tracking"
        const val TRACKING_PREFERENCES = "rutas_tracking_recovery"
        const val ACTIVE_KEY = "active"
        const val SERVICE_ID_KEY = "service_id"
        const val NOTIFICATION_PERMISSION_REQUEST = 7101
        const val BACKGROUND_LOCATION_PERMISSION_REQUEST = 7102
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setSessionState" -> {
                        val active = call.argument<Boolean>("active") ?: false
                        val serviceId = call.argument<String>("serviceId")
                        getSharedPreferences(TRACKING_PREFERENCES, MODE_PRIVATE)
                            .edit()
                            .putBoolean(ACTIVE_KEY, active)
                            .apply {
                                if (serviceId == null) remove(SERVICE_ID_KEY)
                                else putString(SERVICE_ID_KEY, serviceId)
                            }
                            .apply()
                        result.success(null)
                    }
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "requestBackgroundLocationPermission" -> requestBackgroundLocationPermission(result)
                    "isIgnoringBatteryOptimizations" -> result.success(isIgnoringBatteryOptimizations())
                    "requestIgnoreBatteryOptimizations" -> requestIgnoreBatteryOptimizations(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 33 ||
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun requestBackgroundLocationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < 29 ||
            checkSelfPermission(Manifest.permission.ACCESS_BACKGROUND_LOCATION) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        pendingPermissionResult = result
        requestPermissions(
            arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
            BACKGROUND_LOCATION_PERMISSION_REQUEST,
        )
    }

    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val power = getSystemService(POWER_SERVICE) as PowerManager
        return power.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * Abre el dialogo del sistema para quedar exenta del ahorro de bateria.
     *
     * Es lo unico que evita que Doze y los administradores agresivos de varias
     * marcas cierren la app mientras rastrea. Responde de inmediato: el sistema
     * no informa el resultado, asi que se vuelve a consultar el estado despues.
     */
    private fun requestIgnoreBatteryOptimizations(result: MethodChannel.Result) {
        if (isIgnoringBatteryOptimizations()) {
            result.success(true)
            return
        }
        try {
            startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName"),
                ),
            )
            result.success(true)
        } catch (error: Exception) {
            // Algunas marcas no exponen esa pantalla: no es motivo para romper
            // el arranque del rastreo, solo se queda sin la exencion.
            result.success(false)
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != NOTIFICATION_PERMISSION_REQUEST &&
            requestCode != BACKGROUND_LOCATION_PERMISSION_REQUEST
        ) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }
}
