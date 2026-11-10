interface ReadingItem {
  title: string;
  progress: number;
}

export const documents: ReadingItem[] = [
  { title: "Design notes", progress: 1 },
  { title: "Lab notes", progress: 0.5 },
];

export const unfinished = documents.filter(item => item.progress < 1);
