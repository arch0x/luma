-- SQL reading example; opening it does not execute queries.
CREATE TABLE documents (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    progress REAL DEFAULT 0
);

INSERT INTO documents (title, progress) VALUES ('Design notes', 0.5);
SELECT title FROM documents WHERE progress < 1 ORDER BY title;
