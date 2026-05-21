package com.neko.neko

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.neko.neko/import"
    private var pendingResult: Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "extractZip" -> {
                    val zipPath = call.argument<String>("zipPath") ?: ""
                    val targetPath = call.argument<String>("targetPath") ?: ""
                    try {
                        extractZip(zipPath, targetPath)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("ZIP_ERROR", e.message, null)
                    }
                }
                "pickAndCopyFolder" -> {
                    pendingResult = result
                    val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE)
                    intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                    startActivityForResult(intent, REQUEST_FOLDER_PICK)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != REQUEST_FOLDER_PICK || pendingResult == null) return

        val result = pendingResult!!
        pendingResult = null

        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return
        }

        val treeUri = data!!.data!!
        // Take persistent permission
        contentResolver.takePersistableUriPermission(
            treeUri,
            Intent.FLAG_GRANT_READ_URI_PERMISSION
        )

        try {
            val targetDir = File(cacheDir, "neko_folder_import_${System.currentTimeMillis()}")
            targetDir.mkdirs()
            val docFile = DocumentFile.fromTreeUri(this, treeUri)
            if (docFile != null) {
                copyDocumentTree(docFile, targetDir)
            }
            result.success(targetDir.absolutePath)
        } catch (e: Exception) {
            result.error("COPY_ERROR", e.message, null)
        }
    }

    private fun copyDocumentTree(source: DocumentFile, targetDir: File) {
        val children = source.listFiles()
        for (child in children) {
            if (child.isDirectory) {
                val subDir = File(targetDir, child.name ?: "unknown")
                subDir.mkdirs()
                copyDocumentTree(child, subDir)
            } else if (child.isFile) {
                val targetFile = File(targetDir, child.name ?: "unknown")
                contentResolver.openInputStream(child.uri)?.use { input ->
                    targetFile.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
            }
        }
    }

    private fun extractZip(zipPath: String, targetPath: String) {
        java.util.zip.ZipFile(zipPath).use { zip ->
            val entries = zip.entries()
            while (entries.hasMoreElements()) {
                val entry = entries.nextElement()
                if (!entry.isDirectory) {
                    val targetFile = File(targetPath, entry.name)
                    targetFile.parentFile?.mkdirs()
                    zip.getInputStream(entry).use { input ->
                        targetFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                }
            }
        }
    }

    companion object {
        private const val REQUEST_FOLDER_PICK = 9999
    }
}
