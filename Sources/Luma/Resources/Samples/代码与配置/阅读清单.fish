# Fish shell：列出本地文档。
function reading_list
    for document in *.md
        printf '继续阅读：%s\n' "$document"
    end
end
