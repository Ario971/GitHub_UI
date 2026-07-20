"use strict";

if (!window.BranchlineState || !window.BranchlineRender || !window.BranchlineActions) {
  throw new Error("Branchline frontend modules did not load. Restart the application.");
}
const state = window.BranchlineState.create();

const byId = (id) => document.getElementById(id);

const elements = {
  workspace: byId("workspace"),
  healthDot: byId("healthDot"),
  healthText: byId("healthText"),
  headerBranch: byId("headerBranch"),
  themeButton: byId("themeButton"),
  refreshButton: byId("refreshButton"),
  repoPathInput: byId("repoPathInput"),
  useRepositoryButton: byId("useRepositoryButton"),
  initializeButton: byId("initializeButton"),
  cloneRepositoryButton: byId("cloneRepositoryButton"),
  detachRepositoryButton: byId("detachRepositoryButton"),
  restoreGitButton: byId("restoreGitButton"),
  folderGuidance: byId("folderGuidance"),
  connectionBridge: byId("connectionBridge"),
  connectionBridgeTitle: byId("connectionBridgeTitle"),
  connectionBridgeDetail: byId("connectionBridgeDetail"),
  localStatus: byId("localStatus"),
  localBadge: byId("localBadge"),
  remoteInput: byId("remoteInput"),
  connectRemoteButton: byId("connectRemoteButton"),
  remoteStatus: byId("remoteStatus"),
  remoteLink: byId("remoteLink"),
  syncMood: byId("syncMood"),
  syncHelp: byId("syncHelp"),
  syncContextPanel: byId("syncContextPanel"),
  syncContextLabel: byId("syncContextLabel"),
  syncContextHelp: byId("syncContextHelp"),
  syncSwitchViewButton: byId("syncSwitchViewButton"),
  repairUpstreamButton: byId("repairUpstreamButton"),
  publishNewBranchButton: byId("publishNewBranchButton"),
  fetchButton: byId("fetchButton"),
  fetchButtonNote: byId("fetchButtonNote"),
  pullButton: byId("pullButton"),
  pullButtonLabel: byId("pullButtonLabel"),
  pullButtonNote: byId("pullButtonNote"),
  pushButton: byId("pushButton"),
  pushButtonNote: byId("pushButtonNote"),
  githubLoginButton: byId("githubLoginButton"),
  resetLoginButton: byId("resetLoginButton"),
  repoName: byId("repoName"),
  repoPathView: byId("repoPathView"),
  branchName: byId("branchName"),
  aheadCount: byId("aheadCount"),
  behindCount: byId("behindCount"),
  lastUpdated: byId("lastUpdated"),
  remoteFetchedAt: byId("remoteFetchedAt"),
  repositoryStateError: byId("repositoryStateError"),
  syncBanner: byId("syncBanner"),
  syncTitle: byId("syncTitle"),
  syncDescription: byId("syncDescription"),
  fileSearchInput: byId("fileSearchInput"),
  fileCount: byId("fileCount"),
  fileNotice: byId("fileNotice"),
  filesList: byId("filesList"),
  localViewTab: byId("localViewTab"),
  githubViewTab: byId("githubViewTab"),
  localFilesView: byId("localFilesView"),
  githubFilesView: byId("githubFilesView"),
  githubFilesList: byId("githubFilesList"),
  githubSnapshotNotice: byId("githubSnapshotNotice"),
  localTabNote: byId("localTabNote"),
  githubTabNote: byId("githubTabNote"),
  refreshLocalButton: byId("refreshLocalButton"),
  openRepositoryFolderButton: byId("openRepositoryFolderButton"),
  localRefreshStatus: byId("localRefreshStatus"),
  localPreviousPageButton: byId("localPreviousPageButton"),
  localNextPageButton: byId("localNextPageButton"),
  localPageStatus: byId("localPageStatus"),
  githubPreviousPageButton: byId("githubPreviousPageButton"),
  githubNextPageButton: byId("githubNextPageButton"),
  githubPageStatus: byId("githubPageStatus"),
  composerPanel: byId("composerPanel"),
  changeCount: byId("changeCount"),
  identityPanel: byId("identityPanel"),
  identitySummary: byId("identitySummary"),
  identityHelp: byId("identityHelp"),
  identityNameInput: byId("identityNameInput"),
  identityEmailInput: byId("identityEmailInput"),
  saveIdentityButton: byId("saveIdentityButton"),
  commitPrerequisite: byId("commitPrerequisite"),
  commitPrerequisiteButton: byId("commitPrerequisiteButton"),
  commitGuidance: byId("commitGuidance"),
  commitMessageInput: byId("commitMessageInput"),
  selectedFileLabel: byId("selectedFileLabel"),
  stageAllButton: byId("stageAllButton"),
  commitButton: byId("commitButton"),
  commitPushButton: byId("commitPushButton"),
  currentBranchLabel: byId("currentBranchLabel"),
  branchSelect: byId("branchSelect"),
  branchSwitchHelp: byId("branchSwitchHelp"),
  switchBranchButton: byId("switchBranchButton"),
  mergeSourceSelect: byId("mergeSourceSelect"),
  mergeTargetSelect: byId("mergeTargetSelect"),
  mergeGuidance: byId("mergeGuidance"),
  mergeBranchButton: byId("mergeBranchButton"),
  newBranchInput: byId("newBranchInput"),
  createBranchButton: byId("createBranchButton"),
  deleteBranchButton: byId("deleteBranchButton"),
  remoteBranchSelect: byId("remoteBranchSelect"),
  checkoutRemoteBranchButton: byId("checkoutRemoteBranchButton"),
  branchSummary: byId("branchSummary"),
  pullRequestLink: byId("pullRequestLink"),
  commitSearchInput: byId("commitSearchInput"),
  commitSelect: byId("commitSelect"),
  commitsList: byId("commitsList"),
  showCommitButton: byId("showCommitButton"),
  restoreFromCommitButton: byId("restoreFromCommitButton"),
  revertCommitButton: byId("revertCommitButton"),
  operationNotice: byId("operationNotice"),
  abortOperationButton: byId("abortOperationButton"),
  resetCommitButton: byId("resetCommitButton"),
  syncGuideDialog: byId("syncGuideDialog"),
  syncGuideTitle: byId("syncGuideTitle"),
  syncGuideDescription: byId("syncGuideDescription"),
  syncGuideAhead: byId("syncGuideAhead"),
  syncGuideBehind: byId("syncGuideBehind"),
  syncGuideChanges: byId("syncGuideChanges"),
  syncGuideSteps: byId("syncGuideSteps"),
  syncGuidePrimaryButton: byId("syncGuidePrimaryButton"),
  clearActivityButton: byId("clearActivityButton"),
  activityList: byId("activityList"),
  outputDetail: byId("outputDetail"),
  toggleOutputButton: byId("toggleOutputButton"),
  copyOutputButton: byId("copyOutputButton"),
  busyCurtain: byId("busyCurtain"),
  busyText: byId("busyText"),
  filePreviewDialog: byId("filePreviewDialog"),
  filePreviewSide: byId("filePreviewSide"),
  filePreviewTitle: byId("filePreviewTitle"),
  filePreviewMeta: byId("filePreviewMeta"),
  filePreviewTabs: byId("filePreviewTabs"),
  previewContentTab: byId("previewContentTab"),
  previewDiffTab: byId("previewDiffTab"),
  filePreviewContent: byId("filePreviewContent"),
  closeFilePreviewButton: byId("closeFilePreviewButton"),
  liveStatus: byId("liveStatus"),
  toastRegion: byId("toastRegion")
};

const operationControls = Array.from(document.querySelectorAll("[data-operation]"));

function asArray(value) {
  if (!value) return [];
  return Array.isArray(value) ? value : [value];
}

function shortPath(path) {
  const parts = String(path || "").replace(/\\/g, "/").split("/");
  return parts[parts.length - 1] || path || "";
}

function firstLine(text) {
  return String(text || "").split(/\r?\n/).find((line) => line.trim()) || "No output.";
}

function diffLineClass(line) {
  if (/^(diff --git |index |--- |\+\+\+ )/.test(line)) return "diff-meta";
  if (/^@@/.test(line)) return "diff-hunk";
  if (/^\+(?!\+\+)/.test(line)) return "diff-added";
  if (/^-(?!---)/.test(line)) return "diff-removed";
  if (/^(STAGED DIFF|WORKING TREE DIFF|FETCHED GITHUB DIFF|LOCAL HEAD DIFF|FINAL RESULT|COMMAND DETAILS)$/i.test(line.trim())) return "diff-section";
  if (/^\\ No newline at end of file/.test(line)) return "diff-note";
  return line.length ? "diff-context" : "diff-empty";
}

function renderHighlightedDiff(element, value) {
  const text = String(value || "");
  element.replaceChildren();
  const lines = text.split(/\r?\n/);
  lines.forEach((line, index) => {
    const span = document.createElement("span");
    const className = diffLineClass(line);
    span.className = `diff-line ${className}`;
    span.textContent = line + (index < lines.length - 1 ? "\n" : "");
    element.append(span);
  });
}

function activityStatus(entry) {
  if (entry.partial) return { label: "Partly completed", icon: "~", className: "is-partial" };
  if (entry.ok) return { label: "Completed", icon: "✓", className: "is-complete" };
  return { label: "Needs attention", icon: "!", className: "is-failed" };
}

function createOutputCode(value, className = "") {
  const code = document.createElement("pre");
  code.className = `output-code${className ? ` ${className}` : ""}`;
  renderHighlightedDiff(code, value);
  return code;
}

function createOutputLabel(value) {
  const label = document.createElement("div");
  label.className = "output-block-label";
  label.textContent = value;
  return label;
}

function renderSelectedOutput(entry) {
  const detail = elements.outputDetail;
  detail.replaceChildren();
  const status = activityStatus(entry);

  const overview = document.createElement("div");
  overview.className = `output-overview ${status.className}`;
  const badge = document.createElement("span");
  badge.className = "output-status-badge";
  badge.textContent = `${status.icon} ${status.label}`;
  const time = document.createElement("time");
  time.textContent = entry.time;
  const title = document.createElement("strong");
  title.textContent = actionLabel(entry.command);
  const phase = document.createElement("small");
  phase.textContent = entry.phase ? `Phase: ${entry.phase}` : "Git operation record";
  overview.append(badge, time, title, phase);
  detail.append(overview);

  const commandBlock = document.createElement("section");
  commandBlock.className = "output-block output-command";
  const command = document.createElement("code");
  command.textContent = entry.command;
  commandBlock.append(createOutputLabel("Command"), command);
  detail.append(commandBlock);

  const copyParts = [`COMMAND\n${entry.command}`];
  if (entry.steps.length) {
    const timeline = document.createElement("section");
    timeline.className = "output-block output-timeline";
    timeline.append(createOutputLabel(`Steps · ${entry.steps.length}`));
    entry.steps.forEach((step, index) => {
      const item = document.createElement("article");
      const stepStatus = String(step.status || "completed").toLowerCase();
      item.className = `output-step is-${stepStatus}`;
      const heading = document.createElement("div");
      heading.className = "output-step-heading";
      const number = document.createElement("span");
      number.textContent = String(index + 1).padStart(2, "0");
      const name = document.createElement("strong");
      name.textContent = step.name || `Step ${index + 1}`;
      const stateLabel = document.createElement("small");
      stateLabel.textContent = step.status || "completed";
      heading.append(number, name, stateLabel);
      item.append(heading);
      if (step.command) {
        const stepCommand = document.createElement("code");
        stepCommand.className = "output-step-command";
        stepCommand.textContent = step.command;
        item.append(stepCommand);
      }
      if (step.output) item.append(createOutputCode(step.output, "output-step-result"));
      timeline.append(item);
      copyParts.push(`STEP ${index + 1}: ${step.name || "Git step"}\n${step.command || ""}\n${step.output || ""}`.trim());
    });
    detail.append(timeline);
  }

  const resultBlock = document.createElement("section");
  resultBlock.className = "output-block output-result";
  resultBlock.append(createOutputLabel(entry.steps.length ? "Final result" : "Result"), createOutputCode(entry.output));
  detail.append(resultBlock);
  copyParts.push(`RESULT\n${entry.output}`);
  detail.dataset.copyText = copyParts.join("\n\n");
}

function actionLabel(command) {
  const text = String(command || "Git action");
  const lower = text.toLowerCase();
  if (lower.includes("abort")) return "Aborted an interrupted operation";
  if (lower.includes("diff")) return "Reviewed a diff";
  if (lower.includes("unstage")) return "Removed from staging";
  if (lower.includes("stage") || lower.includes("git add")) return "Prepared changes";
  if (lower.includes("identity")) return "Saved the commit identity";
  if (lower.includes("bring github")) return "Brought GitHub into the folder";
  if (lower.includes("commit")) return "Created a commit";
  if (lower.includes("push") || lower.includes("publish")) return "Published changes";
  if (lower.includes("pull") || lower.includes("fast-forward")) return "Received changes";
  if (lower.includes("fetch")) return "Checked the remote";
  if (lower.includes("branch") || lower.includes("switch")) return "Updated branches";
  if (lower.includes("merge")) return "Merged a branch";
  if (lower.includes("reset")) return "Reset with a safety reference";
  if (lower.includes("clone")) return "Cloned GitHub into the folder";
  if (lower.includes("detach")) return "Detached local Git safely";
  if (lower.includes("restore")) return "Restored a file";
  if (lower.includes("revert")) return "Reverted a commit";
  if (lower.includes("origin") || lower.includes("repository")) return "Updated the connection";
  if (lower.includes("status")) return "Checked repository status";
  return text;
}

async function api(path, body) {
  if (!window.BranchlineApi) throw new Error("Branchline's local API module did not load. Restart the application.");
  return window.BranchlineApi.request(path, body);
}

function setBusy(busy, message = "Working…") {
  state.busy = busy;
  elements.workspace.setAttribute("aria-busy", String(busy));
  elements.busyText.textContent = message;
  elements.busyCurtain.classList.toggle("is-hidden", !busy);
  elements.healthDot.classList.toggle("is-busy", busy);
  if (busy) {
    elements.healthText.textContent = message;
    updateAvailability();
  } else if (state.summary) {
    elements.healthText.textContent = state.stale ? "Repository view needs refresh" : state.summary.stateOk === false ? "Repository needs attention" : "Repository ready";
    elements.healthDot.classList.toggle("is-good", !state.stale && state.summary.stateOk !== false);
    updateAvailability();
  } else {
    elements.healthText.textContent = "Waiting for a repository";
    updateAvailability();
  }
}

function toast(message, error = false) {
  const item = document.createElement("div");
  item.className = `toast${error ? " is-error" : ""}`;
  item.textContent = message;
  elements.toastRegion.append(item);
  window.setTimeout(() => item.remove(), 3800);
}

function appendActivity(result) {
  const entry = {
    id: `${Date.now()}-${Math.random().toString(16).slice(2)}`,
    ok: Boolean(result.ok),
    partial: Boolean(result.partial),
    command: result.command || "Git action",
    output: String(result.output || (result.ok ? "Completed successfully." : "The command failed.")),
    phase: String(result.phase || ""),
    steps: asArray(result.steps).map((step) => ({
      name: String(step?.name || "Git step"),
      status: String(step?.status || "completed"),
      command: String(step?.command || ""),
      output: String(step?.output || "")
    })),
    time: new Date().toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
  };
  state.activities.unshift(entry);
  state.activities = state.activities.slice(0, 24);
  state.selectedActivityId = entry.id;
  renderActivities();
}

function renderActivities() {
  elements.activityList.replaceChildren();
  if (state.activities.length === 0) {
    const empty = document.createElement("div");
    empty.className = "activity-empty";
    const icon = document.createElement("span");
    icon.setAttribute("aria-hidden", "true");
    icon.textContent = "☕";
    const strong = document.createElement("strong");
    strong.textContent = "Quiet for now";
    const copy = document.createElement("p");
    copy.textContent = "Your next Git action will appear here.";
    empty.append(icon, strong, copy);
    elements.activityList.append(empty);
    elements.outputDetail.replaceChildren();
    const outputEmpty = document.createElement("p");
    outputEmpty.className = "output-empty";
    outputEmpty.textContent = "Choose an activity entry to inspect its output.";
    elements.outputDetail.append(outputEmpty);
    elements.outputDetail.dataset.copyText = "";
    return;
  }

  state.activities.forEach((entry) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `activity-entry${entry.partial ? " is-partial" : entry.ok ? "" : " is-failed"}${entry.id === state.selectedActivityId ? " is-selected" : ""}`;
    button.addEventListener("click", () => {
      state.selectedActivityId = entry.id;
      renderActivities();
    });

    const entryStatus = activityStatus(entry);
    const meta = document.createElement("span");
    meta.className = "activity-meta";
    const status = document.createElement("span");
    status.className = `activity-status ${entryStatus.className}`;
    const statusIcon = document.createElement("i");
    statusIcon.setAttribute("aria-hidden", "true");
    statusIcon.textContent = entryStatus.icon;
    const statusText = document.createElement("span");
    statusText.textContent = entryStatus.label;
    status.append(statusIcon, statusText);
    const time = document.createElement("time");
    time.textContent = entry.time;
    meta.append(status, time);

    const title = document.createElement("strong");
    title.textContent = actionLabel(entry.command);
    const excerpt = document.createElement("p");
    excerpt.textContent = firstLine(entry.output);
    button.append(meta, title, excerpt);
    elements.activityList.append(button);
  });

  const selected = state.activities.find((entry) => entry.id === state.selectedActivityId) || state.activities[0];
  renderSelectedOutput(selected);
}

function setSelectedFile(path) {
  state.selectedFile = path || "";
  elements.selectedFileLabel.textContent = state.selectedFile || "None";
  renderFiles();
}

function fileStateLabel(file) {
  const labels = {
    staged: "ST",
    modified: "M",
    mixed: "MX",
    untracked: "+",
    deleted: "D",
    conflicted: "!",
    unchanged: "OK"
  };
  return labels[file.state] || file.status || "?";
}

function fileStateDescription(file) {
  const descriptions = {
    staged: "Ready to commit · staging is saved",
    mixed: "Ready to commit · newer edits are not staged",
    modified: "Changed · not staged",
    untracked: "New file · not staged",
    deleted: "Deleted · not staged",
    conflicted: "Conflict · resolve and stage",
    unchanged: "Unchanged"
  };
  return descriptions[file.state] || file.state || file.status || "Unknown state";
}

function availableFileActions(file) {
  const actions = [];
  if (file.tracked && !["unchanged", "untracked"].includes(file.state)) actions.push(["Diff", "diffFile", false]);
  if (["modified", "mixed", "untracked", "deleted", "conflicted"].includes(file.state)) actions.push(["Stage", "stageFile", false]);
  if (["staged", "mixed", "conflicted"].includes(file.state)) actions.push(["Unstage", "unstageFile", false]);
  if (file.tracked && file.state !== "unchanged") actions.push(["Restore", "restoreFile", true]);
  return actions;
}

function renderFilePagination(side) {
  const page = state.filePages[side];
  const previousButton = side === "github" ? elements.githubPreviousPageButton : elements.localPreviousPageButton;
  const nextButton = side === "github" ? elements.githubNextPageButton : elements.localNextPageButton;
  const status = side === "github" ? elements.githubPageStatus : elements.localPageStatus;
  const pages = Math.max(1, Math.ceil(Number(page.total || 0) / page.limit));
  const current = Math.min(pages, Math.floor(Number(page.offset || 0) / page.limit) + 1);
  status.textContent = `${current} / ${pages} · ${Number(page.total || 0)} files`;
  previousButton.disabled = state.busy || page.offset <= 0;
  nextButton.disabled = state.busy || page.nextOffset < 0;
}

async function loadFilePage(side, { offset = 0, announce = false } = {}) {
  if (!state.summary?.isRepo || state.busy) return false;
  const normalizedSide = side === "github" ? "github" : "local";
  const page = state.filePages[normalizedSide];
  if (page.loading) return false;
  page.loading = true;
  try {
    const result = await api("/api/action", {
      action: "listFiles",
      side: normalizedSide,
      query: state.fileQuery.trim(),
      offset,
      limit: page.limit
    });
    const next = result.page || {};
    state.filePages[normalizedSide] = {
      items: asArray(next.items),
      offset: Number(next.offset || 0),
      limit: Number(next.limit || page.limit),
      total: Number(next.total || 0),
      nextOffset: Number(next.nextOffset ?? -1),
      query: String(next.query || ""),
      revision: String(next.revision || ""),
      loaded: true,
      loading: false
    };
    if (normalizedSide === "github") renderRemoteFiles();
    else renderFiles();
    elements.fileCount.textContent = `${Number(next.total || 0)} ${normalizedSide === "github" ? "GitHub" : "local"} file${Number(next.total || 0) === 1 ? "" : "s"}`;
    if (announce) elements.liveStatus.textContent = `Loaded ${asArray(next.items).length} ${normalizedSide} files.`;
    return true;
  } catch (error) {
    page.loading = false;
    toast(error.message || String(error), true);
    return false;
  }
}

function renderFilePreview() {
  const preview = state.preview;
  if (!preview) return;
  const isDiff = state.previewMode === "diff";
  elements.previewContentTab.classList.toggle("is-active", !isDiff);
  elements.previewDiffTab.classList.toggle("is-active", isDiff);
  elements.previewContentTab.setAttribute("aria-selected", String(!isDiff));
  elements.previewDiffTab.setAttribute("aria-selected", String(isDiff));
  elements.previewContentTab.tabIndex = isDiff ? -1 : 0;
  elements.previewDiffTab.tabIndex = isDiff ? 0 : -1;
  if (isDiff) {
    renderHighlightedDiff(elements.filePreviewContent, preview.diff || "No net difference is available for this file.");
    return;
  }
  const messages = {
    binary: "Binary file — content preview is disabled.",
    "too-large": `File is larger than the ${Math.round(Number(preview.maxPreviewBytes || 524288) / 1024)} KiB preview limit.`,
    deleted: "This file is deleted from the local working copy. Open Differences to inspect the deletion."
  };
  elements.filePreviewContent.textContent = preview.kind === "text" ? preview.content || "This text file is empty." : messages[preview.kind] || "Preview is unavailable.";
}

async function openFilePreview(side, path) {
  if (state.busy) return;
  elements.liveStatus.textContent = `Loading ${path}`;
  try {
    const result = await api("/api/action", { action: "previewFile", side, file: path });
    state.preview = result.preview;
    state.previewMode = "content";
    elements.filePreviewSide.textContent = side === "github" ? "Fetched GitHub file" : "Local working file";
    elements.filePreviewTitle.textContent = path;
    elements.filePreviewMeta.textContent = `${result.preview.branch || "no branch"} · ${result.preview.kind} · ${Number(result.preview.byteLength || 0).toLocaleString()} bytes`;
    renderFilePreview();
    if (window.BranchlinePreviewDialog) window.BranchlinePreviewDialog.show();
    else elements.filePreviewDialog.showModal();
    elements.liveStatus.textContent = `Preview opened for ${path}`;
  } catch (error) {
    toast(error.message || String(error), true);
  }
}

function renderFiles() {
  const summary = state.summary;
  elements.filesList.replaceChildren();
  if (!summary?.ok) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.innerText = "No repository loaded\nChoose a trusted working folder from the left.";
    elements.filesList.append(empty);
    return;
  }

  const query = state.fileQuery.trim();
  const page = state.filePages.local;
  const files = page.loaded ? asArray(page.items) : asArray(summary.files);
  renderFilePagination("local");

  if (files.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    const icon = document.createElement("span");
    icon.textContent = query ? "⌕" : "✓";
    const title = document.createElement("strong");
    title.textContent = query ? "No matching files" : "Nothing to show";
    const copy = document.createElement("p");
    copy.textContent = query ? "Try a shorter file filter." : "The repository has no visible files.";
    empty.append(icon, title, copy);
    elements.filesList.append(empty);
    return;
  }

  files.forEach((file) => {
    const row = document.createElement("div");
    row.className = `file-row state-${file.state}${state.selectedFile === file.path ? " is-selected" : ""}`;

    const badge = document.createElement("span");
    badge.className = "file-state";
    badge.textContent = fileStateLabel(file);
    badge.title = file.state;

    const select = document.createElement("button");
    select.type = "button";
    select.className = "file-select";
    select.addEventListener("click", () => {
      setSelectedFile(file.path);
      openFilePreview("local", file.path);
    });
    const name = document.createElement("strong");
    name.textContent = file.path;
    const detail = document.createElement("small");
    detail.textContent = fileStateDescription(file);
    select.append(name, detail);

    const actions = document.createElement("div");
    actions.className = "file-actions";
    availableFileActions(file).forEach(([label, action, dangerous]) => {
      const button = document.createElement("button");
      button.type = "button";
      button.className = `file-action${dangerous ? " is-danger" : ""}`;
      button.textContent = label;
      button.disabled = state.busy || summary.stateOk === false;
      button.addEventListener("click", async () => {
        setSelectedFile(file.path);
        if (action === "restoreFile") {
          const accepted = window.confirm(`Restore “${file.path}” to the last committed version? Local changes in this file will be replaced.`);
          if (!accepted) return;
          await runAction({ action, file: file.path, confirm: `RESTORE:${file.path}` }, `Restoring ${shortPath(file.path)}…`);
        } else {
          await runAction({ action, file: file.path }, `${label} ${shortPath(file.path)}…`);
        }
      });
      actions.append(button);
    });

    row.append(badge, select, actions);
    elements.filesList.append(row);
  });
  renderFilePagination("local");
}

function renderRemoteFiles() {
  const summary = state.summary;
  const snapshot = summary?.remoteSnapshot || {};
  const relationship = String(summary?.tracking?.relationship || "no-remote");
  elements.githubFilesList.replaceChildren();

  if (!summary?.isRepo || !summary?.remoteValid) {
    elements.githubSnapshotNotice.textContent = "Connect a GitHub repository to inspect its last fetched snapshot.";
    elements.githubFilesList.innerHTML = '<div class="empty-state"><strong>No GitHub snapshot</strong><p>Choose a Git repository and connect its GitHub origin first.</p></div>';
    return;
  }
  if (!snapshot.available) {
    elements.githubSnapshotNotice.textContent = relationship === "remote-empty"
      ? "GitHub is connected, but it has no branches or committed files yet."
      : "No GitHub branch snapshot is available. Check GitHub again or review the connection state.";
    elements.githubFilesList.innerHTML = '<div class="empty-state"><strong>No remote files</strong><p>There is no fetched GitHub tree to display.</p></div>';
    return;
  }

  const incoming = asArray(snapshot.incomingCommits);
  const prefix = `GitHub snapshot: ${snapshot.branch}`;
  if (relationship === "unrelated") {
    elements.githubSnapshotNotice.textContent = `${prefix}. This history is unrelated to the local project, so Pull and Publish are blocked.`;
  } else if (relationship === "behind") {
    elements.githubSnapshotNotice.textContent = `${prefix}. ${incoming.length} incoming commit${incoming.length === 1 ? "" : "s"} can be reviewed and pulled safely. IN marks the net files that differ from local HEAD.`;
  } else if (relationship === "diverged") {
    elements.githubSnapshotNotice.textContent = `${prefix}. Both sides contain unique commits; IN marks remote-side net differences before the merge, not guaranteed conflict results.`;
  } else if (relationship === "unpublished") {
    elements.githubSnapshotNotice.textContent = `${prefix}. Your current local branch has not been published yet.`;
  } else {
    elements.githubSnapshotNotice.textContent = `${prefix}. This is the last fetched GitHub view, not a live file system.`;
  }

  if (incoming.length > 0) {
    const commitGroup = document.createElement("div");
    commitGroup.className = "incoming-commit-group";
    const title = document.createElement("strong");
    title.textContent = "Incoming commits";
    commitGroup.append(title);
    incoming.slice(0, 8).forEach((commit) => {
      const item = document.createElement("span");
      item.textContent = `${commit.shortHash} · ${commit.subject}`;
      commitGroup.append(item);
    });
    elements.githubFilesList.append(commitGroup);
  }

  const query = state.fileQuery.trim();
  const page = state.filePages.github;
  const files = page.loaded ? asArray(page.items) : asArray(snapshot.files);
  renderFilePagination("github");
  if (files.length === 0) {
    const empty = document.createElement("div");
    empty.className = "empty-state";
    empty.innerHTML = `<strong>${query ? "No matching GitHub files" : "No files in this snapshot"}</strong><p>${query ? "Try a shorter filter." : "This GitHub branch has no committed files."}</p>`;
    elements.githubFilesList.append(empty);
    return;
  }

  files.forEach((file) => {
    const row = document.createElement("div");
    row.className = `file-row remote-file-row state-${file.state || "remote"}`;
    const badge = document.createElement("span");
    badge.className = "file-state";
    badge.textContent = file.state === "incoming" ? "IN" : "GH";
    badge.title = file.state === "incoming" ? "Net remote-side difference from local HEAD" : "Committed in the fetched GitHub snapshot";
    const copy = document.createElement("button");
    copy.type = "button";
    copy.className = "file-select remote-file-copy";
    copy.addEventListener("click", () => openFilePreview("github", file.path));
    const name = document.createElement("strong");
    name.textContent = file.path;
    const detail = document.createElement("small");
    detail.textContent = file.state === "incoming" ? "remote-side difference before Pull or merge" : `fetched GitHub file · ${snapshot.branch}`;
    copy.append(name, detail);
    row.append(badge, copy);
    elements.githubFilesList.append(row);
  });
  renderFilePagination("github");
}

function setRepositoryView(view) {
  state.activeRepositoryView = view === "github" ? "github" : "local";
  const github = state.activeRepositoryView === "github";
  elements.localViewTab.classList.toggle("is-active", !github);
  elements.githubViewTab.classList.toggle("is-active", github);
  elements.localViewTab.setAttribute("aria-selected", String(!github));
  elements.githubViewTab.setAttribute("aria-selected", String(github));
  elements.localViewTab.tabIndex = github ? -1 : 0;
  elements.githubViewTab.tabIndex = github ? 0 : -1;
  elements.localFilesView.classList.toggle("is-hidden", github);
  elements.githubFilesView.classList.toggle("is-hidden", !github);
  elements.composerPanel.classList.toggle("is-hidden", github);
  document.body.classList.toggle("is-local-view", !github);
  document.body.classList.toggle("is-github-view", github);
  const page = state.filePages[github ? "github" : "local"];
  const fallbackCount = github ? Number(state.summary?.remoteSnapshot?.fileCount || 0) : Number(state.summary?.fileCount || 0);
  const count = page.loaded ? page.total : fallbackCount;
  elements.fileCount.textContent = `${count} ${github ? "GitHub" : "local"} file${count === 1 ? "" : "s"}`;
  renderSyncContext();
  updateActionEmphasis();
  if (state.summary?.isRepo && (!page.loaded || page.query !== state.fileQuery.trim())) loadFilePage(github ? "github" : "local", { offset: 0 });
}

function renderSyncContext() {
  const summary = state.summary || {};
  const tracking = summary.tracking || {};
  const relationship = String(tracking.relationship || "no-remote");
  const changed = Number(summary.changedCount ?? asArray(summary.changedFiles).length);
  const ahead = Number(tracking.ahead || 0);
  const behind = Number(tracking.behind || 0);
  const branch = summary.branch || "current branch";
  const github = state.activeRepositoryView === "github";

  elements.syncContextLabel.textContent = github ? `GitHub → local ${branch}` : `Local ${branch} → GitHub`;
  elements.syncSwitchViewButton.textContent = github ? "Back to local →" : "Review GitHub →";
  elements.syncSwitchViewButton.disabled = !summary?.ok || !summary?.isRepo;

  if (!summary?.ok || !summary?.isRepo) {
    elements.syncContextHelp.textContent = "Choose a Git repository to see its local and GitHub actions.";
    return;
  }

  if (github) {
    if (!summary.remoteValid) {
      elements.syncContextHelp.textContent = "Connect a valid GitHub origin before checking or pulling.";
    } else if (["behind", "diverged"].includes(relationship) && changed > 0) {
      const action = relationship === "diverged" ? "Integrate" : "Pull";
      elements.syncContextHelp.textContent = `${action} is waiting: commit or restore all ${changed} local change${changed === 1 ? "" : "s"}. Staging alone is not enough.`;
    } else if (relationship === "diverged") {
      elements.syncContextHelp.textContent = `Ready to integrate ${behind} GitHub commit${behind === 1 ? "" : "s"} with ${ahead} local commit${ahead === 1 ? "" : "s"}. No force push or history rewrite.`;
    } else if (relationship === "behind") {
      elements.syncContextHelp.textContent = `Pull will fast-forward ${branch} by ${behind} commit${behind === 1 ? "" : "s"}.`;
    } else {
      elements.syncContextHelp.textContent = "Check GitHub refreshes the fetched GitHub snapshot only. It never changes local project files.";
    }
    return;
  }

  if (["behind", "diverged"].includes(relationship)) {
    elements.syncContextHelp.textContent = `Publish is waiting: review and integrate ${behind} incoming GitHub commit${behind === 1 ? "" : "s"} first.`;
  } else if (["ahead", "unpublished", "remote-empty"].includes(relationship)) {
    elements.syncContextHelp.textContent = `${ahead || 1} local commit${ahead === 1 ? "" : "s"} can be published from ${branch}.`;
  } else if (changed > 0) {
    elements.syncContextHelp.textContent = `Stage and commit the ${changed} local change${changed === 1 ? "" : "s"}; Publish unlocks when ${branch} is ahead.`;
  } else {
    elements.syncContextHelp.textContent = "No local commits are waiting to be published.";
  }
}

function updateActionEmphasis() {
  const relationship = String(state.summary?.tracking?.relationship || "no-remote");
  const primary = ["local-empty", "behind", "diverged"].includes(relationship)
    ? elements.pullButton
    : ["ahead", "unpublished", "remote-empty"].includes(relationship)
      ? elements.pushButton
      : elements.fetchButton;
  [elements.fetchButton, elements.pullButton, elements.pushButton].forEach((button) => {
    button.classList.toggle("is-primary-action", button === primary && !button.disabled);
  });
  elements.pushButton.classList.toggle("is-view-context", state.activeRepositoryView === "local" && !elements.pushButton.disabled);
  elements.pullButton.classList.toggle("is-view-context", state.activeRepositoryView === "github" && !elements.pullButton.disabled);
}

function syncGuideFor(intent = "publish") {
  const summary = state.summary || {};
  const tracking = summary.tracking || {};
  const configured = Boolean(summary.ok && summary.isRepo);
  const remoteReady = configured && Boolean(summary.remoteValid);
  const relationship = String(tracking.relationship || (configured ? "no-remote" : "no-repository"));
  const changes = asArray(summary.changedFiles);
  const staged = changes.filter((file) => ["staged", "mixed"].includes(file.state)).length;
  const ahead = Number(tracking.ahead || 0);
  const behind = Number(tracking.behind || 0);
  const branch = summary.branch || "current branch";
  const operation = String(summary.operation || "");
  const guide = {
    title: intent === "publish" ? "Why Publish is waiting" : "Why receiving is waiting",
    description: "Branchline found the next safe step.",
    ahead,
    behind,
    changes: changes.length,
    steps: [],
    primaryLabel: "Review repository",
    action: "local-changes"
  };

  const step = (label, detail, status = "waiting") => ({ label, detail, status });

  if (!configured) {
    guide.description = "Choose a Git repository before synchronizing.";
    guide.steps = [step("Choose a project folder", "Inspect the folder so Branchline can read its Git state.", "current")];
    guide.primaryLabel = "Choose a folder";
    guide.action = "choose-folder";
    return guide;
  }

  if (summary.stateOk === false) {
    guide.description = "Git could not read the repository reliably, so every changing action is blocked.";
    guide.steps = [
      step("Repair the Git repository", summary.stateError || "Open the selected output or run Git status in the folder.", "current"),
      step("Refresh local state", "Branchline must read status and the current branch successfully."),
      step(intent === "publish" ? "Publish" : "Receive", "Available only after the safety check succeeds.")
    ];
    guide.primaryLabel = "Retry local refresh";
    guide.action = "refresh";
    return guide;
  }

  if (relationship === "detached") {
    guide.description = "The selected commit is detached and has no branch name.";
    guide.steps = [
      step("Create a branch here", "Enter a new branch name in Branches so this commit has a safe destination.", "current"),
      step("Review branch tracking", "Connect or publish the new named branch."),
      step(intent === "publish" ? "Publish" : "Receive", "Available after the branch is named.")
    ];
    guide.primaryLabel = "Open branch tools";
    guide.action = "branches";
    return guide;
  }

  if (!remoteReady) {
    guide.description = "This local repository is not connected to a valid GitHub origin.";
    guide.steps = [
      step("Local repository is ready", branch, "done"),
      step("Connect a GitHub repository", "Enter the GitHub URL and confirm the origin.", "current"),
      step(intent === "publish" ? "Publish local commits" : "Check GitHub", "Available after the connection is verified.")
    ];
    guide.primaryLabel = "Go to GitHub connection";
    guide.action = "connect";
    return guide;
  }

  if (operation) {
    guide.description = `A ${operation} operation is unfinished. Complete or abort it before starting another synchronization.`;
    guide.steps = [
      step(`Finish the active ${operation}`, "Resolve its files and commit, or use the safe Abort action.", "current"),
      step("Refresh repository state", "Branchline will recalculate incoming and outgoing commits."),
      step(intent === "publish" ? "Publish" : "Receive from GitHub", "Available after the operation is complete.")
    ];
    guide.primaryLabel = "Open recovery tools";
    guide.action = "recovery";
    return guide;
  }

  if (["behind", "diverged"].includes(relationship) && changes.length > 0) {
    guide.description = `${changes.length} local change${changes.length === 1 ? " is" : "s are"} still outside a commit. GitHub integration waits so those files cannot be mixed into a merge accidentally.`;
    guide.steps = [
      step("Finish local changes", staged > 0 ? `${staged} file${staged === 1 ? " is" : "s are"} staged: enter a message and commit, or restore the change.` : "Stage and commit the work you want, or restore it.", "current"),
      step(relationship === "diverged" ? `Integrate ${behind} GitHub commit${behind === 1 ? "" : "s"}` : `Pull ${behind} GitHub commit${behind === 1 ? "" : "s"}`, "This becomes available when the working tree is clean."),
      step(`Publish ${ahead} local commit${ahead === 1 ? "" : "s"}`, "Publish follows integration.")
    ];
    guide.primaryLabel = staged > 0 ? "Go to commit message" : "Review local changes";
    guide.action = staged > 0 ? "local-commit" : "local-changes";
    return guide;
  }

  if (relationship === "diverged") {
    guide.description = `${branch} contains ${ahead} local commit${ahead === 1 ? "" : "s"}, and GitHub contains ${behind} different commit${behind === 1 ? "" : "s"}. Integrate both histories before publishing.`;
    guide.steps = [
      step("Local changes are committed", `${ahead} local commit${ahead === 1 ? " is" : "s are"} ready.`, "done"),
      step(`Integrate ${behind} GitHub commit${behind === 1 ? "" : "s"}`, "Branchline creates a normal merge and preserves both sides.", "current"),
      step("Publish the integrated branch", "This unlocks automatically after a successful integration.")
    ];
    guide.primaryLabel = "Open GitHub side to integrate";
    guide.action = "github";
    return guide;
  }

  if (relationship === "behind") {
    guide.description = `GitHub is ${behind} commit${behind === 1 ? "" : "s"} ahead of local ${branch}. Pull that work before publishing.`;
    guide.steps = [
      step("Local working tree is clean", "No local files are waiting.", "done"),
      step(`Pull ${behind} GitHub commit${behind === 1 ? "" : "s"}`, "A fast-forward updates the local branch without rewriting history.", "current"),
      step("Publish future local commits", "Available after local and GitHub agree.")
    ];
    guide.primaryLabel = "Open GitHub side to pull";
    guide.action = "github";
    return guide;
  }

  if (["ahead", "unpublished", "remote-empty"].includes(relationship) && tracking.hasLocalCommit) {
    guide.description = `${ahead || 1} local commit${ahead === 1 ? " is" : "s are"} ready to publish from ${branch}.`;
    guide.steps = [
      step("Local commit is ready", "GitHub has no incoming commit blocking it.", "done"),
      step("Publish to GitHub", "This is the available action now.", "current")
    ];
    guide.primaryLabel = "Publish now";
    guide.action = "publish";
    return guide;
  }

  if (relationship === "local-empty") {
    guide.description = "GitHub already has history, but this local repository has no commit yet.";
    guide.steps = [
      step("Bring GitHub history here", "Existing local files are preserved for review.", "current"),
      step("Commit local changes", "Available after GitHub becomes the local base."),
      step("Publish", "Available after the local commit.")
    ];
    guide.primaryLabel = "Open GitHub side";
    guide.action = "github";
    return guide;
  }

  if (["both-empty", "remote-empty"].includes(relationship) && !tracking.hasLocalCommit && changes.length === 0) {
    guide.description = "Both sides are waiting for the first local commit.";
    guide.steps = [
      step("Create or copy a project file", "Place the first file in the local folder.", "current"),
      step("Stage and commit the file", "The commit becomes the first publishable unit."),
      step("Publish the first branch", "Branchline creates the matching GitHub branch.")
    ];
    guide.primaryLabel = "Open local files";
    guide.action = "local-changes";
    return guide;
  }

  if (relationship === "upstream-mismatch") {
    guide.description = `${branch} tracks ${tracking.upstream || "another branch"} instead of origin/${branch}.`;
    guide.steps = [
      step("Confirm the matching GitHub branch", `Branchline will fetch and verify origin/${branch}.`, "done"),
      step("Repair tracking", "Only the upstream pointer changes; commits and files are untouched.", "current"),
      step(intent === "publish" ? "Publish" : "Receive", "Available after tracking is repaired.")
    ];
    guide.primaryLabel = "Repair branch tracking";
    guide.action = "repair-upstream";
    return guide;
  }

  if (["unrelated", "remote-branch-missing", "error"].includes(relationship)) {
    guide.description = "Branchline cannot prove that this local branch and GitHub branch can be combined safely.";
    guide.steps = [
      step("Review the repository connection", tracking.error || "Confirm that this is the correct GitHub project and branch.", "current"),
      step("Reconnect or choose the correct project", "Branchline will never force unrelated histories together."),
      step(intent === "publish" ? "Publish" : "Receive", "Available after the relationship is safe.")
    ];
    guide.primaryLabel = "Review GitHub connection";
    guide.action = "connect";
    return guide;
  }

  if (changes.length > 0) {
    guide.description = "These local file changes are not commits yet, so Git has nothing new to publish.";
    guide.steps = [
      step("Stage the files you want", `${changes.length} local change${changes.length === 1 ? " is" : "s are"} waiting.`, staged > 0 ? "done" : "current"),
      step("Commit the staged files", "A commit is the unit Git can publish.", staged > 0 ? "current" : "waiting"),
      step("Publish the commit", "Available when the branch is ahead of GitHub.")
    ];
    guide.primaryLabel = staged > 0 ? "Go to commit message" : "Review local changes";
    guide.action = staged > 0 ? "local-commit" : "local-changes";
    return guide;
  }

  guide.title = intent === "publish" ? "Nothing is waiting to publish" : "Nothing is waiting to pull";
  guide.description = `Local ${branch} and GitHub already agree.`;
  guide.steps = [step("Repository is synchronized", "Create and commit a local change to publish, or Check GitHub for new remote work.", "done")];
  guide.primaryLabel = intent === "publish" ? "Review local files" : "Check GitHub view";
  guide.action = intent === "publish" ? "local-changes" : "github";
  return guide;
}

function showSyncGuide(intent) {
  const guide = syncGuideFor(intent);
  state.syncGuideAction = guide.action;
  elements.syncGuideTitle.textContent = guide.title;
  elements.syncGuideDescription.textContent = guide.description;
  elements.syncGuideAhead.textContent = String(guide.ahead);
  elements.syncGuideBehind.textContent = String(guide.behind);
  elements.syncGuideChanges.textContent = String(guide.changes);
  elements.syncGuidePrimaryButton.textContent = guide.primaryLabel;
  elements.syncGuideSteps.replaceChildren();
  guide.steps.forEach((item, index) => {
    const row = document.createElement("li");
    row.className = `sync-guide-step is-${item.status}`;
    const marker = document.createElement("span");
    marker.className = "sync-guide-marker";
    marker.textContent = item.status === "done" ? "✓" : String(index + 1);
    const copy = document.createElement("div");
    const title = document.createElement("strong");
    title.textContent = item.label;
    const detail = document.createElement("small");
    detail.textContent = item.detail;
    copy.append(title, detail);
    row.append(marker, copy);
    elements.syncGuideSteps.append(row);
  });
  if (window.BranchlineSyncGuideDialog) window.BranchlineSyncGuideDialog.show();
  else if (typeof elements.syncGuideDialog.showModal === "function") elements.syncGuideDialog.showModal();
  else elements.syncGuideDialog.setAttribute("open", "");
}

function closeSyncGuide() {
  if (window.BranchlineSyncGuideDialog) window.BranchlineSyncGuideDialog.close();
  else if (typeof elements.syncGuideDialog.close === "function" && elements.syncGuideDialog.open) elements.syncGuideDialog.close();
  else elements.syncGuideDialog.removeAttribute("open");
}

function followSyncGuide() {
  const action = state.syncGuideAction || "local-changes";
  closeSyncGuide();
  if (action === "publish") {
    const relationship = String(state.summary?.tracking?.relationship || "");
    if (["unpublished", "remote-empty"].includes(relationship)) publishNewBranch();
    else runAction({ action: "push" }, "Publishing current branch…");
    return;
  }
  if (action === "refresh") {
    refreshLocalFiles({ announce: true });
    return;
  }
  if (action === "repair-upstream") {
    repairUpstream();
    return;
  }
  if (action === "branches") {
    elements.newBranchInput.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => elements.newBranchInput.focus(), 350);
    return;
  }
  if (action === "github") {
    setRepositoryView("github");
    elements.syncContextPanel.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => elements.pullButton.focus(), 350);
    return;
  }
  if (action === "connect") {
    elements.remoteInput.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => elements.remoteInput.focus(), 350);
    return;
  }
  if (action === "choose-folder") {
    elements.repoPathInput.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => elements.repoPathInput.focus(), 350);
    return;
  }
  if (action === "recovery") {
    elements.abortOperationButton.scrollIntoView({ behavior: "smooth", block: "center" });
    window.setTimeout(() => elements.abortOperationButton.focus(), 350);
    return;
  }
  setRepositoryView("local");
  const target = action === "local-commit" ? elements.composerPanel : elements.localFilesView;
  target.scrollIntoView({ behavior: "smooth", block: "center" });
  if (action === "local-commit") window.setTimeout(() => elements.commitMessageInput.focus(), 350);
}

function renderBranches() {
  const branches = asArray(state.summary?.branches).filter((branch) => branch && branch.name);
  const names = branches.map((branch) => branch.name);
  const remoteOnly = asArray(state.summary?.remoteBranches).filter((name) => name && !names.includes(name));
  const current = String(state.summary?.branch || "");
  const defaultBranch = String(state.summary?.defaultBranch || "main");
  const previousDestination = elements.branchSelect.value;
  const previousSource = elements.mergeSourceSelect.value;
  const previousTarget = elements.mergeTargetSelect.value;

  elements.branchSelect.replaceChildren();
  const destinationPlaceholder = document.createElement("option");
  destinationPlaceholder.value = "";
  destinationPlaceholder.textContent = names.some((name) => name !== current) ? "Choose another branch…" : "No other local branch";
  destinationPlaceholder.selected = true;
  elements.branchSelect.append(destinationPlaceholder);
  branches.filter((branch) => branch.name !== current).forEach((branch) => {
    const option = document.createElement("option");
    option.value = branch.name;
    option.textContent = branch.name;
    elements.branchSelect.append(option);
  });
  if (previousDestination && names.includes(previousDestination) && previousDestination !== current) elements.branchSelect.value = previousDestination;

  [elements.mergeSourceSelect, elements.mergeTargetSelect].forEach((select) => {
    select.replaceChildren();
    branches.forEach((branch) => {
      const option = document.createElement("option");
      option.value = branch.name;
      option.textContent = branch.current ? `${branch.name} · current` : branch.name;
      select.append(option);
    });
  });

  const source = previousSource && names.includes(previousSource)
    ? previousSource
    : current && current !== defaultBranch
      ? current
      : names.find((name) => name !== current) || current;
  const target = previousTarget && names.includes(previousTarget) && previousTarget !== source
    ? previousTarget
    : names.includes(defaultBranch) && defaultBranch !== source
      ? defaultBranch
      : current && current !== source
        ? current
        : names.find((name) => name !== source) || current;
  elements.mergeSourceSelect.value = source || "";
  elements.mergeTargetSelect.value = target || "";

  const previousRemote = elements.remoteBranchSelect.value;
  elements.remoteBranchSelect.replaceChildren();
  const remotePlaceholder = document.createElement("option");
  remotePlaceholder.value = "";
  remotePlaceholder.textContent = remoteOnly.length > 0 ? "Choose a GitHub-only branch…" : "No GitHub-only branches";
  elements.remoteBranchSelect.append(remotePlaceholder);
  remoteOnly.forEach((name) => {
    const option = document.createElement("option");
    option.value = name;
    option.textContent = `origin/${name}`;
    elements.remoteBranchSelect.append(option);
  });
  if (remoteOnly.includes(previousRemote)) elements.remoteBranchSelect.value = previousRemote;
  updateBranchControls();
}

function updateBranchControls() {
  const summary = state.summary || {};
  const current = String(summary.branch || "");
  const destination = elements.branchSelect.value || "";
  const mergeSource = elements.mergeSourceSelect.value || "";
  const mergeTarget = elements.mergeTargetSelect.value || "";
  const changed = Number(summary.changedCount ?? asArray(summary.changedFiles).length);
  const defaultBranch = String(summary.defaultBranch || "main");
  const onSharedBase = Boolean(current && current === defaultBranch);
  const branchPublished = Boolean(summary.tracking?.matchingRemoteExists);
  elements.currentBranchLabel.textContent = current || (summary.headState === "detached" ? `Detached at ${String(summary.headCommit || "").slice(0, 8)}` : "—");
  elements.branchSummary.textContent = summary.headState === "detached"
    ? "This commit has no branch name. Enter a new branch name below to preserve it before other work."
    : current
      ? onSharedBase
        ? `${defaultBranch} is the shared base. Check GitHub and Pull first, then create a short-lived branch for the new task.`
        : branchPublished
          ? `Team branch ${current} is on GitHub. Commit and Publish your next logical change, then open a pull request into ${defaultBranch}.`
          : `New local branch ${current} is ready. Commit the first logical change, then Publish it as a new GitHub branch.`
      : "Create the first commit before managing branches.";
  elements.switchBranchButton.textContent = destination ? `Switch to ${destination}` : "Choose a destination";
  elements.branchSwitchHelp.textContent = !destination
    ? "Choose a different local branch above."
    : changed > 0
      ? `${changed} uncommitted change${changed === 1 ? "" : "s"} will come with you if Git can apply them safely. Git refuses rather than overwrite files.`
      : `Move from ${current} to ${destination}.`;
  elements.mergeBranchButton.textContent = mergeSource && mergeTarget && mergeSource !== mergeTarget
    ? `Merge ${mergeSource} → ${mergeTarget}`
    : "Choose a merge route";
  elements.mergeGuidance.textContent = !mergeSource || !mergeTarget
    ? "At least two local branches are required."
    : mergeSource === mergeTarget
      ? "Source and target must be different branches."
      : changed > 0
        ? `Merge is waiting: commit or restore all ${changed} local change${changed === 1 ? "" : "s"} first.`
        : `For team work, prefer Publish → Pull Request → review → merge on GitHub. If your team explicitly wants a local merge, Branchline will switch to ${mergeTarget} and merge ${mergeSource} into it normally.`;

  elements.pullRequestLink.classList.add("is-hidden");
  elements.pullRequestLink.removeAttribute("href");
  elements.pullRequestLink.textContent = "04 Open pull request on GitHub ↗";
  if (summary.remoteWebUrl && current && current !== defaultBranch && summary.tracking?.matchingRemoteExists) {
    try {
      const base = new URL(summary.remoteWebUrl);
      if (base.protocol === "https:" && base.hostname === "github.com") {
        elements.pullRequestLink.href = `${base.href.replace(/\/$/, "")}/compare/${encodeURIComponent(defaultBranch)}...${encodeURIComponent(current)}?expand=1`;
        elements.pullRequestLink.textContent = `04 Open pull request: ${current} → ${defaultBranch} ↗`;
        elements.pullRequestLink.classList.remove("is-hidden");
      }
    } catch { }
  }
}

function setSelectedCommit(hash) {
  state.selectedCommit = hash || "";
  elements.commitSelect.value = state.selectedCommit;
  renderCommits();
}

function renderCommits() {
  const commits = asArray(state.summary?.commits).filter((commit) => commit?.hash);
  const query = state.commitQuery.trim().toLowerCase();
  const visible = commits.filter((commit) => !query || `${commit.shortHash} ${commit.subject} ${commit.time}`.toLowerCase().includes(query));

  elements.commitSelect.replaceChildren();
  commits.forEach((commit) => {
    const option = document.createElement("option");
    option.value = commit.hash;
    option.textContent = `${commit.shortHash} · ${commit.subject}`;
    elements.commitSelect.append(option);
  });
  if (!commits.some((commit) => commit.hash === state.selectedCommit)) state.selectedCommit = commits[0]?.hash || "";
  elements.commitSelect.value = state.selectedCommit;

  elements.commitsList.replaceChildren();
  visible.slice(0, 30).forEach((commit) => {
    const button = document.createElement("button");
    button.type = "button";
    button.className = `commit-card${commit.hash === state.selectedCommit ? " is-selected" : ""}`;
    button.addEventListener("click", () => setSelectedCommit(commit.hash));
    const hash = document.createElement("span");
    hash.className = "commit-hash";
    hash.textContent = commit.shortHash;
    const copy = document.createElement("span");
    copy.className = "commit-copy";
    const subject = document.createElement("strong");
    subject.textContent = commit.subject;
    const time = document.createElement("small");
    time.textContent = commit.time;
    copy.append(subject, time);
    button.append(hash, copy);
    elements.commitsList.append(button);
  });
}

function renderSummary() {
  const summary = state.summary;
  const configured = Boolean(summary?.ok && summary?.isRepo);
  const stateHealthy = configured && summary?.stateOk !== false;
  const folderSelected = Boolean(summary?.folderSelected);
  const folder = summary?.folder || {};
  const tracking = summary?.tracking || {};
  const changedFiles = asArray(summary?.changedFiles);
  const changedTotal = Number(summary?.changedCount ?? changedFiles.length);
  const stagedTotal = Number(summary?.stagedCount ?? changedFiles.filter((file) => ["staged", "mixed"].includes(file.state)).length);
  const unstagedTotal = Number(summary?.unstagedCount ?? changedFiles.filter((file) => ["modified", "mixed", "untracked", "deleted", "conflicted"].includes(file.state)).length);
  const conflictTotal = Number(summary?.conflictCount ?? changedFiles.filter((file) => file.state === "conflicted").length);
  const relationship = String(tracking.relationship || (configured ? "no-remote" : "no-repository"));
  const backups = asArray(folder.backups);

  document.body.classList.toggle("has-repository", configured);

  elements.healthDot.classList.toggle("is-good", stateHealthy && !state.busy);
  elements.healthDot.classList.toggle("is-idle", !configured && !state.busy);
  elements.healthText.textContent = state.busy ? elements.busyText.textContent : configured ? stateHealthy ? "Repository ready" : "Repository needs attention" : folderSelected ? "Normal folder selected" : "Waiting for a folder";
  elements.headerBranch.textContent = configured ? summary.headState === "detached" ? `detached ${String(summary.headCommit || "").slice(0, 8)}` : summary.branch || "unborn" : "—";

  if (document.activeElement !== elements.repoPathInput && (summary?.selectedPath || summary?.repoPath)) elements.repoPathInput.value = summary.selectedPath || summary.repoPath;
  elements.localStatus.textContent = configured ? summary.repoName || "Git repository" : folderSelected ? folder.name || "Normal folder" : "Not selected";
  elements.localBadge.textContent = configured ? "Git ready" : folderSelected ? "Normal folder" : "Idle";
  elements.localBadge.className = `status-badge ${configured ? "is-good" : folderSelected ? "is-warn" : "is-neutral"}`;

  elements.initializeButton.classList.toggle("is-hidden", !folderSelected || configured);
  elements.cloneRepositoryButton.classList.toggle("is-hidden", !folderSelected || configured || !folder.empty);
  elements.detachRepositoryButton.classList.toggle("is-hidden", !configured || !folder.detachable);
  elements.restoreGitButton.classList.toggle("is-hidden", configured || backups.length === 0);
  if (configured) {
    elements.folderGuidance.textContent = "Git repository ready. Local changes stay on this computer until you commit and publish them.";
  } else if (folderSelected && folder.empty) {
    elements.folderGuidance.textContent = "This empty normal folder can become a new Git project, or receive an existing GitHub project with Clone GitHub here.";
  } else if (folderSelected && backups.length > 0) {
    elements.folderGuidance.textContent = "This is a normal folder with a recoverable Branchline Git-history backup.";
  } else if (folderSelected) {
    elements.folderGuidance.textContent = "This normal folder contains files. Make it a Git repository if those files belong to one project.";
  } else {
    elements.folderGuidance.textContent = "Select a folder to see the safest next step.";
  }

  elements.repoName.textContent = configured ? summary.repoName || "Repository" : folderSelected ? folder.name || "Normal folder" : "No folder selected";
  elements.repoPathView.textContent = configured ? summary.repoPath : summary?.selectedPath || summary?.message || "Choose a project folder from the left.";
  elements.branchName.textContent = configured ? summary.headState === "detached" ? `detached ${String(summary.headCommit || "").slice(0, 8)}` : summary.branch || "unborn" : "—";
  elements.aheadCount.textContent = String(tracking.ahead || 0);
  elements.behindCount.textContent = String(tracking.behind || 0);
  elements.lastUpdated.textContent = configured ? String(summary.localScannedAt || "—").split(" ").pop() : "—";
  elements.remoteFetchedAt.textContent = configured && summary.remoteFetchedAt ? String(summary.remoteFetchedAt).split(" ").pop() : "Never";
  elements.repositoryStateError.classList.toggle("is-hidden", stateHealthy || !configured);
  elements.repositoryStateError.textContent = stateHealthy || !configured ? "" : `Branchline cannot safely change this repository until Git can read its state:\n${summary.stateError || "Unknown Git state error."}`;

  if (document.activeElement !== elements.remoteInput && summary?.remote) elements.remoteInput.value = summary.remote;
  if (summary?.remote) {
    elements.remoteStatus.textContent = summary.remoteValid ? `${summary.remoteType === "github" ? "GitHub origin" : "Test origin"}: ${summary.remote}` : `Unsupported origin: ${summary.remote}`;
  } else {
    elements.remoteStatus.textContent = "No origin configured";
  }

  elements.remoteLink.classList.add("is-hidden");
  elements.remoteLink.removeAttribute("href");
  if (summary?.remoteWebUrl) {
    try {
      const remoteUrl = new URL(summary.remoteWebUrl);
      if (remoteUrl.protocol === "https:" && remoteUrl.hostname === "github.com") {
        elements.remoteLink.href = remoteUrl.href;
        elements.remoteLink.classList.remove("is-hidden");
      }
    } catch {
      // Backend validation should make this unreachable.
    }
  }

  const remoteBranchForBridge = tracking.matchingRemoteExists
    ? tracking.remoteBranch
    : tracking.remoteDefaultBranch || tracking.remoteBranch || "remote branch";
  if (configured && summary?.remoteValid) {
    const historiesBlocked = ["unrelated", "upstream-mismatch", "remote-branch-missing", "error"].includes(relationship);
    elements.connectionBridge.className = `connection-bridge ${historiesBlocked ? "is-warning" : "is-connected"}`;
    elements.connectionBridgeTitle.textContent = historiesBlocked ? "GitHub origin connected - review needed" : "Local repository connected to GitHub";
    elements.connectionBridgeDetail.textContent = `Local ${summary.branch || "branch"} ↔ GitHub ${remoteBranchForBridge}`;
  } else if (configured && summary?.remote) {
    elements.connectionBridge.className = "connection-bridge is-warning";
    elements.connectionBridgeTitle.textContent = "Origin needs attention";
    elements.connectionBridgeDetail.textContent = "Replace it with a supported GitHub repository URL.";
  } else if (configured) {
    elements.connectionBridge.className = "connection-bridge is-offline";
    elements.connectionBridgeTitle.textContent = "Local Git is ready";
    elements.connectionBridgeDetail.textContent = "Connect a GitHub origin when you want to exchange commits.";
  } else {
    elements.connectionBridge.className = "connection-bridge is-offline";
    elements.connectionBridgeTitle.textContent = folderSelected ? "Git is not active yet" : "Not connected";
    elements.connectionBridgeDetail.textContent = folderSelected ? "Initialize this folder or clone GitHub here." : "Choose a Git repository and GitHub origin.";
  }

  const ahead = Number(tracking.ahead || 0);
  const behind = Number(tracking.behind || 0);
  elements.syncBanner.className = "sync-banner is-neutral";
  elements.syncMood.className = "mood-chip";

  const syncCopy = {
    "no-repository": [folderSelected ? "Normal folder selected" : "Choose a project folder", folderSelected ? "Make it a Git repository, or clone GitHub here when the folder is empty." : "Branchline will inspect it before offering Git actions.", folderSelected ? "Choose setup" : "Not started", "warn"],
    "no-remote": ["Local Git repository ready", summary?.remote ? "Replace the unsupported origin with a valid GitHub URL." : "Connect GitHub when you are ready to exchange commits.", "Local only", "warn"],
    "both-empty": ["Both repositories are empty", "Create a file, stage it, commit it, then publish the first commit.", "Start locally", "good"],
    "remote-empty": ["GitHub is empty", "Your local history can be published safely as the first GitHub branch.", "Ready to publish", "good"],
    "local-empty": ["GitHub already contains work", "Use Bring GitHub here to keep local files and make GitHub history the base of this folder.", "Bring GitHub here", "warn"],
    "unpublished": ["Current branch is local only", `Publish ${summary?.branch || "this branch"} to create its matching GitHub branch.`, "Ready to publish", "good"],
    "in-sync": ["Local and GitHub agree", "No committed work is waiting in either direction.", "In sync", "good"],
    "ahead": [`${ahead} outgoing commit${ahead === 1 ? "" : "s"}`, "Review local commits, then publish them to GitHub.", "Publish next", "good"],
    "behind": [`${behind} incoming commit${behind === 1 ? "" : "s"}`, changedTotal > 0 ? "Commit or restore every local change, then open the GitHub tab and Pull." : "Open the GitHub tab to review the incoming work, then Pull safely.", "Pull next", "warn"],
    "diverged": ["Local and GitHub both have new commits", changedTotal > 0 ? "Commit or restore every remaining local change. Then use Integrate GitHub, followed by Publish." : "Open the GitHub tab, integrate both histories with a normal merge, then Publish. Nothing is overwritten.", "Integrate next", "warn"],
    "unrelated": ["These are different projects", "The local and GitHub histories are unrelated. Clone GitHub into another empty folder or connect this local project to a different empty repository.", "Sync blocked", "warn"],
    "upstream-mismatch": ["Upstream mismatch", `This branch tracks ${tracking.upstream || "another branch"}, not origin/${summary?.branch || "current"}.`, "Review upstream", "warn"],
    "remote-branch-missing": ["GitHub branch is missing", "Branchline could not prove a safe relationship with the available GitHub branches.", "Review connection", "warn"],
    "detached": ["Detached commit", "Create a named branch here before committing, pulling, merging, or publishing.", "Create branch", "warn"],
    "error": ["Comparison failed", tracking.error || "Git could not compare local and GitHub safely.", "Action blocked", "warn"]
  };
  const copy = syncCopy[relationship] || syncCopy.error;
  elements.syncTitle.textContent = copy[0];
  elements.syncDescription.textContent = copy[1];
  elements.syncHelp.textContent = copy[1];
  elements.syncMood.textContent = copy[2];
  elements.syncBanner.classList.add(copy[3] === "good" ? "is-good" : "is-warn");
  elements.syncMood.classList.add(copy[3] === "good" ? "is-good" : "is-warn");
  elements.repairUpstreamButton.classList.toggle("is-hidden", relationship !== "upstream-mismatch");
  elements.publishNewBranchButton.classList.toggle("is-hidden", !["unpublished", "remote-empty"].includes(relationship));

  const currentBranchLabel = summary?.branch || "current branch";
  elements.fetchButtonNote.textContent = "Refresh GitHub snapshot only";
  elements.pushButtonNote.textContent = relationship === "diverged"
    ? `Integrate ${behind} from GitHub first`
    : relationship === "behind"
      ? `Pull ${behind} from GitHub first`
      : relationship === "unpublished" || relationship === "remote-empty"
    ? `Create ${currentBranchLabel} on GitHub`
    : ahead > 0 ? `Publish ${ahead} from ${currentBranchLabel}` : `No outgoing commits on ${currentBranchLabel}`;
  elements.pullButtonLabel.textContent = relationship === "local-empty" ? "Bring GitHub here" : relationship === "diverged" ? "Integrate GitHub" : "Pull";
  elements.pullButtonNote.textContent = relationship === "local-empty"
    ? `Keep local files - adopt ${tracking.remoteDefaultBranch || "GitHub history"}`
    : relationship === "diverged"
      ? changedTotal > 0 ? `Commit or restore ${changedTotal} local change${changedTotal === 1 ? "" : "s"} first` : `Merge ${behind} incoming with ${ahead} local`
      : behind > 0
        ? changedTotal > 0 ? `Commit or restore ${changedTotal} local change${changedTotal === 1 ? "" : "s"} first` : `Pull ${behind} into ${currentBranchLabel}`
        : `No incoming commits on ${currentBranchLabel}`;
  elements.localTabNote.textContent = `${changedTotal} uncommitted change${changedTotal === 1 ? "" : "s"}`;
  elements.githubTabNote.textContent = summary?.remoteSnapshot?.available ? `${behind} incoming · fetched ${summary.remoteFetchedAt ? String(summary.remoteFetchedAt).split(" ").pop() : "earlier"}` : "No fetched snapshot";
  elements.changeCount.textContent = `${changedTotal} change${changedTotal === 1 ? "" : "s"}`;

  const scanTime = configured ? String(summary.localScannedAt || "").split(" ").pop() : "";
  elements.localRefreshStatus.textContent = configured
    ? `${changedTotal} change${changedTotal === 1 ? "" : "s"} · ${stagedTotal} ready to commit · scanned ${scanTime || "now"}`
    : "Waiting for a Git repository";

  const identity = summary?.identity || {};
  const identityReady = Boolean(identity.configured);
  elements.identitySummary.textContent = identityReady ? `${identity.name} <${identity.email}>` : "Required before committing";
  elements.identityHelp.textContent = identityReady
    ? "This repository has its own commit author. Open this section to change it without affecting global Git settings."
    : identity.inheritedAvailable
      ? "A global Git identity was found and prefilled, but Branchline requires an explicit repository-local identity before committing."
      : "Set the author name and email recorded in commits. These values are saved only in this repository.";
  if (document.activeElement !== elements.identityNameInput) elements.identityNameInput.value = identity.name || identity.inheritedName || elements.identityNameInput.value || "";
  if (document.activeElement !== elements.identityEmailInput) elements.identityEmailInput.value = identity.email || identity.inheritedEmail || elements.identityEmailInput.value || "";
  if (!identityReady && configured) elements.identityPanel.open = true;
  elements.commitPrerequisite.classList.toggle("is-hidden", relationship !== "local-empty");
  if (!configured) {
    elements.commitGuidance.textContent = "Choose a Git repository before preparing a commit.";
  } else if (relationship === "local-empty") {
    elements.commitGuidance.textContent = "Required first step: connect this local branch to GitHub history. Commit and Publish unlock afterward.";
  } else if (!identityReady) {
    elements.commitGuidance.textContent = "Step 1 of 3: save a commit author. Then stage, commit, and publish.";
  } else if (stagedTotal === 0) {
    elements.commitGuidance.textContent = "Step 1 of 3: stage the files you want. Step 2: commit. Step 3: publish.";
  } else {
    const stagedCopy = `${stagedTotal} file${stagedTotal === 1 ? " is" : "s are"} already staged and will stay staged after Branchline closes.`;
    const remainingCopy = unstagedTotal > 0
      ? ` ${unstagedTotal} file${unstagedTotal === 1 ? " has" : "s have"} unstaged work that will not be included unless you stage it.`
      : "";
    elements.commitGuidance.textContent = `${stagedCopy}${remainingCopy} Enter a message, then commit to ${currentBranchLabel}; choose Commit staged & publish when you want both steps now.`;
  }

  elements.fileNotice.classList.toggle("is-hidden", conflictTotal === 0);
  elements.fileNotice.textContent = conflictTotal > 0 ? `${conflictTotal} conflicted file${conflictTotal === 1 ? " needs" : "s need"} resolution. Preview each difference, edit it in your normal editor, stage the resolution, then commit—or abort the operation.` : "";

  const operation = String(summary?.operation || "");
  elements.operationNotice.classList.toggle("is-hidden", !operation);
  elements.abortOperationButton.classList.toggle("is-hidden", !operation);
  elements.operationNotice.textContent = operation ? `An interrupted ${operation} is active. Resolve it and commit, or abort it safely.` : "";

  renderFiles();
  renderRemoteFiles();
  renderBranches();
  renderCommits();
  setRepositoryView(state.activeRepositoryView);
  updateAvailability();
}

function updateAvailability() {
  const configured = Boolean(state.summary?.ok && state.summary?.isRepo);
  const stateHealthy = configured && state.summary?.stateOk !== false;
  const folderSelected = Boolean(state.summary?.folderSelected);
  const folder = state.summary?.folder || {};
  const remoteReady = configured && Boolean(state.summary?.remoteValid);
  const relationship = String(state.summary?.tracking?.relationship || "no-remote");
  const hasBranches = asArray(state.summary?.branches).length > 0;
  const hasCommits = asArray(state.summary?.commits).length > 0;
  const changes = asArray(state.summary?.changedFiles);
  const hasChanges = Number(state.summary?.changedCount ?? changes.length) > 0;
  const hasStaged = Number(state.summary?.stagedCount ?? changes.filter((file) => ["staged", "mixed"].includes(file.state)).length) > 0;
  const hasUnstaged = Number(state.summary?.unstagedCount ?? changes.filter((file) => ["modified", "mixed", "untracked", "deleted", "conflicted"].includes(file.state)).length) > 0;
  const hasCommitMessage = Boolean(elements.commitMessageInput.value.trim());
  const identityReady = Boolean(state.summary?.identity?.configured);
  const disable = state.busy;

  operationControls.forEach((control) => { control.disabled = disable; });
  // Directional sync controls remain explainable even while another view is
  // settling. Their handlers either open the prerequisite guide or let
  // runAction reject a concurrent operation; the native disabled state must
  // not make an aria-disabled guide unreachable.
  if (configured) {
    elements.pullButton.disabled = false;
    elements.pushButton.disabled = false;
  }
  if (disable) return;

  elements.useRepositoryButton.disabled = !elements.repoPathInput.value.trim();
  elements.initializeButton.disabled = !folderSelected || configured;
  elements.cloneRepositoryButton.disabled = !folderSelected || configured || !folder.empty || !elements.remoteInput.value.trim();
  elements.connectRemoteButton.disabled = !stateHealthy || !elements.remoteInput.value.trim();
  elements.detachRepositoryButton.disabled = !stateHealthy || !folder.detachable;
  elements.restoreGitButton.disabled = configured || asArray(folder.backups).length === 0;
  elements.refreshLocalButton.disabled = !configured;
  elements.openRepositoryFolderButton.disabled = !configured;
  elements.stageAllButton.disabled = !stateHealthy || !hasUnstaged;
  elements.commitButton.disabled = !stateHealthy || !hasStaged || !hasCommitMessage || !identityReady || relationship === "local-empty";
  elements.createBranchButton.disabled = !stateHealthy;
  elements.fetchButton.disabled = !remoteReady || !stateHealthy;
  const canAdoptGitHub = remoteReady && relationship === "local-empty" && Boolean(state.summary?.tracking?.remoteDefaultBranch);
  const canPull = remoteReady && relationship === "behind" && !hasChanges && !state.summary?.operation;
  const canIntegrate = remoteReady && relationship === "diverged" && !hasChanges && !state.summary?.operation;
  const canReceive = canAdoptGitHub || canPull || canIntegrate;
  elements.pullButton.disabled = !configured;
  const canPush = remoteReady && ["ahead", "unpublished", "remote-empty"].includes(relationship) && state.summary?.tracking?.hasLocalCommit;
  elements.pushButton.disabled = !configured;
  elements.pullButton.setAttribute("aria-disabled", String(!canReceive || !stateHealthy));
  elements.pushButton.setAttribute("aria-disabled", String(!canPush || !stateHealthy));
  elements.pullButton.classList.toggle("is-guided-blocked", configured && !canReceive);
  elements.pushButton.classList.toggle("is-guided-blocked", configured && !canPush);
  elements.githubLoginButton.disabled = !remoteReady;
  elements.resetLoginButton.disabled = !remoteReady;
  const selectedBranch = elements.branchSelect.value || "";
  const currentBranch = String(state.summary?.branch || "");
  const mergeSource = elements.mergeSourceSelect.value || "";
  const mergeTarget = elements.mergeTargetSelect.value || "";
  elements.switchBranchButton.disabled = !stateHealthy || !hasBranches || !selectedBranch || selectedBranch === currentBranch || Boolean(state.summary?.operation);
  elements.mergeBranchButton.disabled = !stateHealthy || asArray(state.summary?.branches).length < 2 || !mergeSource || !mergeTarget || mergeSource === mergeTarget || hasChanges || Boolean(state.summary?.operation);
  elements.deleteBranchButton.disabled = !stateHealthy || !hasBranches || !selectedBranch || selectedBranch === currentBranch;
  elements.showCommitButton.disabled = !configured || !hasCommits;
  [elements.revertCommitButton, elements.resetCommitButton].forEach((button) => { button.disabled = !stateHealthy || !hasCommits; });
  elements.restoreFromCommitButton.disabled = !stateHealthy || !hasCommits || !state.selectedFile;
  elements.abortOperationButton.disabled = !configured || !state.summary?.operation;
  elements.saveIdentityButton.disabled = !configured || !elements.identityNameInput.value.trim() || !elements.identityEmailInput.value.trim();
  elements.commitPushButton.disabled = !stateHealthy || !hasCommitMessage || !identityReady || !remoteReady || !hasStaged || relationship === "local-empty" || !["in-sync", "ahead", "unpublished", "remote-empty", "both-empty"].includes(relationship);
  elements.commitPrerequisiteButton.disabled = !canAdoptGitHub;
  elements.repairUpstreamButton.disabled = !stateHealthy || relationship !== "upstream-mismatch";
  elements.publishNewBranchButton.disabled = !stateHealthy || !["unpublished", "remote-empty"].includes(relationship);
  const remoteOnlyBranch = elements.remoteBranchSelect.value || "";
  elements.checkoutRemoteBranchButton.disabled = !stateHealthy || !remoteOnlyBranch || hasChanges || Boolean(state.summary?.operation);
  renderFilePagination("local");
  renderFilePagination("github");
  updateActionEmphasis();
}

function scheduleLocalPoll(delay = state.pollDelay) {
  window.clearTimeout(state.pollTimer);
  state.pollTimer = window.setTimeout(pollLocalStatus, delay);
}

function revisionsDiffer(left, right, fields = ["repository", "head", "config", "localRefs", "remoteRefs"]) {
  return fields.some((field) => String(left?.[field] || "") !== String(right?.[field] || ""));
}

function captureViewState() {
  const active = document.activeElement;
  return {
    id: active?.id || "",
    start: typeof active?.selectionStart === "number" ? active.selectionStart : null,
    end: typeof active?.selectionEnd === "number" ? active.selectionEnd : null,
    x: window.scrollX,
    y: window.scrollY
  };
}

function restoreViewState(snapshot) {
  if (!snapshot) return;
  window.scrollTo(snapshot.x, snapshot.y);
  const target = snapshot.id ? document.getElementById(snapshot.id) : null;
  if (target && document.contains(target)) {
    target.focus({ preventScroll: true });
    if (snapshot.start !== null && typeof target.setSelectionRange === "function") {
      try { target.setSelectionRange(snapshot.start, snapshot.end); } catch { }
    }
  }
}

function markStateStale(message) {
  state.stale = true;
  document.body.classList.add("has-stale-state");
  if (state.summary) {
    state.summary.stateOk = false;
    state.summary.stateError = message || "The repository view could not be refreshed.";
    renderSummary();
  }
  elements.refreshButton.title = "Retry a complete repository refresh";
}

function applyLocalStatus(local) {
  if (!state.summary || !local?.configured) return { full: true, localChanged: false };
  const localChanged = String(state.summary.localStatusSignature || "") !== String(local.signature || "");
  const full = revisionsDiffer(state.summary.revisions, local.revisions)
    || String(state.summary.branch || "") !== String(local.branch || "")
    || String(state.summary.headState || "") !== String(local.headState || "")
    || String(state.summary.headCommit || "") !== String(local.headCommit || "")
    || String(state.summary.operation || "") !== String(local.operation || "");
  if (full) return { full: true, localChanged };
  state.summary.changedFiles = asArray(local.changedFiles);
  state.summary.changedCount = Number(local.changedCount ?? state.summary.changedFiles.length);
  state.summary.stagedCount = Number(local.stagedCount ?? 0);
  state.summary.unstagedCount = Number(local.unstagedCount ?? 0);
  state.summary.conflictCount = Number(local.conflictCount ?? 0);
  state.summary.changesTruncated = Boolean(local.truncated);
  state.summary.localStatusSignature = String(local.signature || "");
  state.summary.localScannedAt = String(local.localScannedAt || "");
  state.summary.stateOk = Boolean(local.stateOk);
  state.summary.stateError = String(local.stateError || "");
  state.summary.revisions = local.revisions || state.summary.revisions;
  if (state.summary.tracking) {
    state.summary.tracking.ahead = Number(local.ahead ?? state.summary.tracking.ahead ?? 0);
    state.summary.tracking.behind = Number(local.behind ?? state.summary.tracking.behind ?? 0);
    state.summary.tracking.upstream = String(local.upstream ?? state.summary.tracking.upstream ?? "");
  }
  if (localChanged) {
    state.filePages.local.loaded = false;
    state.filePages.local.revision = "";
  }
  state.stale = false;
  document.body.classList.remove("has-stale-state");
  elements.refreshButton.title = "Refresh complete repository view";
  return { full: false, localChanged };
}

async function refresh({ manageBusy = true } = {}) {
  if (state.refreshing) return false;
  state.refreshing = true;
  if (manageBusy) setBusy(true, "Reading repository…");
  const view = captureViewState();
  try {
    const previous = state.summary;
    const next = await api("/api/summary");
    const repositoryChanged = previous?.repoPath !== next?.repoPath;
    const localChanged = repositoryChanged || previous?.localStatusSignature !== next?.localStatusSignature || previous?.branch !== next?.branch || previous?.headState !== next?.headState;
    const remoteChanged = repositoryChanged || String(previous?.revisions?.remoteRefs || "") !== String(next?.revisions?.remoteRefs || "") || previous?.remoteSnapshot?.branch !== next?.remoteSnapshot?.branch;
    if (localChanged) { state.filePages.local.loaded = false; state.filePages.local.revision = ""; }
    if (remoteChanged) { state.filePages.github.loaded = false; state.filePages.github.revision = ""; }
    state.summary = next;
    state.stale = false;
    document.body.classList.remove("has-stale-state");
    elements.refreshButton.title = "Refresh complete repository view";
    renderSummary();
    restoreViewState(view);
    return true;
  } catch (error) {
    const message = error.message || String(error);
    toast(message, true);
    appendActivity({ ok: false, command: "refresh", output: message });
    markStateStale(message);
    return false;
  } finally {
    if (manageBusy) setBusy(false);
    state.refreshing = false;
    const page = state.filePages[state.activeRepositoryView];
    if (state.summary?.isRepo && !page.loaded) window.setTimeout(() => loadFilePage(state.activeRepositoryView, { offset: 0 }), 0);
  }
}

async function refreshLocalFiles({ announce = true } = {}) {
  if (state.refreshing) return false;
  state.refreshing = true;
  if (announce) setBusy(true, "Refreshing local files…");
  try {
    const local = await api("/api/local-status");
    if (!state.summary || Boolean(local.configured) !== Boolean(state.summary.isRepo)) {
      state.refreshing = false;
      return await refresh({ manageBusy: false });
    }
    const applied = applyLocalStatus(local);
    if (applied.full) {
      state.refreshing = false;
      return await refresh({ manageBusy: false });
    }
    renderSummary();
    if (announce) toast("Local files and staging refreshed. GitHub was not contacted.");
    return true;
  } catch (error) {
    const message = error.message || String(error);
    toast(message, true);
    markStateStale(message);
    return false;
  } finally {
    state.refreshing = false;
    if (announce) setBusy(false);
    if (state.summary?.isRepo && state.activeRepositoryView === "local" && !state.filePages.local.loaded) {
      window.setTimeout(() => loadFilePage("local", { offset: 0 }), 0);
    }
  }
}

function actionResultMessage(result, payload, context) {
  if (result?.partial) {
    if (result.commitCreated) return "The commit is safely saved locally. Publishing still needs attention; read the selected output for the next step.";
    if (result.phase === "merge" || result.recovery?.nextAction === "resolve-conflicts-or-abort") {
      return "Integration paused because files conflict. Resolve and stage them, then commit—or abort the merge safely.";
    }
    if (["rollback", "tracking-cleanup"].includes(result.phase)) {
      return firstLine(result.output) || "The operation completed only partly. Use the recovery guidance before continuing.";
    }
    return firstLine(result.output) || "The operation completed only partly. Review the selected output before continuing.";
  }
  const publishedTeamBranch = result?.ok
    && ["push", "publishNewBranch", "commitStagedPush"].includes(payload.action)
    && context.branch
    && context.branch !== context.defaultBranch;
  if (publishedTeamBranch) return `Branch ${context.branch} is on GitHub. Next: open its pull request into ${context.defaultBranch}.`;
  return result?.ok ? actionLabel(result.command) : firstLine(result?.output);
}

async function runAction(payload, busyMessage = "Running Git safely…") {
  if (state.busy) return null;
  const context = {
    branch: String(state.summary?.branch || ""),
    defaultBranch: String(state.summary?.defaultBranch || "main")
  };
  setBusy(true, busyMessage);
  try {
    const result = await api("/api/action", payload);
    appendActivity(result);
    toast(actionResultMessage(result, payload, context), !result.ok);
    if (window.BranchlineActions.shouldClearCommitMessage(payload.action, result)) elements.commitMessageInput.value = "";
    if (result.ok && payload.action === "createBranch") elements.newBranchInput.value = "";
    const scope = window.BranchlineActions.refreshScope(result, payload.action);
    if (scope.local || scope.history || scope.branches || scope.full) { state.filePages.local.loaded = false; state.filePages.local.revision = ""; }
    if (scope.remote || scope.full) { state.filePages.github.loaded = false; state.filePages.github.revision = ""; }
    state.lastActivityAt = Date.now();
    state.stablePolls = 0;
    if (scope.full || scope.remote || scope.history || scope.branches) await refresh({ manageBusy: false });
    else if (scope.local) await refreshLocalFiles({ announce: false });
    return result;
  } catch (error) {
    const message = error.message || String(error);
    appendActivity({ ok: false, command: payload.action || "request", output: message });
    toast(message, true);
    markStateStale(message);
    return null;
  } finally {
    setBusy(false);
  }
}

async function pollLocalStatus() {
  const dialogOpen = Boolean(document.querySelector("dialog[open]"));
  const fileLoading = state.filePages.local.loading || state.filePages.github.loading;
  if (state.busy || state.refreshing || dialogOpen || fileLoading || document.visibilityState !== "visible") {
    scheduleLocalPoll(30000);
    return;
  }
  try {
    const local = await api("/api/local-status");
    const duration = Number(local.scanDurationMs || Number(local.durationSeconds || 0) * 1000);
    if (!state.summary || Boolean(local.configured) !== Boolean(state.summary.isRepo)) {
      await refresh({ manageBusy: false });
    } else if (local.configured) {
      const applied = applyLocalStatus(local);
      if (applied.full) {
        state.lastActivityAt = Date.now();
        state.stablePolls = 0;
        await refresh({ manageBusy: false });
      } else if (applied.localChanged) {
        state.lastActivityAt = Date.now();
        state.stablePolls = 0;
        renderSummary();
      } else {
        state.stablePolls += 1;
        elements.lastUpdated.textContent = String(local.localScannedAt || "—").split(" ").pop();
        elements.localRefreshStatus.textContent = `${Number(local.changedCount || 0)} change${Number(local.changedCount || 0) === 1 ? "" : "s"} · ${Number(local.stagedCount || 0)} ready to commit · scanned ${String(local.localScannedAt || "now").split(" ").pop()}`;
      }
    }
    const recentlyActive = Date.now() - Number(state.lastActivityAt || 0) < 120000;
    state.pollDelay = duration > 750 || state.stablePolls >= 4 ? 60000 : recentlyActive ? 15000 : 30000;
  } catch (error) {
    state.pollDelay = 60000;
    markStateStale(error.message || String(error));
    window.BranchlineRender.announce(elements.liveStatus, error.message || String(error));
  } finally {
    scheduleLocalPoll();
  }
}

function currentCommit() {
  return elements.commitSelect.value || state.selectedCommit || "";
}

function currentBranch() {
  return elements.branchSelect.value || "";
}

function setOutputExpanded(expanded) {
  state.outputExpanded = Boolean(expanded);
  const panel = elements.outputDetail.closest(".output-panel");
  panel?.classList.toggle("is-expanded", state.outputExpanded);
  document.body.classList.toggle("output-is-expanded", state.outputExpanded);
  elements.toggleOutputButton.textContent = state.outputExpanded ? "Collapse" : "Expand";
  elements.toggleOutputButton.setAttribute("aria-expanded", String(state.outputExpanded));
  if (state.outputExpanded) elements.outputDetail.focus();
}

async function bringGitHubHere() {
  const remoteBranch = String(state.summary?.tracking?.remoteDefaultBranch || "");
  if (!remoteBranch) return toast("GitHub's default branch could not be determined.", true);
  if (!window.confirm(`Bring GitHub branch "${remoteBranch}" into this folder?\n\nExisting local files will be preserved. Missing GitHub files will be added, GitHub history will become the local base, and the staging area will be cleared for review.`)) return;
  await runAction({ action: "adoptRemote", confirm: `ADOPT_GITHUB:${remoteBranch}` }, "Bringing GitHub history here…");
}

async function repairUpstream() {
  const branch = String(state.summary?.branch || "");
  if (!branch) return toast("Create or switch to a named branch first.", true);
  if (!window.confirm(`Repair ${branch} so it tracks origin/${branch}?\n\nOnly the tracking pointer changes. Commits and files are untouched.`)) return;
  await runAction({ action: "repairUpstream", confirm: `REPAIR_UPSTREAM:${branch}` }, "Repairing branch tracking…");
}

async function publishNewBranch() {
  const branch = String(state.summary?.branch || "");
  if (!branch) return toast("Create a named branch first.", true);
  if (!window.confirm(`Create origin/${branch} on GitHub and publish this local branch?\n\nNo existing GitHub branch will be overwritten.`)) return;
  await runAction({ action: "publishNewBranch", confirm: `PUBLISH_NEW_BRANCH:${branch}` }, `Publishing new GitHub branch ${branch}…`);
}

async function createTeamBranch() {
  const branch = elements.newBranchInput.value.trim();
  if (!branch) return toast("Enter a short branch name such as feature/clear-name.", true);
  const summary = state.summary || {};
  const current = String(summary.branch || "");
  const defaultBranch = String(summary.defaultBranch || "main");
  const relationship = String(summary.tracking?.relationship || "");
  const hasLocalChanges = asArray(summary.changedFiles).length > 0;
  if (current === defaultBranch && !hasLocalChanges && ["behind", "diverged"].includes(relationship)) {
    setRepositoryView("github");
    showSyncGuide("receive");
    toast(`Update ${defaultBranch} from GitHub before creating ${branch}.`);
    return;
  }
  await runAction({ action: "createBranch", branch }, `Creating team branch ${branch}…`);
}

async function checkoutRemoteBranch() {
  const branch = elements.remoteBranchSelect.value || "";
  if (!branch) return;
  if (!window.confirm(`Create a local branch named ${branch}, track origin/${branch}, and switch to it?\n\nThe local working tree must be clean.`)) return;
  await runAction({ action: "checkoutRemoteBranch", branch, confirm: `TRACK_REMOTE:${branch}` }, `Bringing down origin/${branch}…`);
}

function installEvents() {
  window.BranchlineSyncGuideDialog = window.BranchlineA11y?.installDialog(elements.syncGuideDialog) || null;
  elements.refreshButton.addEventListener("click", () => refresh());
  elements.refreshLocalButton.addEventListener("click", () => refreshLocalFiles());
  elements.openRepositoryFolderButton.addEventListener("click", () => runAction({ action: "openRepositoryFolder" }, "Opening repository folder…"));
  elements.repairUpstreamButton.addEventListener("click", repairUpstream);
  elements.publishNewBranchButton.addEventListener("click", publishNewBranch);
  elements.themeButton.addEventListener("click", () => {
    const next = document.documentElement.dataset.theme === "dark" ? "light" : "dark";
    document.documentElement.dataset.theme = next;
    try { localStorage.setItem("branchline-theme", next); } catch { }
  });

  elements.useRepositoryButton.addEventListener("click", () => runAction({ action: "selectRepository", path: elements.repoPathInput.value.trim() }, "Opening repository…"));
  elements.initializeButton.addEventListener("click", async () => {
    const path = elements.repoPathInput.value.trim();
    if (!path) return toast("Choose a folder first.", true);
    if (!window.confirm(`Initialize a new Git repository inside:\n\n${path}\n\nNo branch will be renamed and no remote will be added.`)) return;
    await runAction({ action: "initializeRepository", path, confirm: "INITIALIZE" }, "Initializing repository…");
  });
  elements.cloneRepositoryButton.addEventListener("click", async () => {
    const path = elements.repoPathInput.value.trim();
    const remote = elements.remoteInput.value.trim();
    if (!path || !remote) return toast("Choose an empty folder and enter a GitHub repository URL first.", true);
    if (!window.confirm(`Clone this GitHub repository into the selected empty folder?\n\nGitHub: ${remote}\nFolder: ${path}`)) return;
    await runAction({ action: "cloneRepository", path, remote, confirm: "CLONE" }, "Cloning GitHub into the folder…");
  });
  elements.detachRepositoryButton.addEventListener("click", async () => {
    const name = String(state.summary?.repoName || "repository");
    const typed = window.prompt(`Turn this Git repository into a normal folder while keeping every project file?\n\nThe .git history will be moved to a recoverable Branchline backup.\n\nType DETACH ${name} to continue.`);
    if (typed !== `DETACH ${name}`) return;
    await runAction({ action: "detachRepository", confirm: `DETACH_GIT:${name}` }, "Detaching Git safely…");
  });
  elements.restoreGitButton.addEventListener("click", async () => {
    const backup = asArray(state.summary?.folder?.backups)[0]?.name || "";
    const path = String(state.summary?.selectedPath || "");
    if (!backup || !path) return toast("No recoverable Git history was found.", true);
    if (!window.confirm(`Restore Git history from ${backup}?\n\nAll current project files remain in place.`)) return;
    await runAction({ action: "restoreGitMetadata", path, backup, confirm: `RESTORE_GIT:${backup}` }, "Restoring Git history…");
  });
  elements.connectRemoteButton.addEventListener("click", async () => {
    const remote = elements.remoteInput.value.trim();
    if (!remote) return toast("Enter a GitHub repository URL first.", true);
    if (!window.confirm(`Set this repository's origin to:\n\n${remote}\n\nThe previous origin will be restored if fetching fails.`)) return;
    await runAction({ action: "configureRemote", remote, confirm: "CONNECT" }, "Validating GitHub origin…");
  });

  elements.fetchButton.addEventListener("click", () => runAction({ action: "fetch" }, "Fetching origin…"));
  elements.pullButton.addEventListener("click", async () => {
    const relationship = state.summary?.tracking?.relationship;
    const hasChanges = asArray(state.summary?.changedFiles).length > 0;
    const remoteReady = Boolean(state.summary?.remoteValid);
    const canReceive = state.summary?.stateOk !== false && remoteReady && (relationship === "local-empty" || (["behind", "diverged"].includes(relationship) && !hasChanges && !state.summary?.operation));
    if (!canReceive) {
      showSyncGuide("receive");
      return;
    }
    if (relationship === "local-empty") {
      await bringGitHubHere();
      return;
    }
    if (relationship === "diverged") {
      const branch = String(state.summary?.branch || "current branch");
      const ahead = Number(state.summary?.tracking?.ahead || 0);
      const behind = Number(state.summary?.tracking?.behind || 0);
      if (!window.confirm(`Integrate GitHub into ${branch}?\n\nThis creates a normal merge that preserves ${ahead} local and ${behind} GitHub commit${behind === 1 ? "" : "s"}. It never force-pushes or rewrites history.\n\nIf the same lines changed on both sides, Branchline will pause and show the conflict.`)) return;
      await runAction({ action: "integrateRemote", confirm: `MERGE_REMOTE:${branch}` }, "Integrating local and GitHub history…");
      return;
    }
    await runAction({ action: "pull" }, "Fast-forwarding safely…");
  });
  elements.pushButton.addEventListener("click", () => {
    const relationship = String(state.summary?.tracking?.relationship || "no-remote");
    const canPush = state.summary?.stateOk !== false && Boolean(state.summary?.remoteValid) && ["ahead", "unpublished", "remote-empty"].includes(relationship) && state.summary?.tracking?.hasLocalCommit;
    if (!canPush) {
      showSyncGuide("publish");
      return;
    }
    if (["unpublished", "remote-empty"].includes(relationship)) publishNewBranch();
    else runAction({ action: "push" }, "Publishing current branch…");
  });
  elements.syncGuidePrimaryButton.addEventListener("click", followSyncGuide);
  elements.githubLoginButton.addEventListener("click", () => runAction({ action: "githubLogin" }, "Opening GitHub sign-in…"));
  elements.resetLoginButton.addEventListener("click", async () => {
    if (!window.confirm("Remove the saved GitHub account for this origin and open a fresh sign-in?")) return;
    await runAction({ action: "githubResetLogin" }, "Resetting GitHub sign-in…");
  });

  elements.fileSearchInput.addEventListener("input", () => {
    state.fileQuery = elements.fileSearchInput.value;
    window.clearTimeout(state.searchTimer);
    state.searchTimer = window.setTimeout(() => {
      state.filePages.local.loaded = false;
      state.filePages.github.loaded = false;
      loadFilePage(state.activeRepositoryView, { offset: 0, announce: true });
    }, 250);
  });
  elements.localViewTab.addEventListener("click", () => setRepositoryView("local"));
  elements.githubViewTab.addEventListener("click", () => setRepositoryView("github"));
  window.BranchlineA11y?.installTabs(document.getElementById("repositoryTabs"), (tab) => setRepositoryView(tab === elements.githubViewTab ? "github" : "local"));
  elements.syncSwitchViewButton.addEventListener("click", () => setRepositoryView(state.activeRepositoryView === "github" ? "local" : "github"));
  elements.repoPathInput.addEventListener("input", updateAvailability);
  elements.remoteInput.addEventListener("input", updateAvailability);
  elements.commitMessageInput.addEventListener("input", updateAvailability);
  elements.commitSearchInput.addEventListener("input", () => {
    state.commitQuery = elements.commitSearchInput.value;
    renderCommits();
  });
  elements.commitSelect.addEventListener("change", () => setSelectedCommit(elements.commitSelect.value));
  elements.commitPrerequisiteButton.addEventListener("click", bringGitHubHere);
  elements.identityNameInput.addEventListener("input", updateAvailability);
  elements.identityEmailInput.addEventListener("input", updateAvailability);
  elements.saveIdentityButton.addEventListener("click", async () => {
    const result = await runAction({
      action: "setIdentity",
      name: elements.identityNameInput.value.trim(),
      email: elements.identityEmailInput.value.trim()
    }, "Saving commit identity…");
    if (result?.ok) elements.identityPanel.open = false;
  });

  elements.stageAllButton.addEventListener("click", async () => {
    if (!window.confirm("Stage every changed, deleted, and untracked file in this repository?")) return;
    await runAction({ action: "stageAll", confirm: "STAGE_ALL" }, "Staging all changes…");
  });
  elements.commitButton.addEventListener("click", () => runAction({ action: "commit", message: elements.commitMessageInput.value }, "Creating commit…"));
  elements.commitPushButton.addEventListener("click", async () => {
    const message = elements.commitMessageInput.value.trim();
    if (!message) return toast("Write a commit message first.", true);
    if (!window.confirm("Commit only the changes that are already staged, then publish the resulting local commit to GitHub?\n\nUnstaged changes will stay on this computer and will not be included.")) return;
    await runAction({ action: "commitStagedPush", message, confirm: "COMMIT_STAGED_PUSH" }, "Committing staged work and publishing…");
  });

  elements.createBranchButton.addEventListener("click", createTeamBranch);
  elements.switchBranchButton.addEventListener("click", () => runAction({ action: "switchBranch", branch: currentBranch() }, "Switching branch…"));
  elements.branchSelect.addEventListener("change", () => { updateBranchControls(); updateAvailability(); });
  elements.mergeSourceSelect.addEventListener("change", () => { updateBranchControls(); updateAvailability(); });
  elements.mergeTargetSelect.addEventListener("change", () => { updateBranchControls(); updateAvailability(); });
  elements.remoteBranchSelect.addEventListener("change", updateAvailability);
  elements.checkoutRemoteBranchButton.addEventListener("click", checkoutRemoteBranch);
  elements.mergeBranchButton.addEventListener("click", async () => {
    const source = elements.mergeSourceSelect.value || "";
    const target = elements.mergeTargetSelect.value || "";
    if (!source || !target || source === target) return;
    if (!window.confirm(`Merge source branch “${source}” into target branch “${target}”?\n\nBranchline will first switch to ${target}, then create a normal merge. The working tree must be clean. Nothing is force-merged or rewritten.`)) return;
    await runAction({ action: "mergeBranches", source, target, confirm: `MERGE_BRANCHES:${source}:${target}` }, `Merging ${source} into ${target}…`);
  });
  elements.deleteBranchButton.addEventListener("click", async () => {
    const branch = currentBranch();
    if (!branch) return;
    if (!window.confirm(`Delete the local branch “${branch}”? Unmerged branches will be refused.`)) return;
    await runAction({ action: "deleteBranch", branch, confirm: `DELETE:${branch}` }, `Deleting ${branch}…`);
  });

  elements.showCommitButton.addEventListener("click", () => runAction({ action: "showCommit", commit: currentCommit() }, "Inspecting commit…"));
  elements.restoreFromCommitButton.addEventListener("click", async () => {
    const commit = currentCommit();
    const file = state.selectedFile;
    if (!file) return toast("Select a file in the working tree first.", true);
    if (!window.confirm(`Restore “${file}” from commit ${commit.slice(0, 8)}? Current content in that file will be replaced.`)) return;
    await runAction({ action: "restoreFileFromCommit", file, commit, confirm: `RESTORE:${file}:${commit}` }, "Restoring historical file…");
  });
  elements.revertCommitButton.addEventListener("click", async () => {
    const commit = currentCommit();
    if (!commit) return;
    if (!window.confirm(`Create a new commit that reverts ${commit.slice(0, 8)}?`)) return;
    await runAction({ action: "revertCommit", commit, confirm: `REVERT:${commit}` }, "Reverting commit…");
  });
  elements.abortOperationButton.addEventListener("click", async () => {
    const operation = String(state.summary?.operation || "");
    if (!operation) return;
    if (!window.confirm(`Abort the interrupted ${operation} and restore its pre-operation state?`)) return;
    await runAction({ action: "abortOperation", confirm: `ABORT:${operation}` }, `Aborting ${operation}…`);
  });
  elements.resetCommitButton.addEventListener("click", async () => {
    const commit = currentCommit();
    if (!commit) return;
    const phrase = `RESET ${commit.slice(0, 8)}`;
    const typed = window.prompt(`A safety reference will be created first.\n\nType “${phrase}” to hard-reset the current branch.`);
    if (typed !== phrase) return;
    await runAction({ action: "resetToCommit", commit, confirm: `RESET:${commit}` }, "Creating safety reference and resetting…");
  });

  elements.localPreviousPageButton.addEventListener("click", () => loadFilePage("local", { offset: Math.max(0, state.filePages.local.offset - state.filePages.local.limit), announce: true }));
  elements.localNextPageButton.addEventListener("click", () => {
    if (state.filePages.local.nextOffset >= 0) loadFilePage("local", { offset: state.filePages.local.nextOffset, announce: true });
  });
  elements.githubPreviousPageButton.addEventListener("click", () => loadFilePage("github", { offset: Math.max(0, state.filePages.github.offset - state.filePages.github.limit), announce: true }));
  elements.githubNextPageButton.addEventListener("click", () => {
    if (state.filePages.github.nextOffset >= 0) loadFilePage("github", { offset: state.filePages.github.nextOffset, announce: true });
  });

  window.BranchlinePreviewDialog = window.BranchlineA11y?.installDialog(elements.filePreviewDialog) || null;
  window.BranchlineA11y?.installTabs(elements.filePreviewTabs, (tab) => {
    state.previewMode = tab === elements.previewDiffTab ? "diff" : "content";
    renderFilePreview();
  });
  elements.previewContentTab.addEventListener("click", () => { state.previewMode = "content"; renderFilePreview(); });
  elements.previewDiffTab.addEventListener("click", () => { state.previewMode = "diff"; renderFilePreview(); });
  elements.closeFilePreviewButton.addEventListener("click", () => {
    if (window.BranchlinePreviewDialog) window.BranchlinePreviewDialog.close();
    else elements.filePreviewDialog.close();
  });

  elements.clearActivityButton.addEventListener("click", () => {
    state.activities = [];
    state.selectedActivityId = "";
    renderActivities();
  });
  elements.copyOutputButton.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(elements.outputDetail.dataset.copyText || elements.outputDetail.textContent || "");
      toast("Output copied.");
    } catch {
      toast("Clipboard access was not available.", true);
    }
  });
  elements.toggleOutputButton.addEventListener("click", () => setOutputExpanded(!state.outputExpanded));
  elements.outputDetail.addEventListener("click", () => setOutputExpanded(!state.outputExpanded));
  elements.outputDetail.addEventListener("keydown", (event) => {
    if (event.key === "Enter" || event.key === " ") {
      event.preventDefault();
      setOutputExpanded(!state.outputExpanded);
    }
  });
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && state.outputExpanded) setOutputExpanded(false);
  });
}

function restoreTheme() {
  let saved = "";
  try { saved = localStorage.getItem("branchline-theme") || ""; } catch { }
  if (saved === "dark" || saved === "light") {
    document.documentElement.dataset.theme = saved;
  } else if (window.matchMedia?.("(prefers-color-scheme: dark)").matches) {
    document.documentElement.dataset.theme = "dark";
  }
}

restoreTheme();
installEvents();
renderActivities();
refresh();
scheduleLocalPoll();

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible" && !state.busy) scheduleLocalPoll(0);
  else window.clearTimeout(state.pollTimer);
});
