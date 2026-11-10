local documents = {
  { title = "Design notes", read = true },
  { title = "Lab notes", read = false },
}

for _, document in ipairs(documents) do
  if not document.read then
    print("Continue reading: " .. document.title)
  end
end
