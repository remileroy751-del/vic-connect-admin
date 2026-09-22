package com.vicintelligentsia.vicconnect

import android.Manifest
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.setContent
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import org.json.JSONArray
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

private val DarkGreen = Color(0xFF0E4B3A)
private val YellowGreen = Color(0xFFC9D84A)
private val SoftGreen = Color(0xFFEAF2D1)
private val Orange = Color(0xFFE78A21)
private val Red = Color(0xFFD63C3C)

private data class Child(val id: String, val name: String, val className: String)
private data class Teacher(val id: String, val name: String, val subject: String, val homeroom: Boolean)
private data class NoteRow(
    val subject: String,
    val homework: List<Pair<String, Double>>,
    val classAverage: Double?,
    val composition: Double?,
    val subjectAverage: Double?
)
private data class Announcement(
    val id: String, val title: String, val body: String,
    val importance: String, val createdAt: String, val acknowledged: Boolean
)
private data class ChatMessage(val id: String, val senderRole: String, val body: String, val createdAt: String)
private data class TeacherClass(
    val classId: String, val className: String, val subjectId: String,
    val subjectName: String, val assignmentId: String, val homeroom: Boolean
)
private data class Student(val id: String, val name: String, val className: String)
private data class ClassStat(val classId: String, val className: String, val effectif: Int)
private data class StudentRanking(val id: String, val name: String, val generalAverage: Double?)
private data class TeacherConversation(val parentId: String, val parentName: String, val studentId: String, val studentName: String, val className: String, val lastMessage: String, val lastSenderRole: String, val lastMessageAt: String)
private data class MobileNotification(val id: String, val title: String, val body: String, val createdAt: String)

class VicApi {
    private val base = BuildConfig.SUPABASE_URL.trimEnd('/')
    private val key = BuildConfig.SUPABASE_ANON_KEY

    private fun post(function: String, body: JSONObject): String {
        val conn = (URL("$base/rest/v1/rpc/$function").openConnection() as HttpURLConnection)
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = 20000
            conn.readTimeout = 30000
            conn.setRequestProperty("apikey", key)
            conn.setRequestProperty("Authorization", "Bearer $key")
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "application/json")
            conn.doOutput = true
            conn.outputStream.use { it.write(body.toString().toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val stream = if (code in 200..299) conn.inputStream else conn.errorStream
            val text = stream?.bufferedReader()?.use { it.readText() } ?: ""
            if (code !in 200..299) error(text.ifBlank { "Erreur HTTP $code" })
            return text
        } finally { conn.disconnect() }
    }

    private fun arr(text: String) = JSONArray(text)
    private fun dateLabel(raw: String): String = runCatching {
        val input = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US)
        val output = SimpleDateFormat("dd/MM/yyyy HH:mm", Locale.FRANCE)
        output.format(input.parse(raw.take(19)) ?: Date())
    }.getOrDefault(raw.take(16).replace('T', ' '))

    fun login(code: String): JSONObject = post("login_with_access_code", JSONObject().put("p_code", code.trim().uppercase()))
        .let { if (it.trimStart().startsWith("[") && JSONArray(it).length() > 0) JSONArray(it).getJSONObject(0) else JSONObject(it) }

    fun parentChildren(code: String): List<Child> = arr(post("parent_children", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { o -> a.getJSONObject(o).let { Child(it.getString("student_id"), it.getString("student_name"), it.getString("class_name")) } }
    }

    fun teachersForChild(code: String, childId: String): List<Teacher> = arr(post("parent_child_teachers", JSONObject().put("p_code", code).put("p_student_id", childId))).let { a ->
        (0 until a.length()).map { o -> a.getJSONObject(o).let { Teacher(it.getString("teacher_id"), it.getString("teacher_name"), it.getString("subject_name"), it.optBoolean("is_homeroom")) } }
    }

    fun notes(code: String, childId: String, term: String): List<NoteRow> = arr(post("student_notes", JSONObject().put("p_code", code).put("p_student_id", childId).put("p_term", term))).let { a ->
        (0 until a.length()).map { i ->
            val o = a.getJSONObject(i)
            val hw = mutableListOf<Pair<String, Double>>()
            val ja = o.optJSONArray("devoirs") ?: JSONArray()
            for (j in 0 until ja.length()) {
                val h = ja.getJSONObject(j)
                hw += (h.optString("title").ifBlank { "Devoir" }) to h.optDouble("value", 0.0)
            }
            NoteRow(o.optString("subject_name"), hw, o.takeDouble("moyenne_classe"), o.takeDouble("composition"), o.takeDouble("moyenne_matiere"))
        }
    }

    fun announcements(code: String, childId: String): List<Announcement> = arr(post("student_announcements", JSONObject().put("p_code", code).put("p_student_id", childId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { Announcement(it.getString("announcement_id"), it.optString("title"), it.optString("body"), it.optString("importance"), dateLabel(it.optString("created_at")), it.optBoolean("acknowledged")) } }
    }

    fun teacherAnnouncements(code: String): List<Announcement> = arr(post("teacher_announcements", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { Announcement(it.getString("announcement_id"), it.optString("title"), it.optString("body"), it.optString("importance"), dateLabel(it.optString("created_at")), false) } }
    }

    fun acknowledge(code: String, id: String, childId: String) {
        post("acknowledge_announcement", JSONObject().put("p_code", code).put("p_announcement_id", id).put("p_student_id", childId))
    }

    fun messages(code: String, childId: String, teacherId: String): List<ChatMessage> = arr(post("conversation_messages", JSONObject().put("p_code", code).put("p_student_id", childId).put("p_teacher_id", teacherId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { ChatMessage(it.getString("message_id"), it.optString("sender_role"), it.optString("body"), dateLabel(it.optString("created_at"))) } }
    }

    fun sendParentMessage(code: String, childId: String, teacherId: String, body: String) {
        post("send_parent_message", JSONObject().put("p_code", code).put("p_student_id", childId).put("p_teacher_id", teacherId).put("p_body", body))
    }

    fun teacherConversations(code: String): List<TeacherConversation> = arr(post("teacher_conversations", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let {
            TeacherConversation(
                it.getString("parent_id"), it.getString("parent_name"), it.getString("student_id"),
                it.getString("student_name"), it.getString("class_name"), it.optString("last_message"),
                it.optString("last_sender_role"), dateLabel(it.optString("last_message_at"))
            )
        } }
    }

    fun teacherMessages(code: String, studentId: String, parentId: String): List<ChatMessage> = arr(post("teacher_conversation_messages", JSONObject().put("p_code", code).put("p_student_id", studentId).put("p_parent_id", parentId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { ChatMessage(it.getString("message_id"), it.optString("sender_role"), it.optString("body"), dateLabel(it.optString("created_at"))) } }
    }

    fun sendTeacherMessage(code: String, studentId: String, parentId: String, body: String) {
        post("teacher_send_parent_message", JSONObject().put("p_code", code).put("p_student_id", studentId).put("p_parent_id", parentId).put("p_body", body))
    }

    fun teacherClassStats(code: String, term: String): List<ClassStat> = arr(post("teacher_class_statistics", JSONObject().put("p_code", code).put("p_term", term))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { ClassStat(it.getString("class_id"), it.getString("class_name"), it.optInt("effectif")) } }
    }

    fun teacherRankings(code: String, classId: String, term: String): List<StudentRanking> = arr(post("teacher_student_rankings", JSONObject().put("p_code", code).put("p_class_id", classId).put("p_term", term))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { StudentRanking(it.getString("student_id"), it.getString("student_name"), it.takeDouble("moyenne_generale")) } }
    }

    fun teacherClasses(code: String): List<TeacherClass> = arr(post("teacher_classes", JSONObject().put("p_code", code))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { TeacherClass(it.getString("class_id"), it.getString("class_name"), it.getString("subject_id"), it.getString("subject_name"), it.getString("assignment_id"), it.optBoolean("is_homeroom")) } }
    }

    fun mobileNotifications(code: String, role: String, since: String): List<MobileNotification> = arr(post("mobile_notifications", JSONObject().put("p_code", code).put("p_role", role).put("p_since", since))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { MobileNotification(it.getString("notification_id"), it.optString("title"), it.optString("body"), it.getString("created_at")) } }
    }

    fun teacherStudents(code: String, classId: String): List<Student> = arr(post("teacher_students", JSONObject().put("p_code", code).put("p_class_id", classId))).let { a ->
        (0 until a.length()).map { i -> a.getJSONObject(i).let { Student(it.getString("student_id"), it.getString("student_name"), it.getString("class_name")) } }
            .sortedBy { it.name.lowercase(Locale.FRANCE) }
    }

    fun saveNote(code: String, studentId: String, assignmentId: String, term: String, noteType: String, value: Double, title: String?) {
        post("teacher_save_note", JSONObject().put("p_code", code).put("p_student_id", studentId).put("p_assignment_id", assignmentId).put("p_term", term).put("p_note_type", noteType).put("p_value", value).put("p_title", title ?: JSONObject.NULL))
    }
}

private fun JSONObject.takeDouble(key: String): Double? = if (!has(key) || isNull(key)) null else optDouble(key).takeIf { !it.isNaN() }

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val prefs = getSharedPreferences("vic_connect_local", Context.MODE_PRIVATE)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 7001)
        }
        setContent { VicConnectApp(prefs, this) }
    }
}

@Composable
private fun VicConnectApp(prefs: android.content.SharedPreferences, activity: MainActivity) {
    MaterialTheme(colorScheme = lightColorScheme(primary = DarkGreen, secondary = YellowGreen, background = Color.White, surface = Color.White, onPrimary = Color.White, onSecondary = Color.Black)) {
        Surface(Modifier.fillMaxSize(), color = Color.White) {
            var code by remember { mutableStateOf(prefs.getString("last_access_code", "") ?: "") }
            var role by remember { mutableStateOf<String?>(prefs.getString("last_role", null)) }
            var profileName by remember { mutableStateOf(prefs.getString("last_profile_name", "") ?: "") }
            var error by remember { mutableStateOf("") }
            var loading by remember { mutableStateOf(false) }
            val api = remember { VicApi() }
            val scope = rememberCoroutineScope()

            LaunchedEffect(Unit) {
                val savedCode = prefs.getString("last_access_code", "") ?: ""
                if (savedCode.isNotBlank() && (role == null || profileName.isBlank())) {
                    loading = true
                    runCatching {
                        withContext(Dispatchers.IO) { api.login(savedCode) }
                    }.onSuccess { r ->
                        if (r.optBoolean("success", false)) {
                            role = r.optString("role")
                            profileName = r.optString("full_name")
                            prefs.edit().putString("last_role", role).putString("last_profile_name", profileName).apply()
                            startVicNotificationService(activity)
                        } else {
                            prefs.edit().clear().apply()
                            code = ""; role = null; profileName = ""
                        }
                    }.onFailure {
                        // En cas de réseau indisponible, on garde la session locale et réessaiera au prochain lancement.
                    }
                    loading = false
                } else if (role != null && code.isNotBlank()) {
                    startVicNotificationService(activity)
                }
            }

            if (role == null) {
                LoginScreen(code, { code = it }, error, loading) {
                    loading = true; error = ""
                    scope.launch {
                        try {
                            val r = withContext(Dispatchers.IO) { api.login(code) }
                            if (!r.optBoolean("success", false)) {
                                error = r.optString("message", "Code incorrect.")
                            } else {
                                val normalized = code.trim().uppercase()
                                code = normalized
                                role = r.optString("role")
                                profileName = r.optString("full_name")
                                prefs.edit()
                                    .putString("last_access_code", normalized)
                                    .putString("last_role", role)
                                    .putString("last_profile_name", profileName)
                                    .putString("notification_cursor", java.time.Instant.now().toString())
                                    .apply()
                                startVicNotificationService(activity)
                            }
                        } catch (e: Exception) {
                            error = "Connexion impossible : ${e.message?.take(140) ?: "erreur réseau ou serveur"}"
                        } finally { loading = false }
                    }
                }
            } else if (role == "parent") {
                ParentHome(api, code, profileName) {
                    stopVicNotificationService(activity)
                    prefs.edit().clear().apply()
                    code = ""; role = null; profileName = ""
                }
            } else {
                TeacherHome(api, code, profileName) {
                    stopVicNotificationService(activity)
                    prefs.edit().clear().apply()
                    code = ""; role = null; profileName = ""
                }
            }
        }
    }
}

@Composable
private fun LoginScreen(code: String, onCode: (String) -> Unit, error: String, loading: Boolean, onLogin: () -> Unit) {
    Column(
        Modifier.fillMaxSize().padding(horizontal = 28.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center
    ) {
        Image(
            painterResource(R.drawable.vic_logo),
            contentDescription = "VIC-INTELLIGENTSIA",
            modifier = Modifier.size(150.dp),
            contentScale = ContentScale.Fit
        )
        Spacer(Modifier.height(8.dp))
        Text("Lycée Technique & Moderne", color = Color.Gray, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Text("VIC-INTELLIGENTSIA", color = DarkGreen, fontSize = 19.sp, fontWeight = FontWeight.Black)
        Text("VIC-CONNECT", color = DarkGreen, fontSize = 29.sp, fontWeight = FontWeight.Black)
        Text("Lomé-Avépozo", color = Color.Gray, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Text("Tél: +228 90 02 80 15 & 22 71 06 02", color = Color.Gray, fontSize = 12.sp)
        Spacer(Modifier.height(24.dp))
        OutlinedTextField(
            value = code,
            onValueChange = { onCode(it.filter(Char::isLetterOrDigit).take(5).uppercase()) },
            label = { Text("Code d'accès") },
            placeholder = { Text("4 caractères parent / 5 enseignant") },
            singleLine = true,
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(16.dp)
        )
        Spacer(Modifier.height(14.dp))
        Button(
            onClick = onLogin,
            enabled = code.length in 4..5 && !loading,
            modifier = Modifier.fillMaxWidth().height(54.dp),
            shape = RoundedCornerShape(16.dp)
        ) {
            Text(if (loading) "Connexion..." else "ACCÉDER À MON ESPACE", fontWeight = FontWeight.Bold)
        }
        if (error.isNotBlank()) {
            Spacer(Modifier.height(12.dp))
            Text(error, color = Red, fontSize = 13.sp)
        }
        Spacer(Modifier.height(22.dp))
        Text(
            "Contact permanent entre Parents - Enseignants et la Direction.",
            color = DarkGreen,
            fontSize = 12.sp,
            fontWeight = FontWeight.SemiBold
        )
        Spacer(Modifier.height(8.dp))
        Text("Devise: Travail - Discipline - Réussite", color = Color.Gray, fontSize = 11.sp, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun Header(title: String, subtitle: String, logout: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(bottom = 18.dp), verticalAlignment = Alignment.CenterVertically) {
        Image(painterResource(R.drawable.vic_logo), contentDescription = "VIC-INTELLIGENTSIA", modifier = Modifier.size(54.dp), contentScale = ContentScale.Fit)
        Spacer(Modifier.width(10.dp))
        Column(Modifier.weight(1f)) {
            Text(title, color = DarkGreen, fontWeight = FontWeight.Black, fontSize = 20.sp)
            if (subtitle.isNotBlank()) Text(subtitle, color = Color.Gray, fontSize = 12.sp)
        }
        IconButton(onClick = logout) { Icon(Icons.Default.Logout, "Déconnexion") }
    }
}

@Composable
private fun ParentHome(api: VicApi, code: String, parentName: String, logout: () -> Unit) {
    var children by remember { mutableStateOf<List<Child>>(emptyList()) }
    var selected by remember { mutableStateOf<Child?>(null) }
    var error by remember { mutableStateOf("") }
    BackHandler(enabled = selected != null) { selected = null }
    LaunchedEffect(Unit) { try { children = withContext(Dispatchers.IO) { api.parentChildren(code) } } catch (_: Exception) { error = "Impossible de charger les enfants." } }
    if (selected == null) {
        Column(Modifier.fillMaxSize().padding(20.dp)) {
            Header("VIC-CONNECT", "", logout)
            Text("Bienvenu(e) Mr/Mme $parentName", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
            Spacer(Modifier.height(8.dp))
            Text("Mes enfants", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
            Spacer(Modifier.height(12.dp))
            if (error.isNotBlank()) Text(error, color = Red)
            if (children.isEmpty() && error.isBlank()) Text("Aucun enfant lié à ce compte.", color = Color.Gray)
            LazyColumn(verticalArrangement = Arrangement.spacedBy(12.dp)) { items(children) { child ->
                Card(Modifier.fillMaxWidth().clickable { selected = child }, shape = RoundedCornerShape(20.dp)) {
                    Row(Modifier.padding(18.dp), verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.size(52.dp).background(SoftGreen, RoundedCornerShape(16.dp)), Alignment.Center) { Text(child.name.take(1).uppercase(), color = DarkGreen, fontSize = 22.sp, fontWeight = FontWeight.Bold) }
                        Spacer(Modifier.width(14.dp)); Column { Text(child.name, fontSize = 18.sp, fontWeight = FontWeight.Bold); Text(child.className, color = Color.Gray) }; Spacer(Modifier.weight(1f)); Icon(Icons.Default.ChevronRight, null)
                    }
                }
            } }
        }
    } else ParentChildScreen(api, code, selected!!, { selected = null })
}

@Composable
private fun ParentChildScreen(api: VicApi, code: String, child: Child, back: () -> Unit) {
    var page by remember { mutableStateOf("menu") }
    BackHandler { if (page == "menu") back() else page = "menu" }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) { IconButton(onClick = { if (page == "menu") back() else page = "menu" }) { Icon(Icons.Default.ArrowBack, "Retour") }; Column { Text(child.name, fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen); Text(child.className, color = Color.Gray) } }
        Spacer(Modifier.height(20.dp))
        when (page) {
            "menu" -> { ParentAction("Voir les notes", Icons.Default.School) { page = "notes" }; ParentAction("Voir les communiqués", Icons.Default.Notifications) { page = "news" }; ParentAction("Voir les enseignants de mon enfant", Icons.Default.Groups) { page = "chat" } }
            "notes" -> NotesScreen(api, code, child) { page = "menu" }
            "news" -> NewsScreen(api, code, child) { page = "menu" }
            "chat" -> ChatScreen(api, code, child) { page = "menu" }
        }
    }
}

@Composable
private fun ParentAction(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(vertical = 7.dp).clickable(onClick = onClick), shape = RoundedCornerShape(18.dp)) { Row(Modifier.padding(20.dp), verticalAlignment = Alignment.CenterVertically) { Icon(icon, null, tint = DarkGreen, modifier = Modifier.size(30.dp)); Spacer(Modifier.width(18.dp)); Text(label, fontSize = 17.sp, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); Icon(Icons.Default.ChevronRight, null) } }
}

@Composable
private fun TermTabs(selected: String, set: (String) -> Unit) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) { listOf("1er trimestre", "2e trimestre", "3e trimestre").forEach { FilterChip(selected = selected == it, onClick = { set(it) }, label = { Text(it, fontSize = 11.sp) }) } }
}

@Composable
private fun NotesScreen(api: VicApi, code: String, child: Child, back: () -> Unit) {
    var term by remember { mutableStateOf("1er trimestre") }
    var rows by remember { mutableStateOf<List<NoteRow>>(emptyList()) }
    var loading by remember { mutableStateOf(false) }
    BackHandler { back() }
    LaunchedEffect(term) { loading = true; runCatching { rows = withContext(Dispatchers.IO) { api.notes(code, child.id, term) } }; loading = false }
    val averages = rows.mapNotNull { it.subjectAverage }
    val general = averages.takeIf { it.isNotEmpty() }?.average()
    Column(Modifier.fillMaxSize()) {
        Text("Notes & moyennes", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        Spacer(Modifier.height(10.dp)); TermTabs(term) { term = it }; Spacer(Modifier.height(14.dp))
        Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(22.dp)) { Column(Modifier.padding(20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
            Text("GRANDE MOYENNE GÉNÉRALE", color = Color.Gray, fontSize = 13.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.height(5.dp)); Text(general?.let { String.format(Locale.FRANCE, "%.2f / 20", it) } ?: "En attente des notes", fontSize = 38.sp, fontWeight = FontWeight.Black, color = DarkGreen)
            Text("Moyenne de toutes les moyennes de matières", color = Color.Gray, fontSize = 11.sp)
        } }
        Spacer(Modifier.height(12.dp)); if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) { items(rows) { n -> Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) { Column(Modifier.padding(15.dp)) { Row(verticalAlignment = Alignment.CenterVertically) { Text(n.subject, fontWeight = FontWeight.Bold, fontSize = 16.sp, modifier = Modifier.weight(1f)); Text(n.subjectAverage?.let { String.format(Locale.FRANCE, "%.2f", it) } ?: "—", fontSize = 25.sp, fontWeight = FontWeight.Bold, color = DarkGreen) }; Spacer(Modifier.height(7.dp)); Text("Moyenne de classe : ${n.classAverage?.let { String.format(Locale.FRANCE, "%.2f", it) } ?: "—"}", fontSize = 14.sp, color = Color.Gray); Text("Composition : ${n.composition?.let { String.format(Locale.FRANCE, "%.2f", it) } ?: "—"}", fontSize = 14.sp, color = Color.Gray); n.homework.forEach { Text("${it.first} : ${String.format(Locale.FRANCE, "%.2f", it.second)}", fontSize = 14.sp) } } } } }
    }
}

@Composable
private fun NewsScreen(api: VicApi, code: String, child: Child, back: () -> Unit) {
    var items by remember { mutableStateOf<List<Announcement>>(emptyList()) }; val scope = rememberCoroutineScope(); BackHandler { back() }
    fun refresh() { scope.launch { runCatching { items = withContext(Dispatchers.IO) { api.announcements(code, child.id) } } } }
    LaunchedEffect(Unit) { refresh() }
    Column(Modifier.fillMaxSize()) { Text("Communiqués", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen); Spacer(Modifier.height(12.dp)); LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) { items(items) { n -> val c = when (n.importance) { "rouge" -> Red; "orange" -> Orange; else -> YellowGreen }; Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) { Column(Modifier.padding(16.dp)) { Text(n.title, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp); Text(n.createdAt, color = Color.Gray, fontSize = 11.sp); Spacer(Modifier.height(6.dp)); Text(n.body); Spacer(Modifier.height(10.dp)); Button(onClick = { if (!n.acknowledged) scope.launch { withContext(Dispatchers.IO) { api.acknowledge(code, n.id, child.id) }; refresh() } }, enabled = !n.acknowledged, colors = ButtonDefaults.buttonColors(containerColor = c)) { Text(if (n.acknowledged) "Bien reçu ✓" else "Bien reçu", color = if (n.importance == "vert") Color.Black else Color.White) } } } } } }
}

@Composable
private fun ChatScreen(api: VicApi, code: String, child: Child, back: () -> Unit) {
    var teachers by remember { mutableStateOf<List<Teacher>>(emptyList()) }; var teacher by remember { mutableStateOf<Teacher?>(null) }
    BackHandler { if (teacher == null) back() else teacher = null }
    LaunchedEffect(Unit) { runCatching { teachers = withContext(Dispatchers.IO) { api.teachersForChild(code, child.id) } } }
    if (teacher == null) { Column(Modifier.fillMaxSize()) { Text("Enseignants de mon enfant", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen); Spacer(Modifier.height(6.dp)); Text("Cliquez sur le nom d'un enseignant pour lui envoyer un message", color = Color.Gray, fontSize = 12.sp); Spacer(Modifier.height(10.dp)); teachers.forEach { t -> ParentAction("${t.name} • ${t.subject}${if (t.homeroom) " • Titulaire" else ""}", Icons.Default.Person) { teacher = t } } } }
    else Conversation(api, code, child, teacher!!, { teacher = null })
}

@Composable
private fun Conversation(api: VicApi, code: String, child: Child, teacher: Teacher, back: () -> Unit) {
    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() { scope.launch { runCatching { messages = withContext(Dispatchers.IO) { api.messages(code, child.id, teacher.id) } }.onFailure { error = it.message ?: "Erreur" } } }
    LaunchedEffect(Unit) { refresh() }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.Default.ArrowBack, "Retour") }
            Column { Text(teacher.name, fontWeight = FontWeight.Bold); Text(teacher.subject, fontSize = 11.sp, color = Color.Gray) }
        }
        Text("5 messages maximum par jour et par compte. Réinitialisation à 00h GMT.", fontSize = 11.sp, color = Color.Gray)
        if (error.isNotBlank()) Text(error, color = Red, fontSize = 12.sp)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(messages) { m -> Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.senderRole == "parent") Arrangement.End else Arrangement.Start) { Card(shape = RoundedCornerShape(16.dp)) { Column(Modifier.padding(12.dp)) { Text(m.body); Text(m.createdAt, fontSize = 9.sp, color = Color.Gray) } } } }
        }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(text, { text = it }, Modifier.weight(1f), placeholder = { Text("Votre message...") }, maxLines = 4)
            IconButton(onClick = {
                if (text.isNotBlank()) {
                    val sent = text.trim(); text = ""; error = ""
                    scope.launch { runCatching { withContext(Dispatchers.IO) { api.sendParentMessage(code, child.id, teacher.id, sent) }; refresh() }.onFailure { error = it.message ?: "Envoi impossible." } }
                }
            }) { Icon(Icons.Default.Send, "Envoyer", tint = DarkGreen) }
        }
    }
}

@Composable
private fun TeacherDirectionMessagesScreen(api: VicApi, code: String, back: () -> Unit) {
    var items by remember { mutableStateOf<List<Announcement>>(emptyList()) }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() { scope.launch { runCatching { items = withContext(Dispatchers.IO) { api.teacherAnnouncements(code) } } } }
    LaunchedEffect(Unit) { refresh() }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.Default.ArrowBack, "Retour") }
            Text("Messages de la Direction", fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
        }
        Spacer(Modifier.height(8.dp))
        Text("Messages envoyés par la Direction à tous les enseignants.", color = Color.Gray, fontSize = 12.sp)
        Spacer(Modifier.height(12.dp))
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            items(items) { n ->
                val c = when (n.importance) { "rouge" -> Red; "orange" -> Orange; else -> YellowGreen }
                Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(16.dp)) {
                    Column(Modifier.padding(16.dp)) {
                        Text(n.title, fontWeight = FontWeight.ExtraBold, fontSize = 17.sp)
                        Text(n.createdAt, color = Color.Gray, fontSize = 11.sp)
                        Spacer(Modifier.height(6.dp))
                        Text(n.body)
                        Spacer(Modifier.height(8.dp))
                        Box(Modifier.fillMaxWidth().height(4.dp).background(c, RoundedCornerShape(4.dp)))
                    }
                }
            }
        }
        if (items.isEmpty()) Text("Aucun message de la Direction.", color = Color.Gray)
    }
}

@Composable
private fun TeacherHome(api: VicApi, code: String, teacherName: String, logout: () -> Unit) {
    var assignments by remember { mutableStateOf<List<TeacherClass>>(emptyList()) }
    var selectedAssignment by remember { mutableStateOf<TeacherClass?>(null) }
    var term by remember { mutableStateOf("1er trimestre") }
    var students by remember { mutableStateOf<List<Student>>(emptyList()) }
    var selectedStudent by remember { mutableStateOf<Student?>(null) }
    var noteType by remember { mutableStateOf("") }
    var noteTitle by remember { mutableStateOf("") }
    var noteValue by remember { mutableStateOf("") }
    var search by remember { mutableStateOf("") }
    var message by remember { mutableStateOf("") }
    var step by remember { mutableStateOf("home") }
    var classStats by remember { mutableStateOf<List<ClassStat>>(emptyList()) }
    var rankings by remember { mutableStateOf<List<StudentRanking>>(emptyList()) }
    var selectedStatClass by remember { mutableStateOf<ClassStat?>(null) }
    var conversations by remember { mutableStateOf<List<TeacherConversation>>(emptyList()) }
    var selectedConversation by remember { mutableStateOf<TeacherConversation?>(null) }
    val scope = rememberCoroutineScope()

    BackHandler(enabled = true) {
        when (step) {
            "home" -> logout()
            "assignments" -> step = "home"
            "noteTypes" -> { selectedAssignment = null; step = "assignments" }
            "students" -> { selectedStudent = null; step = "noteTypes" }
            "entry" -> { selectedStudent = null; step = "students" }
            "statistics" -> { selectedStatClass = null; rankings = emptyList(); step = "home" }
            "ranking" -> { selectedStatClass = null; rankings = emptyList(); step = "statistics" }
            "messages" -> { selectedConversation = null; step = "home" }
            "conversation" -> { selectedConversation = null; step = "messages" }
        }
    }

    LaunchedEffect(Unit) { runCatching { assignments = withContext(Dispatchers.IO) { api.teacherClasses(code) } } }
    val visibleStudents = students.filter { it.name.contains(search.trim(), ignoreCase = true) }

    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Header("ESPACE ENSEIGNANT", "", logout)
        when (step) {
            "home" -> {
                Text("Bienvenu Mr $teacherName", fontSize = 26.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(18.dp))
                ParentAction("Mes classes et matières", Icons.Default.Class) { step = "assignments" }
                ParentAction("Statistique", Icons.Default.BarChart) {
                    step = "statistics"
                    scope.launch { classStats = withContext(Dispatchers.IO) { api.teacherClassStats(code, term) } }
                }
                ParentAction("Messagerie", Icons.Default.Mail) {
                    step = "messages"
                    scope.launch { conversations = withContext(Dispatchers.IO) { api.teacherConversations(code) } }
                }
                ParentAction("Messages de la Direction", Icons.Default.Campaign) { step = "direction" }
            }
            "assignments" -> {
                TextButton(onClick = { step = "home" }) { Text("← Tableau de bord") }
                Text("Saisie de Notes", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(10.dp))
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) { items(assignments) { a -> ParentAction("${a.className} • ${a.subjectName}${if (a.homeroom) " • Titulaire" else ""}", Icons.Default.Class) { selectedAssignment = a; noteType = ""; step = "noteTypes" } } }
            }
            "noteTypes" -> {
                TextButton(onClick = { selectedAssignment = null; step = "assignments" }) { Text("← Mes classes") }
                Text("${selectedAssignment!!.className} — ${selectedAssignment!!.subjectName}", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(10.dp)); Text("1. Choisissez d'abord le type de note", fontWeight = FontWeight.Bold); Spacer(Modifier.height(8.dp))
                listOf("devoir" to "Devoir", "moyenne_classe" to "Moyenne de classe", "composition" to "Composition").forEach { (value, label) ->
                    ParentAction(label, if (value == "composition") Icons.Default.Assignment else Icons.Default.EditNote) {
                        noteType = value; search = ""; selectedStudent = null
                        scope.launch { students = withContext(Dispatchers.IO) { api.teacherStudents(code, selectedAssignment!!.classId) } }
                        step = "students"
                    }
                }
            }
            "students" -> {
                TextButton(onClick = { step = "noteTypes" }) { Text("← Type de note") }
                Text("${selectedAssignment!!.className} — ${selectedAssignment!!.subjectName}", fontSize = 22.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("Type : ${if (noteType == "moyenne_classe") "Moyenne de classe" else if (noteType == "composition") "Composition" else "Devoir"}", color = Color.Gray)
                Spacer(Modifier.height(8.dp)); TermTabs(term) { term = it }
                Spacer(Modifier.height(8.dp)); OutlinedTextField(search, { search = it }, Modifier.fillMaxWidth(), label = { Text("Rechercher un élève") }, singleLine = true)
                Spacer(Modifier.height(10.dp)); Text("2. Liste alphabétique des élèves", fontWeight = FontWeight.Bold)
                Spacer(Modifier.height(6.dp)); LazyColumn(verticalArrangement = Arrangement.spacedBy(7.dp)) { items(visibleStudents) { s -> Card(Modifier.fillMaxWidth().clickable { selectedStudent = s; noteValue = ""; noteTitle = ""; message = ""; step = "entry" }, shape = RoundedCornerShape(14.dp)) { Row(Modifier.padding(14.dp), verticalAlignment = Alignment.CenterVertically) { Text(s.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); Icon(Icons.Default.ChevronRight, null) } } } }
            }
            "entry" -> {
                val currentIndex = students.indexOfFirst { it.id == selectedStudent!!.id }
                val isLast = currentIndex >= students.lastIndex
                TextButton(onClick = { selectedStudent = null; step = "students" }) { Text("← Liste des élèves") }
                Text(selectedStudent!!.name, fontSize = 24.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("${selectedAssignment!!.subjectName} • ${if (noteType == "moyenne_classe") "Moyenne de classe" else if (noteType == "composition") "Composition" else "Devoir"} • $term", color = Color.Gray)
                Spacer(Modifier.height(20.dp))
                if (noteType == "devoir") { OutlinedTextField(noteTitle, { noteTitle = it }, label = { Text("Libellé du devoir") }, modifier = Modifier.fillMaxWidth()); Spacer(Modifier.height(10.dp)) }
                OutlinedTextField(value = noteValue, onValueChange = { raw -> val normalized = raw.replace(',', '.'); if (normalized.matches(Regex("^\\d{0,2}(\\.\\d{0,2})?$"))) noteValue = normalized }, label = { Text("Note sur 20") }, placeholder = { Text("Ex. 8,75 ou 19,5") }, supportingText = { Text("Jusqu'à 2 chiffres après la virgule") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
                Spacer(Modifier.height(12.dp))
                Button(onClick = {
                    val v = noteValue.replace(',','.').toDoubleOrNull()
                    if (v != null && v in 0.0..20.0) {
                        scope.launch { try { withContext(Dispatchers.IO) { api.saveNote(code, selectedStudent!!.id, selectedAssignment!!.assignmentId, term, noteType, v, noteTitle.ifBlank { null }) }; message = "Note enregistrée."; noteValue = ""; noteTitle = ""; val next = students.getOrNull(currentIndex + 1); if (next != null) selectedStudent = next else step = "students" } catch (e: Exception) { message = "Erreur : ${e.message?.take(100) ?: "enregistrement impossible"}" } }
                    } else message = "Entrez une note entre 0 et 20."
                }, modifier = Modifier.fillMaxWidth().height(54.dp)) { Text(if (isLast) "ENREGISTRER ET TERMINER" else "ENREGISTRER ET SUIVRE →", fontWeight = FontWeight.Bold) }
                if (message.isNotBlank()) { Spacer(Modifier.height(10.dp)); Text(message, color = if (message.startsWith("Erreur")) Red else DarkGreen) }
                Spacer(Modifier.height(18.dp)); Text("Élève ${currentIndex + 1} / ${students.size}", color = Color.Gray, fontSize = 12.sp)
            }
            "statistics" -> {
                TextButton(onClick = { step = "home" }) { Text("← Tableau de bord") }
                Text("Statistique", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Spacer(Modifier.height(8.dp)); TermTabs(term) { newTerm -> term = newTerm; scope.launch { classStats = withContext(Dispatchers.IO) { api.teacherClassStats(code, term) } } }
                Spacer(Modifier.height(10.dp)); Text("Classes et effectifs", fontWeight = FontWeight.Bold)
                LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) { items(classStats) { c -> ParentAction("${c.className}  •  ${c.effectif} élève${if (c.effectif > 1) "s" else ""}", Icons.Default.Groups) { selectedStatClass = c; scope.launch { rankings = withContext(Dispatchers.IO) { api.teacherRankings(code, c.classId, term) }; step = "ranking" } } } }
            }
            "ranking" -> {
                TextButton(onClick = { selectedStatClass = null; rankings = emptyList(); step = "statistics" }) { Text("← Statistique") }
                Text("${selectedStatClass!!.className} — Classement", fontSize = 23.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("${term} • moyenne générale uniquement (devoirs exclus)", color = Color.Gray, fontSize = 12.sp)
                Spacer(Modifier.height(10.dp))
                LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) { items(rankings) { r -> Card(Modifier.fillMaxWidth(), shape = RoundedCornerShape(14.dp)) { Row(Modifier.padding(15.dp), verticalAlignment = Alignment.CenterVertically) { Text("${rankings.indexOf(r) + 1}", fontSize = 20.sp, fontWeight = FontWeight.Black, color = DarkGreen, modifier = Modifier.width(36.dp)); Text(r.name, fontWeight = FontWeight.Bold, modifier = Modifier.weight(1f)); Text(r.generalAverage?.let { String.format(Locale.FRANCE, "%.2f / 20", it) } ?: "—", fontSize = 18.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen) } } } }
            }
            "messages" -> {
                TextButton(onClick = { step = "home" }) { Text("← Tableau de bord") }
                Text("Messagerie", fontSize = 25.sp, fontWeight = FontWeight.ExtraBold, color = DarkGreen)
                Text("5 messages maximum par jour et par compte. Réinitialisation à 00h GMT.", fontSize = 11.sp, color = Color.Gray)
                Spacer(Modifier.height(10.dp))
                LazyColumn(verticalArrangement = Arrangement.spacedBy(9.dp)) { items(conversations) { c -> ParentAction("Parent de ${c.studentName}", Icons.Default.Person) { selectedConversation = c; step = "conversation" } } }
                if (conversations.isEmpty()) Text("Aucun message reçu.", color = Color.Gray)
            }
            "conversation" -> selectedConversation?.let { c ->
                TeacherConversationScreen(api, code, c, { selectedConversation = null; step = "messages" })
            }
            "direction" -> TeacherDirectionMessagesScreen(api, code) { step = "home" }
        }
    }
}

@Composable
private fun TeacherConversationScreen(api: VicApi, code: String, conversation: TeacherConversation, back: () -> Unit) {
    var messages by remember { mutableStateOf<List<ChatMessage>>(emptyList()) }
    var text by remember { mutableStateOf("") }
    var error by remember { mutableStateOf("") }
    val scope = rememberCoroutineScope()
    BackHandler { back() }
    fun refresh() { scope.launch { runCatching { messages = withContext(Dispatchers.IO) { api.teacherMessages(code, conversation.studentId, conversation.parentId) } }.onFailure { error = it.message ?: "Erreur" } } }
    LaunchedEffect(Unit) { refresh() }
    Column(Modifier.fillMaxSize()) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = back) { Icon(Icons.Default.ArrowBack, "Retour") }
            Column { Text("Parent de ${conversation.studentName}", fontWeight = FontWeight.Bold); Text(conversation.parentName, fontSize = 11.sp, color = Color.Gray); Text(conversation.className, fontSize = 11.sp, color = Color.Gray) }
        }
        Text("5 messages maximum par jour et par compte. Réinitialisation à 00h GMT.", fontSize = 11.sp, color = Color.Gray)
        if (error.isNotBlank()) Text(error, color = Red, fontSize = 12.sp)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), contentPadding = PaddingValues(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { items(messages) { m -> Row(Modifier.fillMaxWidth(), horizontalArrangement = if (m.senderRole == "teacher") Arrangement.End else Arrangement.Start) { Card(shape = RoundedCornerShape(16.dp)) { Column(Modifier.padding(12.dp)) { Text(m.body); Text(m.createdAt, fontSize = 9.sp, color = Color.Gray) } } } } }
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(text, { text = it }, Modifier.weight(1f), placeholder = { Text("Votre message...") }, maxLines = 4)
            IconButton(onClick = { if (text.isNotBlank()) { val sent = text.trim(); text = ""; error = ""; scope.launch { runCatching { withContext(Dispatchers.IO) { api.sendTeacherMessage(code, conversation.studentId, conversation.parentId, sent) }; refresh() }.onFailure { error = it.message ?: "Envoi impossible." } } } }) { Icon(Icons.Default.Send, "Envoyer", tint = DarkGreen) }
        }
    }
}

