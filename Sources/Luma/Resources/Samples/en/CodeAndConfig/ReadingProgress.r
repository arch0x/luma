documents <- data.frame(
  title = c("Design notes", "Lab notes", "Code snippets"),
  progress = c(1.0, 0.5, 0.0)
)

unfinished <- subset(documents, progress < 1)
print(unfinished)
