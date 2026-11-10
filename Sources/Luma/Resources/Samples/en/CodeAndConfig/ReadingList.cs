using System;
using System.Linq;

public record Document(string Title, bool Read);

public static class Program {
    public static void Main() {
        var notes = new[] { new Document("Read with clarity", false) };
        foreach (var note in notes.Where(item => !item.Read))
            Console.WriteLine(note.Title);
    }
}
