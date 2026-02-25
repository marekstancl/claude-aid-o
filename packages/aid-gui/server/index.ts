import express from "express";
import { createServer as createViteServer } from "vite";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/** Project root for packages/aid-gui (one level up from server/) */
const PROJECT_ROOT = path.join(__dirname, "..");

export function createApp() {
  const app = express();

  app.use(express.json());

  // TODO: Mount API routes here (EPIC E-005-1_4, Step 3+)
  // Example: app.use("/api", apiRouter);

  return app;
}

async function startServer() {
  const app = createApp();
  const PORT = Number(process.env.PORT) || 3000;

  // Vite middleware for development
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      root: PROJECT_ROOT,
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(PROJECT_ROOT, "dist");
    app.use(express.static(distPath));
    app.get("*", (_req, res) => {
      res.sendFile(path.join(distPath, "index.html"));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`AID Dashboard server running on http://localhost:${PORT}`);
  });
}

startServer();
