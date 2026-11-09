<script lang="ts">
  let title = "读得清楚";
  const collections = ["设计文档", "实验记录", "代码片段"];
</script>

<article class="reading-card">
  <h1>{title}</h1>
  <p>留一点空间，给专注。</p>
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
