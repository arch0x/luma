interface ReadingItem {
  title: string;
  progress: number;
}

export const documents: ReadingItem[] = [
  { title: "设计文档", progress: 1 },
  { title: "实验记录", progress: 0.5 },
];

export const unfinished = documents.filter(item => item.progress < 1);
