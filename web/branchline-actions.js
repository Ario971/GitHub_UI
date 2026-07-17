"use strict";

const remoteInvalidatingActions = new Set([
  "fetch", "pull", "integrateRemote", "configureRemote", "push",
  "publishNewBranch", "repairUpstream", "checkoutRemoteBranch"
]);

window.BranchlineActions = Object.freeze({
  shouldClearCommitMessage(action, result) {
    return Boolean((result?.ok || result?.commitCreated) && ["commit", "commitStagedPush"].includes(action));
  },
  invalidation(action) {
    if (["showCommit", "openRepositoryFolder"].includes(action)) return { local: false, github: false };
    return { local: true, github: remoteInvalidatingActions.has(action) };
  },
  refreshScope(result, action) {
    const provided = result?.refreshScope;
    if (provided && typeof provided === "object") {
      return {
        local: Boolean(provided.local),
        remote: Boolean(provided.remote),
        history: Boolean(provided.history),
        branches: Boolean(provided.branches),
        full: Boolean(provided.full)
      };
    }
    const fallback = this.invalidation(action);
    return { local: fallback.local, remote: fallback.github, history: fallback.local, branches: false, full: false };
  }
});
