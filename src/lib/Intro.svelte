<script lang="ts">
  import { onMount } from "svelte";

  let { hotkey, home, ondone }: { hotkey: string; home: string; ondone: () => void } = $props();
  const last = 3;
  let page = $state(0);
  const go = (to: number) => (page = Math.max(0, Math.min(last, to)));

  onMount(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "ArrowRight") page === last ? ondone() : go(page + 1);
      if (e.key === "ArrowLeft") go(page - 1);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  });
</script>

{#snippet win(covered: boolean, cls = "")}
  <div class="win {cls}" class:covered>
    <div class="bar"><i></i><i></i><i></i></div>
    <div class="body">
      <span style="width: 70%"></span><span style="width: 90%"></span><span style="width: 55%"></span>
      <div class="cover"><div class="owl"></div></div>
    </div>
  </div>
{/snippet}

<div class="intro" data-tauri-drag-region>
  <div class="stage">
    {#key page}
      <div class="page">
        {#if page === 0}
          <div class="greeting"><span class="muted">Greetings from Team</span><img src="/unravel.png" alt="Unravel" /></div>
          <img class="logo" src="/logo.png" alt="" />
          <h1>Welcome to Nyx</h1>
        {:else if page === 1}
          <div class="card">
            <div class="item"><i></i><span style="width: 60px"></span></div>
            <div class="item"><i></i><span style="width: 84px"></span></div>
            <div class="pill">+ Add app…</div>
            <div class="item site"><span style="width: 96px"></span></div>
            <div class="pill">+ Add website…</div>
          </div>
          <div class="keys">
            <span class="muted">or press</span>
            {#each hotkey.includes("+") ? hotkey.split("+") : [...hotkey] as key}<kbd>{key}</kbd>{/each}
            <span class="muted">in any app</span>
          </div>
          <h1>Add the apps and sites<br />you want hidden.</h1>
        {:else if page === 2}
          <div class="sharing"><i></i>Sharing</div>
          <div class="pair">
            <figure>{@render win(false)}<figcaption>You</figcaption></figure>
            <figure>{@render win(true)}<figcaption>Viewers</figcaption></figure>
          </div>
          <h1>Nyx wakes up only when you start sharing your screen.</h1>
        {:else}
          <div class="menubar">
            {#each [0, 1, 2] as _}<i></i>{/each}
            <span class="here"><span class="tray"></span></span>
          </div>
          <h1>Nyx lives in your {home}.<br />Click the owl to come back here.</h1>
        {/if}
      </div>
    {/key}
  </div>

  <nav>
    <button class="arrow" aria-label="Back" disabled={page === 0} onclick={() => go(page - 1)}>←</button>
    <div class="dots">
      {#each { length: last + 1 }, i}<button class:on={i === page} aria-label="Page {i + 1}" onclick={() => go(i)}></button>{/each}
    </div>
    {#if page === last}
      <button class="pill ready" onclick={ondone}>I'm Ready</button>
    {:else}
      <button class="arrow" aria-label="Next" onclick={() => go(page + 1)}>→</button>
    {/if}
  </nav>
</div>

<style>
  .intro { flex: 1; display: flex; flex-direction: column; align-items: center; padding: 30px 24px 18px; }
  .stage { flex: 1; width: 100%; display: grid; place-items: center; }
  .page { display: flex; flex-direction: column; align-items: center; gap: 28px; animation: in 0.3s ease-out; }
  @keyframes in { from { opacity: 0; transform: translateX(12px); } }
  h1 { font-size: 15px; font-weight: 500; text-align: center; line-height: 1.6; text-wrap: balance; }

  .win { width: 150px; border-radius: 7px; border: 1px solid var(--border); background: var(--panel); overflow: hidden; }
  .bar { display: flex; gap: 4px; padding: 6px 7px; border-bottom: 1px solid var(--hairline); }
  .bar i { width: 6px; height: 6px; border-radius: 50%; background: var(--control); }
  .body { position: relative; height: 84px; padding: 12px 10px; display: flex; flex-direction: column; gap: 8px; }
  .body span { height: 6px; border-radius: 3px; background: var(--control); }
  .cover { position: absolute; inset: 0; background: #000; display: grid; place-items: center; opacity: 0; transition: opacity 0.3s; }
  .cover .owl { width: 22px; height: 26px; color: #fff; opacity: 0.5; }
  .covered .cover { opacity: 1; }

  .greeting { display: flex; align-items: baseline; gap: 0.5em; font-size: 15px; }
  .greeting img { height: 1.05em; position: relative; top: 0.08em; }
  .logo { height: 96px; }

  .card { width: 220px; padding: 12px; display: flex; flex-direction: column; gap: 8px; border-radius: 8px; border: 1px solid var(--border); background: var(--panel); }
  .item { display: flex; align-items: center; gap: 8px; height: 16px; }
  .item i { width: 14px; height: 14px; border-radius: 4px; background: var(--control); }
  .item span { height: 6px; border-radius: 3px; background: var(--control); }
  .item.site { margin-top: 6px; }
  .card .pill { align-self: flex-start; font-size: 10px; }

  .sharing { display: flex; align-items: center; gap: 6px; font-size: 11px; font-weight: 500; padding: 4px 10px; border-radius: 12px; background: var(--control); border: 1px solid var(--border); }
  .sharing i { width: 7px; height: 7px; border-radius: 50%; background: #e5534b; animation: pulse 1.6s infinite; }
  @keyframes pulse { 50% { opacity: 0.3; } }

  .pair { display: flex; gap: 14px; }
  .pair .win { width: 130px; }
  figure { display: flex; flex-direction: column; align-items: center; gap: 8px; }
  figcaption { font-size: 11px; color: var(--muted); }

  .keys { display: flex; align-items: center; gap: 5px; font-size: 11px; }
  kbd { font: inherit; font-size: 12px; font-weight: 500; min-width: 24px; padding: 3px 6px; text-align: center; border-radius: 5px; background: var(--control); border: 1px solid var(--border); border-bottom-width: 2px; }

  .menubar { width: 220px; height: 26px; padding: 0 10px; display: flex; align-items: center; justify-content: flex-end; gap: 12px; border-radius: 6px; background: var(--panel); border: 1px solid var(--border); }
  .menubar i { width: 12px; height: 12px; border-radius: 3px; background: var(--control); }
  .here { width: 22px; height: 22px; display: grid; place-items: center; border-radius: 50%; box-shadow: 0 0 0 2px var(--amber); }
  .tray { width: 16px; height: 16px; background: currentColor; mask: url("/tray-owl.png") center / contain no-repeat; }

  nav { width: 100%; display: flex; align-items: center; justify-content: space-between; height: 32px; }
  .arrow { width: 32px; height: 28px; font-size: 14px; border-radius: 6px; background: var(--control); border: 1px solid var(--border); }
  .arrow:disabled { opacity: 0.3; }
  .dots { display: flex; gap: 6px; }
  .dots button { width: 6px; height: 6px; border-radius: 50%; background: var(--border); }
  .dots .on { background: var(--text); }
  .ready { height: 28px; background: var(--amber); color: var(--ink-on-amber); border-color: transparent; }
</style>
