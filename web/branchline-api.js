"use strict";

(function exposeBranchlineApi(global) {
  const token = document.querySelector('meta[name="git-control-token"]')?.content || "";

  async function request(path, body) {
    const headers = { "X-Git-Control-Token": token };
    const options = {
      method: body === undefined ? "GET" : "POST",
      headers,
      cache: "no-store",
      credentials: "same-origin"
    };
    if (body !== undefined) {
      headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(body);
    }

    let response;
    try {
      response = await fetch(path, options);
    } catch {
      throw new Error("Branchline could not reach its local server. Start it again with RUN-BRANCHLINE.cmd, then refresh this page.");
    }
    let payload;
    try {
      payload = await response.json();
    } catch {
      payload = { ok: false, message: "The local server returned an unreadable response." };
    }
    if (!response.ok) throw new Error(payload.message || `Request failed with status ${response.status}.`);
    return payload;
  }

  global.BranchlineApi = Object.freeze({
    request,
    summary: () => request("/api/summary"),
    localStatus: () => request("/api/local-status"),
    action: (payload) => request("/api/action", payload)
  });
})(window);
