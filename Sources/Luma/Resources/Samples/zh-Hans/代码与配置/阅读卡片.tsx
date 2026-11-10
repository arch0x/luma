type Props = { title: string; progress?: number };

export default function ReadingCard({ title, progress = 0 }: Props) {
  return (
    <article className="reading-card">
      <h1>{title}</h1>
      <progress max={100} value={progress} />
    </article>
  );
}
