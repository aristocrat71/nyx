<script lang="ts">
  import * as api from "./api";

  let { onclose }: { onclose: () => void } = $props();
  let field = $state("");
  let host = $state<string | null>(null);

  $effect(() => {
    const typed = field;
    api.normalizeSite(typed).then((h) => typed === field && (host = h));
  });

  async function commit(e: Event) {
    e.preventDefault();
    if (host && (await api.addSite(field))) onclose();
  }
</script>

<form class="panel entry" onsubmit={commit}>
  <!-- svelte-ignore a11y_autofocus -->
  <input placeholder="youtube.com" bind:value={field} autofocus />
  <!-- Only once something typed is rejected: shown up front it repeats the placeholder. -->
  {#if field.trim() && !host}
    <p class="muted">Enter a host like youtube.com, or paste a page address.</p>
  {/if}
  <button class="pill" disabled={!host}>Add</button>
</form>

<style>
  .entry { width: 260px; padding: 14px; display: flex; flex-direction: column; align-items: flex-start; gap: 8px; }
  input { width: 100%; height: 26px; padding: 0 9px; border-radius: 6px; background: var(--control); border: 1px solid var(--border); outline: none; }
  p { font-size: 10px; }
</style>
