import type { Env } from "../env";
import { kvGetCached, kvPutConfig } from "./kvCache";

const KV_KEY = "service_killed";

export async function isServiceKilled(env: Env): Promise<boolean> {
  const value = await kvGetCached(env, KV_KEY);
  return value === "1";
}

export async function setServiceKilled(env: Env, killed: boolean): Promise<void> {
  await kvPutConfig(env, KV_KEY, killed ? "1" : "0");
}
