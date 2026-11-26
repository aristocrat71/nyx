<script lang="ts">
  import changelog from "../../CHANGELOG.md?raw";
  import * as api from "./api";

  let { version, from, ondone }: { version: string; from: string | null; ondone: () => void } = $props();

  // The bold lead of each changelog entry, for every version since `from` (just this one when unknown).
  const highlights = $derived.by(() => {
    const sections = changelog.split(/^## \[/m).slice(1).map((s) => ({ v: s.slice(0, s.indexOf("]")), body: s }));
    const start = sections.findIndex((s) => s.v === version);
    if (start < 0) return [];
    const end = sections.findIndex((s, i) => i > start && (!from || s.v === from));
    return sections
      .slice(start, end < 0 ? undefined : end)
      .flatMap((s) => [...s.body.matchAll(/^- \*\*(.+?)[.,:]?\*\*/gm)].map((m) => m[1]))
      .slice(0, 6);
  });
</script>

<div class="updated" data-tauri-drag-region>
  <div class="tile"><div class="owl"></div></div>
  <h1>Nyx was updated!</h1>
  {#if highlights.length}
    <ul>
      {#each highlights as line}<li>{line}</li>{/each}
    </ul>
  {/if}
  <button class="pill" onclick={() => api.openLink("changelog")}>View Changelog</button>
  <button class="muted later" onclick={ondone}>Continue</button>
</div>

<style>
  .updated { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 18px; padding: 30px 20px; }
  .tile { width: 64px; height: 64px; border-radius: 15px; background: #000; display: grid; place-items: center; border: 1px solid var(--border); }
  .owl { width: 36px; height: 42px; color: #fff; }
  h1 { font-size: 14px; font-weight: 500; }
  ul { list-style: none; padding: 0; display: flex; flex-direction: column; gap: 8px; text-align: center; font-size: 12px; }
  .later { font-size: 11px; text-decoration: underline; }
</style>
