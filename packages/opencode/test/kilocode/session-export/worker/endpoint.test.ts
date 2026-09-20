import { describe, expect, test } from "bun:test"
import { resolveEndpoint } from "@/kilocode/session-export/worker/endpoint"

describe("session export endpoint", () => {
  test("returns undefined when no endpoint is configured", () => {
    expect(resolveEndpoint({})).toBeUndefined()
  })

  test("uses an explicit https endpoint", () => {
    expect(resolveEndpoint({ endpoint: "https://collector.local/batch" })).toBe("https://collector.local/batch")
  })

  test("prefers the explicit endpoint over the env endpoint", () => {
    expect(resolveEndpoint({ endpoint: "https://a.local/batch", env: "https://b.local/batch" })).toBe(
      "https://a.local/batch",
    )
  })

  test("falls back to the env endpoint", () => {
    expect(resolveEndpoint({ env: "https://collector.local/batch" })).toBe("https://collector.local/batch")
  })

  test("allows plaintext loopback endpoints for local ingest", () => {
    expect(resolveEndpoint({ endpoint: "http://127.0.0.1:8787/batch" })).toBe("http://127.0.0.1:8787/batch")
    expect(resolveEndpoint({ endpoint: "http://localhost:8787/batch" })).toBe("http://localhost:8787/batch")
  })

  test("rejects plaintext non-loopback endpoints", () => {
    expect(resolveEndpoint({ endpoint: "http://example.test/ingest" })).toBeUndefined()
  })

  test("rejects invalid URLs", () => {
    expect(resolveEndpoint({ endpoint: "not a url" })).toBeUndefined()
  })
})
