package app.transkey.mobile

import android.text.InputType

/** Whether Vietnamese spelling suggestions and autocorrection are safe here. */
internal fun allowsVietCorrection(inputType: Int): Boolean {
    if ((inputType and InputType.TYPE_MASK_CLASS) != InputType.TYPE_CLASS_TEXT) return false
    if ((inputType and InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS) != 0) return false
    return when (inputType and InputType.TYPE_MASK_VARIATION) {
        InputType.TYPE_TEXT_VARIATION_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD,
        InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_WEB_EMAIL_ADDRESS,
        InputType.TYPE_TEXT_VARIATION_URI,
        InputType.TYPE_TEXT_VARIATION_PERSON_NAME -> false
        else -> true
    }
}
