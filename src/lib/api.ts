import { invoke } from "@tauri-apps/api/core";

export type State = "idle" | "active" | "blind";
export type Row = { id: string; name: string; path: string; icon: string | null };
export type Snapshot = {
  apps: Row[];
  sites: string[];
  enabled: boolean;
  state: State;
  screenPermission: boolean;
  accessibilityPermission: boolean;
  loadFailed: boolean;
  hotkey: string;
};

export const snapshot = () => invoke<Snapshot | null>("snapshot");
export const pickable = (exclude: string[]) => invoke<Row[]>("pickable", { exclude });
export const addApp = (path: string) => invoke("add_app", { path });
export const removeApp = (id: string) => invoke("remove_app", { id });
export const addSite = (raw: string) => invoke<string | null>("add_site", { raw });
export const removeSite = (host: string) => invoke("remove_site", { host });
export const openLink = (target: "screen" | "accessibility" | "unravel") => invoke("open_link", { target });
