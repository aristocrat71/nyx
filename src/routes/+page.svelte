<script lang="ts">
  import { onMount } from "svelte";
  import { listen } from "@tauri-apps/api/event";
  import { getCurrentWindow } from "@tauri-apps/api/window";
  import { getVersion } from "@tauri-apps/api/app";
  import * as api from "$lib/api";
  import AppPicker from "$lib/AppPicker.svelte";
  import SiteEntry from "$lib/SiteEntry.svelte";
  import Settings from "$lib/Settings.svelte";
  import Intro from "$lib/Intro.svelte";
  import Permissions from "$lib/Permissions.svelte";
  import Updated from "$lib/Updated.svelte";

  let snap = $state<api.Snapshot | null>(null);
  let open = $state<"app" | "site" | "settings" | null>(null);
  const close = () => (open = null);
  let at = $state({ x: 0, y: 0 });
  const show = (what: "app" | "site", e: MouseEvent) => {
    const r = (e.currentTarget as HTMLElement).getBoundingClientRect();
    at = { x: r.right + 8, y: r.top };
    open = what;
  };
  // Pulls a panel opened beside its button back inside the window when it would spill out.
  const fit = (el: HTMLElement) => {
    const r = (el.firstElementChild as HTMLElement).getBoundingClientRect();
    el.style.left = `${Math.max(8, Math.min(r.left, innerWidth - r.width - 8))}px`;
    el.style.top = `${Math.max(8, Math.min(r.top, innerHeight - r.height - 8))}px`;
  };
  // Starts on whatever the system is set to, then follows the settings switch.
  let dark = $state(JSON.parse(localStorage.getItem("nyx.dark") ?? String(matchMedia("(prefers-color-scheme: dark)").matches)));
  $effect(() => {
    localStorage.setItem("nyx.dark", String(dark));
    document.documentElement.classList.toggle("dark", dark);
    getCurrentWindow().setTheme(dark ? "dark" : "light");
  });
  let introDone = $state(localStorage.getItem("nyx.intro") === "done");
  // The last version the dashboard showed: a different one after the intro means Nyx was updated.
  let version = $state<string | null>(null);
  let seen = $state(localStorage.getItem("nyx.version"));
  const markSeen = () => version && localStorage.setItem("nyx.version", (seen = version));
  const finishIntro = () => {
    localStorage.setItem("nyx.intro", "done");
    introDone = true;
    markSeen();
  };
  const refresh = async () => (snap = await api.snapshot());
  const home = $derived(snap?.platform === "macos" ? "menu bar" : snap?.platform === "windows" ? "system tray" : "tray");
  const empty = $derived(snap !== null && snap.apps.length === 0 && snap.sites.length === 0);

  onMount(() => {
    refresh();
    getVersion().then((v) => (version = v));
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

{#if snap && !introDone}
  <Intro hotkey={snap.hotkey} {home} ondone={finishIntro} />
{:else if snap && version && seen !== version}
  <Updated {version} from={seen} ondone={markSeen} />
{:else if snap && !(snap.screenPermission && snap.accessibilityPermission)}
  <Permissions {snap} />
{:else if snap}
  <div class="top" data-tauri-drag-region></div>
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
  {#if snap.notice}<p class="banner">{snap.notice}</p>{/if}
  {#if snap.loadFailed}
    <p class="banner failed">
      Nyx could not read your saved list — nothing is protected until you add an app again. The file is at {snap.storePath}.
    </p>
  {/if}

  <main>
    {#if empty}
      <div class="empty">
        <div class="owl big"></div>
        <p class="muted">Nothing protected</p>
        <button class="pill" onclick={(e) => show("app", e)}>+ Add app…</button>
        <button class="pill" onclick={(e) => show("site", e)}>+ Add website…</button>
      </div>
    {:else}
      <div class="label section">PROTECTED APPS</div>
      <button class="pill add" onclick={(e) => show("app", e)}>+ Add app…</button>
      {#each snap.apps as app (app.id)}
        <div class="row">
          {#if app.path}<img class="icon" src={api.icon(app.path)} alt="" />{:else}<span class="icon blank"></span>{/if}
          <span class="grow">{app.name}</span>
          <button class="remove" title="Stop protecting {app.name}" onclick={() => api.removeApp(app.id)}>Remove</button>
        </div>
      {/each}
      <div class="label section">PROTECTED SITES</div>
      <button class="pill add" onclick={(e) => show("site", e)}>+ Add website…</button>
      {#each snap.sites as host (host)}
        <div class="row site">
          <span class="grow">{host}</span>
          <button class="remove" title="Stop covering {host}" onclick={() => api.removeSite(host)}>Remove</button>
        </div>
      {/each}
    {/if}
  </main>

  {#if open}<div class="backdrop" role="presentation" onclick={close}></div>{/if}
  {#if open === "app" || open === "site"}
    <div class="anchor" style="left: {at.x}px; top: {at.y}px" use:fit>
      {#if open === "app"}<AppPicker exclude={snap.apps.map((a) => a.id)} onclose={close} />{:else}<SiteEntry onclose={close} />{/if}
    </div>
  {/if}
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
      <button class="gear" title="Settings" aria-label="Settings" onclick={() => (open = "settings")}>
        <svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor">
          {#each [0, 45, 90, 135, 180, 225, 270, 315] as turn}
            <rect x="10" y="1.5" width="4" height="5" rx="1" transform="rotate({turn} 12 12)" />
          {/each}
          <circle cx="12" cy="12" r="7" fill="none" stroke="currentColor" stroke-width="3" />
        </svg>
      </button>
    </div>
  </footer>
{/if}

<style>
  :global(body) { display: flex; flex-direction: column; }
  .top { height: 30px; flex: none; }
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
  .section { padding-top: 16px; }
  .section ~ .section { padding-top: 22px; }
  .row { display: flex; align-items: center; gap: 10px; height: 36px; padding: 0 16px; font-size: 13px; }
  .row.site { height: 32px; }
  .row:hover { background: var(--row); }
  .gear { margin-left: auto; flex: none; width: 26px; height: 24px; display: grid; place-items: center; border-radius: 6px; color: var(--muted); background: var(--control); border: 1px solid var(--border); }
  .banner { display: flex; align-items: center; gap: 10px; padding: 12px; font-size: 11px; color: var(--amber-text); background: color-mix(in srgb, var(--amber) 12%, transparent); }
  .banner.failed { color: var(--danger); background: color-mix(in srgb, var(--danger) 12%, transparent); line-height: 1.5; }
  .add { margin: 0 16px 8px; }
  .anchor { position: fixed; z-index: 10; }
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
