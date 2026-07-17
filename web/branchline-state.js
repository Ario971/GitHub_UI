"use strict";

window.BranchlineState = Object.freeze({
  create() {
    return {
      summary: null,
      busy: false,
      refreshing: false,
      selectedFile: "",
      selectedCommit: "",
      activities: [],
      selectedActivityId: "",
      fileQuery: "",
      commitQuery: "",
      activeRepositoryView: "local",
      outputExpanded: false,
      syncGuideAction: "local-changes",
      filePages: {
        local: { items: [], offset: 0, limit: 100, total: 0, nextOffset: -1, query: "", revision: "", loaded: false, loading: false },
        github: { items: [], offset: 0, limit: 100, total: 0, nextOffset: -1, query: "", revision: "", loaded: false, loading: false }
      },
      preview: null,
      previewMode: "content",
      pollTimer: 0,
      pollDelay: 30000,
      lastActivityAt: 0,
      stablePolls: 0,
      stale: false,
      searchTimer: 0
    };
  }
});
