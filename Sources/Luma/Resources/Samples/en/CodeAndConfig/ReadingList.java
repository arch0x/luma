import java.util.List;

public class ReadingList {
    record Document(String title, boolean read) {}

    public static void main(String[] args) {
        var notes = List.of(new Document("Read with clarity", false));
        notes.stream().filter(note -> !note.read())
            .forEach(note -> System.out.println(note.title()));
    }
}
