"use strict";

const { test, expect } = require("@playwright/test");
const AxeBuilder = require("@axe-core/playwright").default;
const { spawn, spawnSync } = require("node:child_process");
const fs = require("node:fs");
const net = require("node:net");
const os = require("node:os");
const path = require("node:path");

const projectRoot = path.resolve(__dirname, "..", "..");
const powershell = `${process.env.SystemRoot || "C:\\Windows"}\\System32\\WindowsPowerShell\\v1.0\\powershell.exe`;
let fixtureRoot;
let repository;
let remote;
let port;
let baseUrl;
let server;

function run(executable, args, options = {}) {
  const result = spawnSync(executable, args, { encoding: "utf8", ...options });
  if (result.status !== 0) throw new Error(`${executable} ${args.join(" ")}\n${result.stdout}\n${result.stderr}`);
  return result.stdout.trim();
}

function git(cwd, ...args) {
  return run("git.exe", ["-C", cwd, ...args]);
}

function freePort() {
  return new Promise((resolve, reject) => {
    const listener = net.createServer();
    listener.once("error", reject);
    listener.listen(0, "127.0.0.1", () => {
      const selected = listener.address().port;
      listener.close(() => resolve(selected));
    });
  });
}

async function waitForServer(url) {
  const deadline = Date.now() + 20_000;
  while (Date.now() < deadline) {
    if (server.exitCode !== null) throw new Error(`Branchline exited before startup with code ${server.exitCode}.`);
    try {
      const response = await fetch(`${url}/api/about`);
      if (response.ok) return;
    } catch { /* startup is still in progress */ }
    await new Promise((resolve) => setTimeout(resolve, 150));
  }
  throw new Error("Branchline did not become ready in time.");
}

test.beforeAll(async () => {
  fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "Branchline-playwright-"));
  repository = path.join(fixtureRoot, "working repository");
  remote = path.join(fixtureRoot, "remote repository.git");
  fs.mkdirSync(repository);
  fs.mkdirSync(remote);
  run("git.exe", ["init", "--bare", remote]);
  run("git.exe", ["init", "-b", "main", repository]);
  git(repository, "config", "user.name", "Branchline Browser Test");
  git(repository, "config", "user.email", "browser@example.invalid");
  fs.writeFileSync(path.join(repository, "README.md"), "# Browser fixture\n\nSafe disposable content.\n", "utf8");
  git(repository, "add", "README.md");
  git(repository, "commit", "-m", "Initial browser fixture");
  git(repository, "remote", "add", "origin", remote);
  git(repository, "push", "-u", "origin", "main");
  port = await freePort();
  baseUrl = `http://127.0.0.1:${port}`;
  server = spawn(powershell, [
    "-NoLogo", "-NoProfile", "-ExecutionPolicy", "RemoteSigned",
    "-File", path.join(projectRoot, "start.ps1"),
    "-RepoPath", repository, "-Port", String(port), "-NoBrowser", "-AllowLocalTestRemote"
  ], {
    cwd: projectRoot,
    env: {
      ...process.env,
      LOCALAPPDATA: path.join(fixtureRoot, "local-state"),
      BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION: "1"
    },
    windowsHide: true,
    stdio: ["ignore", "pipe", "pipe"]
  });
  await waitForServer(baseUrl);
});

test.afterAll(async () => {
  if (port) {
    spawnSync(powershell, ["-NoLogo", "-NoProfile", "-ExecutionPolicy", "RemoteSigned", "-File", path.join(projectRoot, "stop.ps1"), "-Port", String(port)], {
      cwd: projectRoot,
      encoding: "utf8",
      env: {
        ...process.env,
        LOCALAPPDATA: path.join(fixtureRoot, "local-state"),
        BRANCHLINE_SKIP_LEGACY_RUNTIME_MIGRATION: "1"
      },
      timeout: 15_000,
      windowsHide: true
    });
  }
  if (server && server.exitCode === null) server.kill();
  if (fixtureRoot && fs.existsSync(fixtureRoot)) fs.rmSync(fixtureRoot, { recursive: true, force: true });
});

test.beforeEach(async ({ page }) => {
  await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
  await expect(page.locator("#healthText")).toContainText("Repository ready");
});

test("loads a disposable repository and previews a file", async ({ page }) => {
  await expect(page.locator("#repoName")).toHaveText("working repository");
  await expect(page.locator("#branchName")).toHaveText("main");
  await page.locator("#filesList .file-select", { hasText: "README.md" }).click();
  await expect(page.locator("#filePreviewDialog")).toBeVisible();
  await expect(page.locator("#filePreviewTitle")).toHaveText("README.md");
  await expect(page.locator("#filePreviewContent")).toContainText("Browser fixture");
  await page.locator("#previewDiffTab").click();
  await expect(page.locator("#filePreviewContent")).toContainText("No staged difference");
  await page.locator("#closeFilePreviewButton").click();
});

test("supports keyboard tabs and explains a blocked publish", async ({ page }) => {
  const localTab = page.locator("#localViewTab");
  const githubTab = page.locator("#githubViewTab");
  await localTab.focus();
  await page.keyboard.press("ArrowRight");
  await expect(githubTab).toHaveAttribute("aria-selected", "true");
  await page.keyboard.press("Home");
  await expect(localTab).toHaveAttribute("aria-selected", "true");
  const publish = page.locator("#pushButton");
  await expect(publish).not.toHaveAttribute("disabled", "");
  await publish.focus();
  await page.keyboard.press("Enter");
  await expect(page.locator("#syncGuideDialog")).toBeVisible();
  await expect(page.locator("#syncGuideTitle")).toContainText(/publish/i);
  await page.keyboard.press("Escape");
  await expect(page.locator("#syncGuideDialog")).not.toBeVisible();
});

test("remains usable at 200 percent zoom and has no serious axe violations", async ({ page }) => {
  await page.evaluate(() => { document.body.style.zoom = "2"; });
  await expect(page.locator("#repositoryTabs")).toBeVisible();
  await expect(page.locator("#refreshLocalButton")).toBeVisible();
  const results = await new AxeBuilder({ page }).withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  const serious = results.violations.filter((violation) => ["serious", "critical"].includes(violation.impact));
  expect(serious, JSON.stringify(serious, null, 2)).toEqual([]);
});

test("uses cached tabs and has no permanent GPU-heavy effects", async ({ page }) => {
  await page.locator("#githubViewTab").click();
  await expect(page.locator("#githubFilesList .file-select").first()).toBeVisible();
  await page.locator("#localViewTab").click();
  await expect(page.locator("#filesList .file-select").first()).toBeVisible();
  const listRequests = [];
  page.on("request", (request) => {
    if (request.url().endsWith("/api/action") && request.postData()?.includes('"action":"listFiles"')) listRequests.push(request.url());
  });
  const elapsed = await page.evaluate(async () => {
    const start = performance.now();
    document.getElementById("githubViewTab").click();
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
    document.getElementById("localViewTab").click();
    await new Promise((resolve) => requestAnimationFrame(() => resolve()));
    return performance.now() - start;
  });
  expect(listRequests).toHaveLength(0);
  expect(elapsed).toBeLessThan(100);
  const effects = await page.evaluate(() => ({
    topbarBackdrop: getComputedStyle(document.querySelector(".topbar")).backdropFilter,
    bridgeAnimation: getComputedStyle(document.querySelector(".connection-bridge .bridge-link-icon")).animationName
  }));
  expect(["", "none"]).toContain(effects.topbarBackdrop);
  expect(effects.bridgeAnimation).toBe("none");
});

test("presents the standard team branch flow before advanced local merging", async ({ page }) => {
  await expect(page.locator(".team-branch-route")).toContainText("Update main");
  await expect(page.locator(".team-branch-route")).toContainText("pull request");
  await expect(page.locator(".new-branch-heading")).toContainText("Start a new team task");
  await expect(page.locator(".merge-workflow")).toContainText("Advanced: merge branches locally");
  const verticalOrder = await page.locator(".branch-panel").evaluate((panel) => {
    const top = (selector) => panel.querySelector(selector).getBoundingClientRect().top;
    return {
      create: top(".new-branch-heading"),
      switch: top(".switch-workflow"),
      remote: top(".remote-branch-workflow"),
      merge: top(".merge-workflow")
    };
  });
  expect(verticalOrder.create).toBeLessThan(verticalOrder.switch);
  expect(verticalOrder.switch).toBeLessThan(verticalOrder.remote);
  expect(verticalOrder.remote).toBeLessThan(verticalOrder.merge);
});

test("colors Git additions and removals and keeps journal entries separate", async ({ page }) => {
  const readme = path.join(repository, "README.md");
  const original = fs.readFileSync(readme, "utf8");
  fs.writeFileSync(readme, original.replace("Safe disposable content.", "Updated disposable content."), "utf8");
  try {
    await page.locator("#refreshLocalButton").click();
    const row = page.locator("#filesList .file-row", { hasText: "README.md" });
    const diff = row.getByRole("button", { name: "Diff", exact: true });
    await diff.click();
    await expect(page.locator("#outputDetail .diff-removed")).toContainText("-Safe disposable content.");
    await expect(page.locator("#outputDetail .diff-added")).toContainText("+Updated disposable content.");
    for (let index = 0; index < 9; index += 1) await diff.click();
    const entriesDoNotOverlap = await page.locator("#activityList").evaluate((list) => {
      const boxes = Array.from(list.querySelectorAll(".activity-entry"), (entry) => entry.getBoundingClientRect());
      return boxes.every((box, index) => index === 0 || box.top >= boxes[index - 1].bottom);
    });
    expect(entriesDoNotOverlap).toBe(true);
  } finally {
    fs.writeFileSync(readme, original, "utf8");
  }
});

test("separates structured command steps in selected output", async ({ page }) => {
  await page.evaluate(() => {
    window.appendActivity({
      ok: true,
      command: "publish integrated branch",
      output: "Both histories were integrated and published.",
      phase: "complete",
      steps: [
        { name: "Check GitHub", status: "completed", command: "git fetch origin", output: "Remote snapshot refreshed." },
        { name: "Publish branch", status: "completed", command: "git push origin main", output: "Published 2 commits." }
      ]
    });
  });
  await expect(page.locator("#outputDetail .output-overview")).toContainText("Completed");
  await expect(page.locator("#outputDetail .output-command")).toContainText("publish integrated branch");
  await expect(page.locator("#outputDetail .output-step")).toHaveCount(2);
  await expect(page.locator("#outputDetail .output-result")).toContainText("Both histories were integrated and published.");
});

test("staging refreshes local state without rebuilding the full summary", async ({ page }) => {
  const file = path.join(repository, "fast-stage.txt");
  fs.writeFileSync(file, "local performance path\n", "utf8");
  try {
    await page.locator("#refreshLocalButton").click();
    const row = page.locator("#filesList .file-row", { hasText: "fast-stage.txt" });
    await expect(row).toBeVisible();
    let summaryRequests = 0;
    page.on("request", (request) => { if (request.url().endsWith("/api/summary")) summaryRequests += 1; });
    await row.getByRole("button", { name: "Stage", exact: true }).click();
    await expect(page.locator("#filesList .file-row", { hasText: "fast-stage.txt" })).toContainText("Ready to commit");
    expect(summaryRequests).toBe(0);
  } finally {
    spawnSync("git.exe", ["-C", repository, "reset", "--", "fast-stage.txt"], { encoding: "utf8" });
    if (fs.existsSync(file)) fs.rmSync(file, { force: true });
  }
});

test("guides a clean stale main through GitHub before creating a team branch", async ({ page }) => {
  const updater = path.join(fixtureRoot, "teammate update");
  run("git.exe", ["clone", "--branch", "main", remote, updater]);
  git(updater, "config", "user.name", "Branchline Teammate");
  git(updater, "config", "user.email", "teammate@example.invalid");
  fs.writeFileSync(path.join(updater, "team-update.txt"), "incoming team work\n", "utf8");
  git(updater, "add", "team-update.txt");
  git(updater, "commit", "-m", "Add teammate update");
  git(updater, "push", "origin", "main");
  fs.rmSync(updater, { recursive: true, force: true });

  await page.locator("#githubViewTab").click();
  await page.locator("#fetchButton").click();
  await expect(page.locator("#behindCount")).toHaveText("1");
  await page.locator("#newBranchInput").fill("feature/from-fresh-main");
  await page.locator("#createBranchButton").click();
  await expect(page.locator("#syncGuideDialog")).toBeVisible();
  await expect(page.locator("#currentBranchLabel")).toHaveText("main");
  await expect(page.locator("#newBranchInput")).toHaveValue("feature/from-fresh-main");
  await expect(page.locator("#toastRegion")).toContainText("Update main from GitHub");
});
