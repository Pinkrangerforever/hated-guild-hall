import { serve } from "https://deno.land/std@0.208.0/http/server.ts"

const CLOUDFLARE_ACCOUNT_ID = Deno.env.get("CLOUDFLARE_ACCOUNT_ID") || ""
const R2_ACCESS_KEY = Deno.env.get("R2_ACCESS_KEY") || ""
const R2_SECRET_KEY = Deno.env.get("R2_SECRET_KEY") || ""
const R2_BUCKET = "site-imgs"
const R2_PUBLIC_URL = "https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev"

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}

async function generatePresignedUrl(fileName: string, contentType: string) {
  const bucket = R2_BUCKET
  const region = "auto"
  const service = "s3"
  const host = `${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`

  const now = new Date()
  const amzDate = now.toISOString().replace(/[:-]/g, "").split(".")[0] + "Z"
  const dateStamp = amzDate.slice(0, 8)

  const canonicalRequest = `PUT\n/${bucket}/${fileName}\n\nhost:${host}\nx-amz-content-sha256:UNSIGNED-PAYLOAD\nx-amz-date:${amzDate}\n\nhost;x-amz-content-sha256;x-amz-date\nUNSIGNED-PAYLOAD`

  const credentialScope = `${dateStamp}/${region}/${service}/aws4_request`

  const encoder = new TextEncoder()
  const canonicalRequestHash = await crypto.subtle.digest("SHA-256", encoder.encode(canonicalRequest))
  const canonicalRequestHashHex = Array.from(new Uint8Array(canonicalRequestHash)).map(b => b.toString(16).padStart(2, "0")).join("")

  const stringToSign = `AWS4-HMAC-SHA256\n${amzDate}\n${credentialScope}\n${canonicalRequestHashHex}`

  const kDate = await crypto.subtle.sign("HMAC", await deriveKey(`AWS4${R2_SECRET_KEY}`, "SHA-256"), encoder.encode(dateStamp))
  const kRegion = await crypto.subtle.sign("HMAC", kDate, encoder.encode(region))
  const kService = await crypto.subtle.sign("HMAC", kRegion, encoder.encode(service))
  const kSigning = await crypto.subtle.sign("HMAC", kService, encoder.encode("aws4_request"))

  const signature = Array.from(new Uint8Array(await crypto.subtle.sign("HMAC", kSigning, encoder.encode(stringToSign)))).map(b => b.toString(16).padStart(2, "0")).join("")

  const uploadUrl = `https://${host}/${bucket}/${fileName}?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=${R2_ACCESS_KEY}/${credentialScope}&X-Amz-Date=${amzDate}&X-Amz-Expires=3600&X-Amz-SignedHeaders=host%3Bx-amz-content-sha256%3Bx-amz-date&x-amz-content-sha256=UNSIGNED-PAYLOAD&X-Amz-Signature=${signature}`

  return {
    uploadUrl,
    publicUrl: `${R2_PUBLIC_URL}/${fileName}`
  }
}

async function deriveKey(key: string, algorithm: string) {
  const encoder = new TextEncoder()
  return await crypto.subtle.importKey("raw", encoder.encode(key), { name: "HMAC", hash: algorithm }, false, ["sign"])
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders })
  }

  // Only allow POST
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405, headers: corsHeaders })
  }

  try {
    // Verify user is authenticated
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const { fileName, contentType } = await req.json()

    if (!fileName || !contentType) {
      return new Response(JSON.stringify({ error: "Missing fileName or contentType" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      })
    }

    const { uploadUrl, publicUrl } = await generatePresignedUrl(fileName, contentType)

    return new Response(
      JSON.stringify({
        uploadUrl,
        publicUrl,
      }),
      {
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    )
  } catch (error) {
    console.error("Error:", error)
    return new Response(JSON.stringify({ error: "Failed to generate presigned URL", details: error.message }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    })
  }
})
