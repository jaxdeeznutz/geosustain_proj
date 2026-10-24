package com.example.geosustain_clean_arranged

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

class MainActivity : FlutterActivity() {
    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey("geosustain.session.v1", null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").apply {
            init(KeyGenParameterSpec.Builder("geosustain.session.v1",
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
        }.generateKey()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "geosustain/session")
            .setMethodCallHandler { call, result ->
                val prefs = getSharedPreferences("protected_session", MODE_PRIVATE)
                try {
                    if (call.method.startsWith("workspace")) {
                        val args = call.arguments as Map<*, *>
                        val owner = args["owner"] as String
                        require(owner.matches(Regex("[0-9]+")))
                        val workspace = getSharedPreferences("protected_workspace", MODE_PRIVATE)
                        when (call.method) {
                            "workspaceRead" -> {
                                val stored = workspace.getString(owner, null)
                                if (stored == null) result.success(null) else {
                                    val parts = stored.split(":")
                                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                    cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                                    cipher.updateAAD(owner.toByteArray(Charsets.UTF_8))
                                    result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                                }
                            }
                            "workspaceWrite" -> {
                                val value = args["value"] as String
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.ENCRYPT_MODE, key())
                                cipher.updateAAD(owner.toByteArray(Charsets.UTF_8))
                                val stored = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                                    Base64.encodeToString(cipher.doFinal(value.toByteArray(Charsets.UTF_8)), Base64.NO_WRAP)
                                check(workspace.edit().putString(owner, stored).commit())
                                result.success(null)
                            }
                            "workspaceDelete" -> { check(workspace.edit().remove(owner).commit()); result.success(null) }
                            else -> result.notImplemented()
                        }
                        return@setMethodCallHandler
                    }
                    when (call.method) {
                        "read" -> {
                            val stored = prefs.getString("ciphertext", null)
                            if (stored == null) result.success(null) else {
                                val parts = stored.split(":")
                                val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                                cipher.init(Cipher.DECRYPT_MODE, key(),
                                    GCMParameterSpec(128, Base64.decode(parts[0], Base64.NO_WRAP)))
                                result.success(String(cipher.doFinal(Base64.decode(parts[1], Base64.NO_WRAP)), Charsets.UTF_8))
                            }
                        }
                        "write" -> {
                            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                            cipher.init(Cipher.ENCRYPT_MODE, key())
                            val encrypted = cipher.doFinal((call.arguments as String).toByteArray(Charsets.UTF_8))
                            val stored = Base64.encodeToString(cipher.iv, Base64.NO_WRAP) + ":" +
                                Base64.encodeToString(encrypted, Base64.NO_WRAP)
                            check(prefs.edit().putString("ciphertext", stored).commit())
                            result.success(null)
                        }
                        "delete" -> {
                            check(prefs.edit().clear().commit())
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    if (call.method.startsWith("workspace")) {
                        // Keep encrypted pending farms on failures; never erase them.
                        result.error("workspace_storage", "Saved farm storage is unavailable on this device.", null)
                        return@setMethodCallHandler
                    }
                    // Restored backups cannot decrypt using another device's key.
                    prefs.edit().clear().commit()
                    if (call.method == "read") result.success(null)
                    else result.error("session_storage", "Protected session storage is unavailable.", null)
                }
            }
    }
}
