package com.example.transkey_mobile

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast

/**
 * Transparent activity that opens the system's screen-recording consent
 * prompt and hands the resulting projection token off to
 * [ScreenCaptureService] via [ScreenCaptureManager].
 *
 * A Service can't call [Activity.startActivityForResult] / register an
 * `ActivityResult` launcher — so the bubble's "Scan screen" entry routes
 * through here for the consent UI, then immediately closes.
 */
class ScreenCapturePermissionActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val mpm = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        try {
            startActivityForResult(mpm.createScreenCaptureIntent(), REQ_CODE)
        } catch (_: Exception) {
            finish()
        }
    }

    @Deprecated("startActivityForResult is the lowest-friction route here — we don't need a ComponentActivity dep just for one call.")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQ_CODE) {
            finish()
            return
        }
        if (resultCode == RESULT_OK && data != null) {
            ScreenCaptureManager.resultCode = resultCode
            ScreenCaptureManager.resultIntent = data
            val intent = Intent(this, ScreenCaptureService::class.java).apply {
                action = ScreenCaptureService.ACTION_CAPTURE
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(intent)
            } else {
                startService(intent)
            }
        } else {
            Toast.makeText(
                this,
                getString(R.string.bubble_scan_perm_denied),
                Toast.LENGTH_LONG,
            ).show()
        }
        finish()
        overridePendingTransition(0, 0)
    }

    companion object {
        private const val REQ_CODE = 4012
    }
}
