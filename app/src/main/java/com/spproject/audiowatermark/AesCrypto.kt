package com.spproject.audiowatermark

import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.IvParameterSpec
import javax.crypto.spec.SecretKeySpec

/**
 * AES-128 in CTR mode with a fixed IV.
 *
 * CTR mode is chosen deliberately over CBC/PKCS5Padding:
 *  • CTR gives ciphertext length == plaintext length exactly.
 *  • CBC rounds UP to the next 16-byte block boundary — a 1-character message
 *    would take as long to transmit as a 16-character one at 10 bits/sec.
 *
 * KNOWN LIMITATION — fixed IV:
 *  Reusing the same IV with the same key in CTR mode is a cryptographic
 *  weakness (keystream reuse: XOR-ing two ciphertexts cancels the keystream
 *  and reveals plaintext XOR plaintext).  Acceptable for a trusted-device
 *  course project; a production system would prepend a fresh random 16-byte
 *  nonce per message.
 */
object AesCrypto {

    private const val TRANSFORM = "AES/CTR/NoPadding"

    /**
     * Derives a 128-bit AES key from [passphrase] by SHA-256 hashing and
     * taking the first 16 bytes.  Both phones must use the same passphrase
     * so they derive the same key.
     */
    fun deriveKey(passphrase: String = Config.SHARED_PASSPHRASE): SecretKey {
        val digest = MessageDigest.getInstance("SHA-256")
        val hash = digest.digest(passphrase.toByteArray(Charsets.UTF_8))
        return SecretKeySpec(hash.copyOf(16), "AES")   // first 128 bits
    }

    /**
     * Fixed all-zero IV.
     * See KNOWN LIMITATION note in the class-level doc.
     */
    private val FIXED_IV = IvParameterSpec(ByteArray(16) { 0 })

    /**
     * Encrypts [plainText] with the derived key and the fixed IV.
     * Returns raw ciphertext bytes (same length as the UTF-8 encoded input).
     */
    fun encrypt(plainText: String, key: SecretKey = deriveKey()): ByteArray {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.ENCRYPT_MODE, key, FIXED_IV)
        return cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
    }

    /**
     * Decrypts [cipherBytes] with the derived key and the fixed IV.
     * Throws [javax.crypto.BadPaddingException] / [IllegalArgumentException]
     * if the bytes are garbage (wrong key, bit errors); callers should catch.
     */
    fun decrypt(cipherBytes: ByteArray, key: SecretKey = deriveKey()): String {
        val cipher = Cipher.getInstance(TRANSFORM)
        cipher.init(Cipher.DECRYPT_MODE, key, FIXED_IV)
        return String(cipher.doFinal(cipherBytes), Charsets.UTF_8)
    }
}
