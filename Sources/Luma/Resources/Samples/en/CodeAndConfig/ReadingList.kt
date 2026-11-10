data class Document(val title: String, val read: Boolean = false)

fun main() {
    val notes = listOf(Document("Design notes", true), Document("Lab notes"))
    notes.filterNot { it.read }.forEach { println(it.title) }
}
