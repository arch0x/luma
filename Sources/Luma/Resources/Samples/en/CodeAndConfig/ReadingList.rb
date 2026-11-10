Document = Struct.new(:title, :read, keyword_init: true)
documents = [
  Document.new(title: "Design notes", read: true),
  Document.new(title: "Lab notes", read: false)
]

documents.reject(&:read).each { |item| puts "Continue reading: #{item.title}" }
