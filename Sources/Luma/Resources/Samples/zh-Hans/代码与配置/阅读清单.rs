struct Document<'a> {
    title: &'a str,
    read: bool,
}

fn main() {
    let document = Document { title: "读得清楚", read: false };
    if !document.read {
        println!("继续阅读：{}", document.title);
    }
}
