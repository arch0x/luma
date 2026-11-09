<script setup lang="ts">
const document = {
  title: "读得清楚",
  subtitle: "留一点空间，给专注。",
  format: "Markdown",
};
</script>

<template>
  <article class="reading-card">
    <span class="reading-card__format">{{ document.format }}</span>
    <h1>{{ document.title }}</h1>
    <p>{{ document.subtitle }}</p>
    <button type="button">继续阅读</button>
  </article>
</template>

<style scoped>
.reading-card {
  max-width: 32rem;
  padding: 2rem;
  color: #1a202b;
  background: #fcfcfa;
  border: 1px solid #3a6095;
  border-radius: 1rem;
}
</style>
