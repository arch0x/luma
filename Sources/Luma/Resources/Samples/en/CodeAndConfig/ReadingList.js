// A standalone JavaScript module.
export const documents = [
  { title: "Design notes", read: true },
  { title: "Lab notes", read: false },
];

export function unreadTitles(items = documents) {
  return items.filter(item => !item.read).map(item => item.title);
}
