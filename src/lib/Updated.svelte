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
      .flatMap((s) => [...s.body.matchAll(/^### (.+)|^- \*\*(.+?)[.,:]?\*\*/gm)])
      .map((m, i, all) => ({ text: m[2], removed: all.findLast((h, j) => j <= i && h[1])?.[1] === "Removed" }))
      .filter((h) => h.text)
      .slice(0, 6);
  });
</script>

<div class="updated" data-tauri-drag-region>
  <img class="logo" src="/logo.png" alt="" />
  <h1>Nyx was <span class="add">updated</span> !</h1>
  {#if highlights.length}
    <ul>
      {#each highlights as h}<li><span class={h.removed ? "remove" : "add"}>{h.removed ? "−" : "+"}</span> {h.text}</li>{/each}
    </ul>
  {/if}
  <button class="pill" onclick={() => api.openLink("changelog")}>View Changelog</button>
  <button class="muted later" onclick={ondone}>Continue</button>
</div>

<style>
  .updated { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 18px; padding: 30px 20px; }
  .logo { height: 84px; }
  h1 { font-size: 18px; font-weight: 500; }
  .add { color: var(--ok); }
  .remove { color: var(--danger); }
  ul { list-style: none; padding: 0; display: flex; flex-direction: column; gap: 8px; text-align: center; font-size: 12px; }
  .later { font-size: 11px; text-decoration: underline; }
</style>
