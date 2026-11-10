<script lang="ts">
  let title = "Read with clarity";
  const collections = ["Design notes", "Lab notes", "Code snippets"];
</script>

<article class="reading-card">
  <h1>{title}</h1>
  <p>A little room to focus.</p>
  <ul>
    {#each collections as collection}
      <li>{collection}</li>
    {/each}
  </ul>
</article>

<style>
  .reading-card {
    max-width: 32rem;
    padding: 2rem;
    color: #1a202b;
    background: #fcfcfa;
    border-left: 3px solid #3a6095;
  }
</style>
