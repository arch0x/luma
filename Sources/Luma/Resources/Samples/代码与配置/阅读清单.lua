local documents = {
  { title = "设计文档", read = true },
  { title = "实验记录", read = false },
}

for _, document in ipairs(documents) do
  if not document.read then
    print("继续阅读：" .. document.title)
  end
end
