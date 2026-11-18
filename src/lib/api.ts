import { convertFileSrc, invoke } from "@tauri-apps/api/core";

export type State = "idle" | "active" | "blind";
export type Row = { id: string; name: string; path: string };
export type Snapshot = {
  apps: Row[];
  sites: string[];
  enabled: boolean;
  state: State;
  screenPermission: boolean;
  accessibilityPermission: boolean;
  loadFailed: boolean;
  storePath: string;
  hotkey: string;
  platform: "macos" | "windows" | "linux";
  notice: string | null;
};

export const icon = (path: string) => (path ? convertFileSrc(path, "icon") : null);
export const snapshot = () => invoke<Snapshot | null>("snapshot");
export const pickable = (exclude: string[]) => invoke<Row[]>("pickable", { exclude });
export const addApp = (path: string) => invoke("add_app", { path });
export const removeApp = (id: string) => invoke("remove_app", { id });
export const addSite = (raw: string) => invoke<string | null>("add_site", { raw });
export const normalizeSite = (raw: string) => invoke<string | null>("normalize_site", { raw });
export const removeSite = (host: string) => invoke("remove_site", { host });
export const openLink = (target: "screen" | "accessibility" | "unravel") => invoke("open_link", { target });
