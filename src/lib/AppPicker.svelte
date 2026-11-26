<script lang="ts">
  import { onMount } from "svelte";
  import * as api from "./api";

  let { exclude, onclose }: { exclude: string[]; onclose: () => void } = $props();
  let filter = $state("");
  let apps = $state<api.Row[] | null>(null);
  const shown = $derived((apps ?? []).filter((a) => a.name.toLowerCase().includes(filter.trim().toLowerCase())));

  onMount(() => api.pickable(exclude).then((found) => (apps = found)));

  async function pick(app: api.Row) {
    await api.addApp(app.path);
    onclose();
  }
</script>

<div class="panel picker">
  <!-- svelte-ignore a11y_autofocus -->
  <input placeholder="Filter…" bind:value={filter} autofocus />
  <div class="rule"></div>
  <div class="list">
    {#if apps === null}<p class="muted note">Looking for apps…</p>{/if}
    {#each shown as app (app.id)}
      <button class="item" onclick={() => pick(app)}>
        <img src={api.icon(app.path)} alt="" loading="lazy" onerror={(e) => ((e.currentTarget as HTMLElement).style.visibility = "hidden")} />
        <span>{app.name}</span>
      </button>
    {/each}
  </div>
</div>

<style>
  .picker { width: 260px; height: 360px; display: flex; flex-direction: column; overflow: hidden; }
  input { border: none; outline: none; background: none; padding: 10px; font-size: 12px; }
  .rule { height: 1px; background: var(--hairline); }
  .list { flex: 1; overflow-y: auto; }
  .note { padding: 10px; font-size: 11px; }
  .item { display: flex; align-items: center; gap: 8px; width: 100%; height: 30px; padding: 0 10px; text-align: left; }
  .item:hover { background: var(--row); }
  img { width: 18px; height: 18px; flex: none; }
  span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
</style>
