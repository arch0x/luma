data class Document(val title: String, val read: Boolean = false)

fun main() {
    val notes = listOf(Document("设计文档", true), Document("实验记录"))
    notes.filterNot { it.read }.forEach { println(it.title) }
}
