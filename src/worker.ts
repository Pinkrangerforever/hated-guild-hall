import { createPresignedPost } from '@aws-sdk/s3-presigned-post';
import { S3Client } from '@aws-sdk/client-s3';

const R2_PUBLIC_URL = "https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev"

export default {
  async fetch(request: Request, env: CloudflareWorkerEnv): Promise<Response> {
    // Handle CORS preflight
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "authorization, content-type",
        },
      })
    }

    // Only allow POST
    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      })
    }

    try {
      // Verify Supabase JWT authentication
      const authHeader = request.headers.get("Authorization")
      if (!authHeader?.startsWith("Bearer ")) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        })
      }

      const { fileName, contentType } = await request.json() as { fileName: string; contentType: string }

      if (!fileName || !contentType) {
        return new Response(JSON.stringify({ error: "Missing fileName or contentType" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        })
      }

      // Use R2 binding directly via signed URL
      const url = new URL(
        `https://${env.CLOUDFLARE_ACCOUNT_ID}.r2.cloudflarestorage.com/site-imgs/${fileName}`
      )

      // Generate presigned URL using R2
      const presignedUrl = await env.R2_BUCKET.createPresignedUrl(fileName, 3600, {
        method: "put",
        headers: {
          "Content-Type": contentType,
        },
      })

      const publicUrl = `${R2_PUBLIC_URL}/${fileName}`

      return new Response(
        JSON.stringify({
          uploadUrl: presignedUrl,
          publicUrl,
        }),
        {
          headers: {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
          },
        }
      )
    } catch (error) {
      console.error("Error:", error)
      return new Response(
        JSON.stringify({ error: "Failed to generate presigned URL", details: (error as Error).message }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }
      )
    }
  },
} satisfies ExportedHandler<CloudflareWorkerEnv>

interface CloudflareWorkerEnv {
  R2_BUCKET: R2Bucket
  CLOUDFLARE_ACCOUNT_ID: string
}

interface R2Bucket {
  createPresignedUrl(
    key: string,
    expirationTtl: number,
    options?: { method?: string; headers?: Record<string, string> }
  ): Promise<string>
}
