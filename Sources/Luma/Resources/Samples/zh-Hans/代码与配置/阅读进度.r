documents <- data.frame(
  title = c("设计文档", "实验记录", "代码片段"),
  progress = c(1.0, 0.5, 0.0)
)

unfinished <- subset(documents, progress < 1)
print(unfinished)
