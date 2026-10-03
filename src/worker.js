export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "POST, OPTIONS",
          "Access-Control-Allow-Headers": "authorization, content-type",
        },
      })
    }

    if (request.method !== "POST") {
      return new Response(JSON.stringify({ error: "Method not allowed" }), {
        status: 405,
        headers: { "Content-Type": "application/json" },
      })
    }

    try {
      const authHeader = request.headers.get("Authorization")
      if (!authHeader?.startsWith("Bearer ")) {
        return new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
          headers: { "Content-Type": "application/json" },
        })
      }

      const contentType = request.headers.get("Content-Type")
      if (!contentType?.startsWith("application/octet-stream")) {
        return new Response(JSON.stringify({ error: "Invalid content type" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        })
      }

      const fileName = new URL(request.url).searchParams.get("fileName")
      const fileType = new URL(request.url).searchParams.get("fileType")

      if (!fileName || !fileType) {
        return new Response(JSON.stringify({ error: "Missing fileName or fileType" }), {
          status: 400,
          headers: { "Content-Type": "application/json" },
        })
      }

      const fileBuffer = await request.arrayBuffer()

      await env.R2_BUCKET.put(fileName, fileBuffer, {
        httpMetadata: {
          contentType: fileType,
        },
      })

      const publicUrl = `https://pub-6e84ce0976e04eda9d12b0c6c34019e3.r2.dev/${fileName}`

      return new Response(
        JSON.stringify({ publicUrl }),
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
        JSON.stringify({ error: "Failed to upload file", details: error.message }),
        {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }
      )
    }
  },
}
