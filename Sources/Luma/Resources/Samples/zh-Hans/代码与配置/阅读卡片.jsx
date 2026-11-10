export default function ReadingCard({ title = "读得清楚", progress = 0 }) {
  return (
    <article className="reading-card">
      <h1>{title}</h1>
      <progress max={100} value={progress} />
      <p>留一点空间，给专注。</p>
    </article>
  );
}
