<script lang="ts">
  import { onMount } from "svelte";
  import { listen } from "@tauri-apps/api/event";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import * as api from "$lib/api";
  import AppPicker from "$lib/AppPicker.svelte";
  import SiteEntry from "$lib/SiteEntry.svelte";
  import Settings from "$lib/Settings.svelte";

  let snap = $state<api.Snapshot | null>(null);
  let open = $state<"app" | "site" | "settings" | null>(null);
  const close = () => (open = null);
  // Starts on whatever the system is set to, then follows the settings switch.
  let dark = $state(JSON.parse(localStorage.getItem("nyx.dark") ?? String(matchMedia("(prefers-color-scheme: dark)").matches)));
  $effect(() => {
    localStorage.setItem("nyx.dark", String(dark));
    document.documentElement.classList.toggle("dark", dark);
    getCurrentWindow().setTheme(dark ? "dark" : "light");
  });
  const refresh = async () => (snap = await api.snapshot());
  const empty = $derived(snap !== null && snap.apps.length === 0 && snap.sites.length === 0);

  onMount(() => {
    refresh();
    const unlisten = listen("changed", refresh);
    // Grants arrive from System Settings, which sends no event, so they are polled while shown.
    const timer = setInterval(() => !document.hidden && refresh(), 2000);
    // Esc abandons an open panel first, and only then closes the dashboard.
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && (open ? close() : getCurrentWindow().close());
    window.addEventListener("keydown", onKey);
    return () => {
      unlisten.then((stop) => stop());
      clearInterval(timer);
      window.removeEventListener("keydown", onKey);
    };
  });
</script>

{#if snap}
  <div class="top" data-tauri-drag-region>
    <button class="gear" title="Settings" aria-label="Settings" onclick={() => (open = "settings")}>
      <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor">
        {#each [0, 45, 90, 135, 180, 225, 270, 315] as turn}
          <rect x="10" y="1.5" width="4" height="5" rx="1" transform="rotate({turn} 12 12)" />
        {/each}
        <circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" stroke-width="3" />
      </svg>
    </button>
  </div>
  <header data-tauri-drag-region>
    <div class="tile"><div class="owl"></div></div>
    <div class="title" data-tauri-drag-region>
      <div class="name">Nyx</div>
      <div class="muted small">Screen-share privacy</div>
    </div>
    <button class="credit" title="unravel.tech" aria-label="Unravel" onclick={() => api.openLink("unravel")}>
      <span class="muted small">Developed by</span>
      <img src="/unravel.png" alt="" />
    </button>
  </header>
  <div class="hr"></div>
  {#if !snap.screenPermission}
    <div class="banner">
      <span>Nyx needs Screen Recording to mirror your windows</span>
      <button onclick={() => api.openLink("screen")}>Open Settings</button>
    </div>
  {/if}
  {#if snap.sites.length && !snap.accessibilityPermission}
    <div class="banner">
      <span>Nyx needs Accessibility to read the browser's address bar</span>
      <button onclick={() => api.openLink("accessibility")}>Open Settings</button>
    </div>
  {/if}
  {#if snap.notice}<p class="banner">{snap.notice}</p>{/if}
  {#if snap.loadFailed}
    <p class="banner failed">
      Nyx could not read your saved list — nothing is protected until you add an app again. The file is at {snap.storePath}.
    </p>
  {/if}

  <main class:disabled={!snap.screenPermission} inert={!snap.screenPermission}>
    {#if empty}
      <div class="empty">
        <div class="owl big"></div>
        <p class="muted">Nothing protected yet.<br />Add an app, or press {snap.hotkey} while using one.</p>
        <button class="pill" onclick={() => (open = "app")}>+ Add app…</button>
        <p class="muted small">Or cover a site whenever it is your front tab.</p>
        <button class="pill" onclick={() => (open = "site")}>+ Add website…</button>
      </div>
    {:else}
      <div class="label section">PROTECTED APPS</div>
      {#each snap.apps as app (app.id)}
        <div class="row">
          {#if app.path}<img class="icon" src={api.icon(app.path)} alt="" />{:else}<span class="icon blank"></span>{/if}
          <span class="grow">{app.name}</span>
          <button class="remove" title="Stop protecting {app.name}" onclick={() => api.removeApp(app.id)}>Remove</button>
        </div>
      {/each}
      <button class="pill add" onclick={() => (open = "app")}>+ Add app…</button>
      <div class="label section">PROTECTED SITES</div>
      {#each snap.sites as host (host)}
        <div class="row site">
          <span class="grow">{host}</span>
          <button class="remove" title="Stop covering {host}" onclick={() => api.removeSite(host)}>Remove</button>
        </div>
      {/each}
      <button class="pill add" onclick={() => (open = "site")}>+ Add website…</button>
    {/if}
  </main>

  {#if open}<div class="backdrop" role="presentation" onclick={close}></div>{/if}
  {#if open === "app"}<AppPicker exclude={snap.apps.map((a) => a.id)} onclose={close} />{/if}
  {#if open === "site"}<SiteEntry onclose={close} />{/if}
  {#if open === "settings"}<Settings bind:dark platform={snap.platform} />{/if}

  <div class="hr"></div>
  <footer>
    <!-- Idle carries no status row: doing nothing is the resting state and needs no announcing. -->
    {#if snap.state !== "idle"}
      <div class="status">
        <span class="dot" class:blind={snap.state === "blind"}></span>
        {snap.state === "blind" ? "Hidden — no local preview" : "Protection active"}
      </div>
      {#if snap.state === "blind"}
        <p class="danger small">Viewers see the placeholder, but Nyx cannot mirror the window back to you. Retrying.</p>
      {/if}
    {/if}
    <div class="hint">
      <span class="chip">{snap.hotkey}</span>
      <span class="muted small">Protect the app you're using, or unprotect it.</span>
    </div>
  </footer>
{/if}

<style>
  :global(body) { display: flex; flex-direction: column; }
  .top { height: 30px; flex: none; display: flex; justify-content: flex-end; align-items: center; padding-right: 12px; }
  header { display: flex; align-items: center; gap: 12px; padding: 0 16px 18px; }
  .tile { width: 46px; height: 46px; border-radius: 11px; background: var(--control); border: 1px solid var(--border); display: grid; place-items: center; }
  .tile .owl { width: 28px; height: 28px; }
  .title { flex: 1; display: flex; flex-direction: column; gap: 3px; }
  .name { font-size: 17px; font-weight: 500; }
  .small { font-size: 11px; }
  /* Monospace: 12ch is exactly "Developed by", so the wordmark squares off with it. */
  .credit { width: 12ch; font-size: 11px; display: flex; flex-direction: column; align-items: flex-end; gap: 4px; cursor: pointer; }
  .credit img { width: 100%; }
  .hr { height: 1px; background: var(--hairline); flex: none; }
  main { flex: 1; overflow-y: auto; position: relative; }
  main.disabled { opacity: 0.4; }
  .section { padding-top: 16px; }
  .section ~ .section { padding-top: 22px; }
  .row { display: flex; align-items: center; gap: 10px; height: 36px; padding: 0 16px; font-size: 13px; }
  .row.site { height: 32px; }
  .row:hover { background: var(--row); }
  .gear { width: 26px; height: 24px; display: grid; place-items: center; border-radius: 6px; color: var(--muted); background: var(--control); border: 1px solid var(--border); }
  .banner { display: flex; align-items: center; gap: 10px; padding: 12px; font-size: 11px; color: var(--amber-text); background: color-mix(in srgb, var(--amber) 12%, transparent); }
  .banner span { flex: 1; }
  .banner button { font-weight: 500; padding: 5px 10px; border-radius: 5px; background: var(--amber); color: var(--ink-on-amber); white-space: nowrap; }
  .banner.failed { color: var(--danger); background: color-mix(in srgb, var(--danger) 12%, transparent); line-height: 1.5; }
  .add { margin: 8px 16px 0; }
  .backdrop { position: fixed; inset: 0; z-index: 5; }
  .grow { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .icon { width: 20px; height: 20px; }
  .blank { border-radius: 5px; background: var(--control); }
  .remove { font-size: 10px; font-weight: 500; color: var(--muted); padding: 3px 8px; border-radius: 5px; border: 1px solid var(--border); }
  .row:hover .remove { color: var(--text); background: var(--control); }
  .empty { height: 100%; display: flex; flex-direction: column; align-items: center; justify-content: center; gap: 14px; text-align: center; line-height: 1.6; }
  .owl.big { width: 60px; height: 72px; color: var(--muted); opacity: 0.35; }
  footer { padding: 12px 16px; display: flex; flex-direction: column; gap: 8px; }
  .status { display: flex; align-items: center; gap: 8px; }
  .dot { width: 6px; height: 6px; border-radius: 50%; background: var(--amber-text); }
  .dot.blind { background: var(--danger); }
  .danger { color: var(--danger); font-size: 10px; }
  .hint { display: flex; align-items: center; gap: 9px; }
  .chip { font-size: 11px; font-weight: 500; padding: 3px 7px; border-radius: 5px; background: var(--control); border: 1px solid var(--border); }
</style>
