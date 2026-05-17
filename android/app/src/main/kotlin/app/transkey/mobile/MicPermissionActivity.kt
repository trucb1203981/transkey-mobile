package app.transkey.mobile

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.widget.Toast

/**
 * Transparent activity that requests the RECORD_AUDIO runtime permission on
 * behalf of [BubbleService] — a Service can't show a permission prompt
 * directly. After the user responds we fire ACTION_START_VOICE back at the
 * bubble service, which opens the voice picker.
 */
class MicPermissionActivity : Activity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (hasMicPermission()) {
            startVoicePicker()
            finish()
            return
        }
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), REQ_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQ_CODE) {
            finish()
            return
        }
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        if (granted) {
            startVoicePicker()
        } else {
            Toast.makeText(
                this,
                getString(R.string.bubble_voice_perm_denied),
                Toast.LENGTH_LONG,
            ).show()
        }
        finish()
    }

    private fun hasMicPermission(): Boolean = checkSelfPermission(
        Manifest.permission.RECORD_AUDIO,
    ) == PackageManager.PERMISSION_GRANTED

    private fun startVoicePicker() {
        val intent = Intent(this, BubbleService::class.java).apply {
            action = BubbleService.ACTION_START_VOICE
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    companion object {
        private const val REQ_CODE = 4011
    }
}
