-- 这是一份供阅读的 SQL 源文件，打开时不会执行。
CREATE TABLE documents (
    id INTEGER PRIMARY KEY,
    title TEXT NOT NULL,
    progress REAL DEFAULT 0
);

INSERT INTO documents (title, progress) VALUES ('设计文档', 0.5);
SELECT title FROM documents WHERE progress < 1 ORDER BY title;
