export function resolveEndpoint(opts: { endpoint?: string; env?: string }): string | undefined {
  const endpoint = opts.endpoint ?? opts.env
  if (!endpoint) return undefined
  try {
    const url = new URL(endpoint)
    if (url.protocol === "https:") return endpoint
    if (url.protocol === "http:" && isLoopback(url.hostname)) return endpoint
    return undefined
  } catch {
    return undefined
  }
}

function isLoopback(host: string): boolean {
  const bare = host.replace(/^\[|\]$/g, "")
  return bare === "localhost" || bare === "127.0.0.1" || bare === "::1"
}
