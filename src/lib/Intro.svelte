<script lang="ts">
  import { onMount } from "svelte";
  import * as api from "./api";

  let { hotkey, ondone }: { hotkey: string; ondone: () => void } = $props();
  const last = 2;
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
          <div class="screen">
            {@render win(false, "back")}
            {@render win(true, "front")}
          </div>
          <h1>Share your screen.<br />Not everything on it.</h1>
        {:else if page === 1}
          <div class="pair">
            <figure>{@render win(false)}<figcaption>You</figcaption></figure>
            <figure>{@render win(true)}<figcaption>Viewers</figcaption></figure>
          </div>
          <h1>You keep working.<br />They see a cover.</h1>
        {:else}
          <div class="keys">
            {#each hotkey.includes("+") ? hotkey.split("+") : [...hotkey] as key}
              <kbd>{key}</kbd>
            {/each}
          </div>
          {@render win(true, "toggle")}
          <h1>Press it in any app<br />to protect it.</h1>
        {/if}
      </div>
    {/key}
  </div>

  <nav>
    <button class="arrow" aria-label="Back" disabled={page === 0} onclick={() => go(page - 1)}>←</button>
    <div class="dots">
      {#each [0, 1, 2] as i}<button class:on={i === page} aria-label="Page {i + 1}" onclick={() => go(i)}></button>{/each}
    </div>
    {#if page === last}
      <button class="pill ready" onclick={ondone}>I'm Ready</button>
    {:else}
      <button class="arrow" aria-label="Next" onclick={() => go(page + 1)}>→</button>
    {/if}
  </nav>

  <button class="credit" onclick={() => api.openLink("unravel")}>
    <span class="muted">Made by Team</span><img src="/unravel.png" alt="Unravel" />
  </button>
</div>

<style>
  .intro { flex: 1; display: flex; flex-direction: column; align-items: center; padding: 30px 24px 18px; }
  .stage { flex: 1; width: 100%; display: grid; place-items: center; }
  .page { display: flex; flex-direction: column; align-items: center; gap: 28px; animation: in 0.3s ease-out; }
  @keyframes in { from { opacity: 0; transform: translateX(12px); } }
  h1 { font-size: 15px; font-weight: 500; text-align: center; line-height: 1.6; }

  .win { width: 150px; border-radius: 7px; border: 1px solid var(--border); background: var(--panel); overflow: hidden; }
  .bar { display: flex; gap: 4px; padding: 6px 7px; border-bottom: 1px solid var(--hairline); }
  .bar i { width: 6px; height: 6px; border-radius: 50%; background: var(--control); }
  .body { position: relative; height: 84px; padding: 12px 10px; display: flex; flex-direction: column; gap: 8px; }
  .body span { height: 6px; border-radius: 3px; background: var(--control); }
  .cover { position: absolute; inset: 0; background: #000; display: grid; place-items: center; opacity: 0; transition: opacity 0.3s; }
  .cover .owl { width: 22px; height: 26px; color: #fff; opacity: 0.5; }
  .covered .cover { opacity: 1; }

  .screen { position: relative; width: 250px; height: 150px; border-radius: 10px; border: 1px solid var(--border); background: var(--control); }
  .screen .win { position: absolute; }
  .back { left: 16px; top: 16px; }
  .front { right: 16px; bottom: 16px; box-shadow: 0 0 0 2px var(--amber); }

  .pair { display: flex; gap: 14px; }
  .pair .win { width: 130px; }
  figure { display: flex; flex-direction: column; align-items: center; gap: 8px; }
  figcaption { font-size: 11px; color: var(--muted); }

  .keys { display: flex; gap: 6px; }
  kbd { font: inherit; font-size: 14px; font-weight: 500; min-width: 32px; padding: 6px 8px; text-align: center; border-radius: 6px; background: var(--control); border: 1px solid var(--border); border-bottom-width: 3px; }
  .toggle .cover { animation: toggle 3s infinite; }
  @keyframes toggle { 0%, 40% { opacity: 0; } 50%, 90% { opacity: 1; } 100% { opacity: 0; } }

  nav { width: 100%; display: flex; align-items: center; justify-content: space-between; height: 32px; }
  .arrow { width: 32px; height: 28px; font-size: 14px; border-radius: 6px; background: var(--control); border: 1px solid var(--border); }
  .arrow:disabled { opacity: 0.3; }
  .dots { display: flex; gap: 6px; }
  .dots button { width: 6px; height: 6px; border-radius: 50%; background: var(--border); }
  .dots .on { background: var(--text); }
  .ready { height: 28px; background: var(--amber); color: var(--ink-on-amber); border-color: transparent; }
  .credit { margin-top: 16px; display: flex; align-items: center; gap: 6px; font-size: 10px; }
  .credit img { height: 9px; }
</style>
