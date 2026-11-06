<script lang="ts">
  let { dark = $bindable() }: { dark: boolean } = $props();
</script>

<div class="panel settings">
  <div class="label head">SETTINGS</div>
  <div class="line">
    <span>Appearance</span>
    <!-- Built rather than native, which would bring the system accent into a monochrome window. -->
    <div class="segments">
      <button class:on={!dark} onclick={() => (dark = false)}>Light</button>
      <button class:on={dark} onclick={() => (dark = true)}>Dark</button>
    </div>
  </div>
  <div class="rule"></div>
  <p class="muted">
    macOS shows a screen-sharing indicator while Nyx mirrors a window, which only happens during a share. The
    mirror never leaves your Mac.
  </p>
</div>

<style>
  .settings { width: 310px; top: 34px; right: 12px; }
  .head { font-size: 10px; padding: 14px 14px 12px; }
  .line { display: flex; justify-content: space-between; align-items: center; padding: 0 14px 14px; }
  .segments { display: flex; border: 1px solid var(--border); border-radius: 6px; overflow: hidden; background: var(--control); }
  .segments button { width: 62px; height: 24px; font-size: 11px; font-weight: 500; color: var(--muted); }
  .segments button + button { border-left: 1px solid var(--border); }
  .segments .on { color: var(--text); background: var(--selection); }
  .rule { height: 1px; background: var(--hairline); }
  p { padding: 14px; font-size: 11px; line-height: 1.5; }
</style>
