package main

import "fmt"

type Document struct {
    Title string
    Read  bool
}

func main() {
    note := Document{Title: "读得清楚", Read: false}
    fmt.Println(note.Title)
}
