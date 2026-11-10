# Fish shell: list local documents.
function reading_list
    for document in *.md
        printf 'Continue reading: %s\n' "$document"
    end
end
