struct Document<'a> {
    title: &'a str,
    read: bool,
}

fn main() {
    let document = Document { title: "Read with clarity", read: false };
    if !document.read {
        println!("Continue reading: {}", document.title);
    }
}
