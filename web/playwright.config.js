import {defineConfig} from "@playwright/test";
export default defineConfig({
  testDir: "./tests", testMatch: "*.spec.js", timeout: 300000, workers: 1,
  reporter: "line", outputDir: "../.artifacts/browser",
  use: {browserName: "chromium", viewport: {width: 1152, height: 760},
    launchOptions: {args: ["--use-gl=angle", "--use-angle=swiftshader", "--enable-unsafe-swiftshader", "--disable-dev-shm-usage"]}},
  webServer: {command: "python3 tools/serve_web.py", url: "http://127.0.0.1:8176", reuseExistingServer: false, timeout: 10000, cwd: ".."},
});
