// 一段独立的 JavaScript 模块。
export const documents = [
  { title: "设计文档", read: true },
  { title: "实验记录", read: false },
];

export function unreadTitles(items = documents) {
  return items.filter(item => !item.read).map(item => item.title);
}
