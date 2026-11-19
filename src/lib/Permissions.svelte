<script lang="ts">
  import * as api from "./api";

  let { snap }: { snap: api.Snapshot } = $props();
  const rows = $derived([
    { key: "screen", name: "Screen Recording", why: "Shows you the app under the cover.", granted: snap.screenPermission },
    { key: "accessibility", name: "Accessibility", why: "Reads the browser's address bar.", granted: snap.accessibilityPermission },
  ] as const);
</script>

<div class="perms" data-tauri-drag-region>
  <div class="owl"></div>
  <h1>Two permissions, then you're set.</h1>
  <div class="list">
    {#each rows as row (row.key)}
      <div class="row" class:granted={row.granted}>
        <div class="text">
          <span>{row.name}</span>
          <span class="muted small">{row.why}</span>
        </div>
        {#if row.granted}
          <span class="ok">✓ Allowed</span>
        {:else}
          <button class="pill" onclick={() => api.openLink(row.key)}>Open Settings</button>
        {/if}
      </div>
    {/each}
  </div>
  {#if snap.platform === "macos"}
    <p class="muted small info">
      Nyx not in the list? Click <kbd>+</kbd> below it and choose Nyx.<br />
      macOS may ask to reopen Nyx after Screen Recording.
    </p>
  {/if}
</div>

<style>
  .perms { flex: 1; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 22px; padding: 30px 20px; }
  .owl { width: 40px; height: 48px; color: var(--muted); opacity: 0.5; }
  h1 { font-size: 14px; font-weight: 500; }
  .list { width: 100%; border: 1px solid var(--border); border-radius: 8px; background: var(--panel); }
  .row { display: flex; align-items: center; gap: 12px; padding: 14px; }
  .row + .row { border-top: 1px solid var(--hairline); }
  .text { flex: 1; display: flex; flex-direction: column; gap: 4px; font-size: 12px; }
  .small { font-size: 11px; }
  .ok { font-size: 11px; font-weight: 500; color: var(--amber-text); }
  .info { text-align: center; line-height: 1.7; }
  kbd { font: inherit; padding: 0 5px; border-radius: 4px; border: 1px solid var(--border); background: var(--control); }
</style>
