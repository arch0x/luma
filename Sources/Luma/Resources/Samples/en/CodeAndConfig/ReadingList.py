from pathlib import Path

def reading_list(folder: Path) -> list[str]:
    """List Markdown documents by name."""
    return sorted(path.name for path in folder.glob("*.md"))

if __name__ == "__main__":
    print(reading_list(Path(".")))
