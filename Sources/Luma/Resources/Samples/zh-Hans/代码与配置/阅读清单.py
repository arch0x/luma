from pathlib import Path

def reading_list(folder: Path) -> list[str]:
    """按名称列出 Markdown 文档。"""
    return sorted(path.name for path in folder.glob("*.md"))

if __name__ == "__main__":
    print(reading_list(Path(".")))
