package main

import "fmt"

type Document struct {
    Title string
    Read  bool
}

func main() {
    note := Document{Title: "Read with clarity", Read: false}
    fmt.Println(note.Title)
}
