Document = Struct.new(:title, :read, keyword_init: true)
documents = [
  Document.new(title: "设计文档", read: true),
  Document.new(title: "实验记录", read: false)
]

documents.reject(&:read).each { |item| puts "继续阅读：#{item.title}" }
