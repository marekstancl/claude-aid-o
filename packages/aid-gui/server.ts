import express from "express";
import { createServer as createViteServer } from "vite";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

async function startServer() {
  const app = express();
  const PORT = 3000;

  // Mock API for AID Dashboard
  app.get("/api/health", (req, res) => {
    res.json({ status: "ok", version: "1.0.0" });
  });

  app.get("/api/projects", (req, res) => {
    res.json([
      { id: "p1", name: "AID Core", health: 92 },
      { id: "p2", name: "Project Phoenix", health: 78 }
    ]);
  });

  app.get("/api/pipeline/status", (req, res) => {
    res.json({
      state: "EXECUTING",
      progress: 0.65,
      activeStep: "step_backend_api",
      epic: "E-005-1_1",
      duration: "1h 23m"
    });
  });

  app.get("/api/pipeline/steps", (req, res) => {
    res.json([
      { id: "step_1", label: "Architecture Review", role: "architect", status: "completed", duration: "12m" },
      { id: "step_2", label: "Database Schema", role: "backend", status: "completed", duration: "8m" },
      { id: "step_3", label: "API Implementation", role: "backend", status: "active", duration: "45m" },
      { id: "step_4", label: "Frontend Components", role: "frontend", status: "pending" },
      { id: "step_5", label: "Security Audit", role: "security", status: "pending" },
    ]);
  });

  app.get("/api/activity", (req, res) => {
    res.json([
      { id: "1", time: "2m ago", state: "EXECUTING", step: "step_3", message: "Agent dispatched: backend. Objective: Implement REST API endpoints." },
      { id: "2", time: "15m ago", state: "EXECUTING", step: "step_2", message: "Step completed: Database Schema. 4 tables created." },
      { id: "3", time: "25m ago", state: "PLAN_READY", message: "Pipeline initialized for EPIC E-005-1_1." },
    ]);
  });

  // Vite middleware for development
  if (process.env.NODE_ENV !== "production") {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: "spa",
    });
    app.use(vite.middlewares);
  } else {
    app.use(express.static(path.join(__dirname, "dist")));
    app.get("*", (req, res) => {
      res.sendFile(path.join(__dirname, "dist", "index.html"));
    });
  }

  app.listen(PORT, "0.0.0.0", () => {
    console.log(`Server running on http://localhost:${PORT}`);
  });
}

startServer();
