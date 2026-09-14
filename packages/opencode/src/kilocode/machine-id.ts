import path from "node:path"
import { Path } from "@opencode-ai/core/global"

let cached: string | undefined

export async function getMachineId(): Promise<string | undefined> {
  if (cached) return cached
  const override = process.env.KILO_MACHINE_ID
  if (override) {
    cached = override
    return cached
  }
  const filepath = path.join(Path.data, "telemetry-id")
  const file = Bun.file(filepath)
  if (await file.exists()) {
    cached = await file.text()
    return cached
  }
  cached = crypto.randomUUID()
  await Bun.write(filepath, cached)
  return cached
}
