# Markdown，让内容更清楚

这份示例可以检查 **表格、Mermaid 和代码语法高亮**。所需引擎随应用打包，断网也可以阅读。

## 表格与列对齐

| 功能 | 状态 | 优先级 |
| :--- | :---: | ---: |
| **表格排版** | 已支持 | 1 |
| Mermaid 流程图 | 已支持 | 2 |
| `代码高亮` | 已支持 | 3 |
| 转义分隔符：a\|b | 可阅读 | 4 |

宽表格可以横向滚动，单元格内支持行内强调、链接和代码。

## Mermaid 流程图

```mermaid
flowchart LR
    A[打开本地文件] --> B{文件类型}
    B -->|Markdown| C[排版预览]
    B -->|JSON| D[结构视图]
    B -->|PDF| E[原生阅读器]
    C --> F[清楚阅读]
    D --> F
    E --> F
```

## Mermaid 时序图

```mermaid
sequenceDiagram
    participant 你
    participant Luma
    participant 本地文件
    你->>Luma: 打开文档
    Luma->>本地文件: 只读访问
    本地文件-->>Luma: 文件内容
    Luma-->>你: 展示预览
```

## Swift

```swift
struct ReadingSpace {
    let name = "Luma"
    var documents: [String] = []

    func contains(_ name: String) -> Bool {
        // 让每天打开的文件触手可及
        documents.contains(name)
    }
}
```

## TypeScript

```typescript
interface Document {
  name: string;
  readOnly: boolean;
}

const document: Document = {
  name: "Markdown增强预览.md",
  readOnly: true,
};

console.log(document.name);
```

## Python 与 JSON

```python
from pathlib import Path

def read_document(path: Path) -> str:
    """Keep files local, keep reading simple."""
    return path.read_text(encoding="utf-8")
```

```json
{
  "name": "Luma",
  "offline": true,
  "features": ["table", "mermaid", "syntax highlighting"]
}
```

## 图表写错也不会丢失内容

下面故意放了一个错误的图表，应该显示错误提示并保留完整源码；后面的内容仍可正常阅读。

```mermaid
flowchart LR
    A --> [
```

**阅读继续。** 使用预览 / 源码切换，可以随时看到原始 Markdown。
