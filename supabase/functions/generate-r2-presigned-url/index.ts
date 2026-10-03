import { serve } from "https://deno.land/std@0.208.0/http/server.ts"
import { S3Client, PutObjectCommand } from "https://deno.land/x/aws_sdk@v3.332.0/client-s3/mod.ts"
import { getSignedUrl } from "https://deno.land/x/aws_sdk@v3.332.0/s3-request-presigner/mod.ts"

const CLOUDFLARE_ACCOUNT_ID = Deno.env.get("CLOUDFLARE_ACCOUNT_ID") || ""
const R2_ACCESS_KEY = Deno.env.get("R2_ACCESS_KEY") || ""
const R2_SECRET_KEY = Deno.env.get("R2_SECRET_KEY") || ""
const R2_BUCKET = "site-imgs"
const R2_PUBLIC_URL = "https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev"

serve(async (req) => {
  // Only allow POST
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 })
  }

  try {
    // Verify user is authenticated
    const authHeader = req.headers.get("Authorization")
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      })
    }

    const { fileName, contentType } = await req.json()

    if (!fileName || !contentType) {
      return new Response(JSON.stringify({ error: "Missing fileName or contentType" }), {
        status: 400,
        headers: { "Content-Type": "application/json" },
      })
    }

    // Create S3 client configured for R2
    const client = new S3Client({
      region: "auto",
      credentials: {
        accessKeyId: R2_ACCESS_KEY,
        secretAccessKey: R2_SECRET_KEY,
      },
      endpoint: `https://${CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com`,
    })

    // Generate presigned PUT URL (valid for 1 hour)
    const command = new PutObjectCommand({
      Bucket: R2_BUCKET,
      Key: fileName,
      ContentType: contentType,
    })

    const uploadUrl = await getSignedUrl(client, command, { expiresIn: 3600 })
    const publicUrl = `${R2_PUBLIC_URL}/${fileName}`

    return new Response(
      JSON.stringify({
        uploadUrl,
        publicUrl,
      }),
      {
        headers: { "Content-Type": "application/json" },
      }
    )
  } catch (error) {
    console.error("Error:", error)
    return new Response(JSON.stringify({ error: "Failed to generate presigned URL" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    })
  }
})
