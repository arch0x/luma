export default function ReadingCard({ title = "Read with clarity", progress = 0 }) {
  return (
    <article className="reading-card">
      <h1>{title}</h1>
      <progress max={100} value={progress} />
      <p>A little room to focus.</p>
    </article>
  );
}
