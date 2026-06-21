// ---- helpers ---------------------------------------------------------
function fmtUptime(s) {
  const d = Math.floor(s / 86400);
  const h = Math.floor((s % 86400) / 3600);
  const m = Math.floor((s % 3600) / 60);
  return (d ? d + "d " : "") + h + "h " + m + "m";
}

function healthDotClass(pid, health) {
  if (pid === "dead" || pid === "down") return "down";
  if (pid === "pending") return "pending";
  if (health === "unhealthy") return "pending";
  return "up";
}

async function api(path, opts) {
  const res = await fetch(path, opts);
  let data = null;
  try { data = await res.json(); } catch (e) { /* no body */ }
  return { ok: res.ok, status: res.status, data };
}

// ---- vitals + services -------------------------------------------------
function render(data) {
  document.getElementById("uptime").textContent = fmtUptime(data.uptime_seconds || 0);
  document.getElementById("load").textContent = data.load || "-";

  if (data.battery && data.battery.percentage !== undefined) {
    document.getElementById("battery").textContent =
      data.battery.percentage + "% (" + data.battery.status + ")";
  } else {
    document.getElementById("battery").textContent = "n/a";
  }

  const total = data.mem_total_kb || 0;
  const used = data.mem_used_kb || 0;
  const pct = total ? Math.round((used / total) * 100) : 0;
  document.getElementById("mem-fill").style.width = pct + "%";
  document.getElementById("mem-text").textContent =
    (used / 1024 / 1024).toFixed(1) + "G / " + (total / 1024 / 1024).toFixed(1) + "G";

  const tbody = document.querySelector("#svc-table tbody");
  tbody.innerHTML = "";
  (data.services || []).forEach((svc) => {
    const tr = document.createElement("tr");
    const dotClass = healthDotClass(svc.pid, svc.health);
    const isUp = dotClass === "up" || dotClass === "pending";

    const nameTd = document.createElement("td");
    nameTd.innerHTML = '<span class="dot ' + dotClass + '"></span>' + svc.name;
    const typeTd = document.createElement("td"); typeTd.textContent = svc.type;
    const pidTd = document.createElement("td"); pidTd.textContent = svc.pid;
    const healthTd = document.createElement("td"); healthTd.textContent = svc.health;

    const actionsTd = document.createElement("td");
    actionsTd.className = "actions";
    actionsTd.appendChild(makeBtn(isUp ? "restart" : "start", () =>
      serviceAction(svc.name, isUp ? "restart" : "start")));
    if (svc.type === "longrun") {
      const stopBtn = makeBtn("stop", () => serviceAction(svc.name, "stop"));
      stopBtn.disabled = !isUp;
      actionsTd.appendChild(stopBtn);
    }
    actionsTd.appendChild(makeBtn("logs", () => openLog(svc.name)));

    tr.append(nameTd, typeTd, pidTd, healthTd, actionsTd);
    tbody.appendChild(tr);
  });
}

function makeBtn(label, onClick, variant) {
  const b = document.createElement("button");
  b.className = "btn" + (variant ? " btn-" + variant : "");
  b.textContent = label;
  b.addEventListener("click", onClick);
  return b;
}

async function serviceAction(name, action) {
  const { ok, data } = await api("/api/service/" + encodeURIComponent(name) + "/" + action, { method: "POST" });
  if (!ok) {
    console.error("service action failed:", data);
  }
  poll();
}

// ---- modules -----------------------------------------------------------
let pendingInstall = null;

async function loadModules() {
  const { ok, data } = await api("/api/modules");
  if (!ok || !data) return;
  const tbody = document.querySelector("#mod-table tbody");
  tbody.innerHTML = "";
  data.forEach((mod) => {
    const tr = document.createElement("tr");

    const nameTd = document.createElement("td"); nameTd.textContent = mod.name;
    const descTd = document.createElement("td"); descTd.textContent = mod.desc;

    const statusTd = document.createElement("td");
    const pill = document.createElement("span");
    const state = mod.status === "installing" ? "installing"
      : mod.status === "error" ? "error"
      : mod.installed ? "installed" : "not installed";
    pill.className = "status-pill" + (state !== "not installed" ? " " + state.replace(" ", "-") : "");
    pill.textContent = state;
    statusTd.appendChild(pill);

    const actionsTd = document.createElement("td");
    actionsTd.className = "actions";
    if (!mod.installed && mod.status !== "installing") {
      actionsTd.appendChild(makeBtn("install", () => requestInstall(mod.name), "primary"));
    }
    actionsTd.appendChild(makeBtn("logs", () => openLog(mod.name)));

    tr.append(nameTd, descTd, statusTd, actionsTd);
    tbody.appendChild(tr);
  });
}

function requestInstall(name) {
  pendingInstall = name;
  document.getElementById("confirm-text").textContent =
    "Install '" + name + "' now? This runs the module's package install " +
    "(may pull a meaningful download, e.g. metasploit is 1.5GB+).";
  document.getElementById("confirm-dialog").showModal();
}

document.addEventListener("DOMContentLoaded", () => {
  const dialog = document.getElementById("confirm-dialog");
  document.getElementById("confirm-cancel").addEventListener("click", () => {
    pendingInstall = null;
    dialog.close();
  });
  document.getElementById("confirm-ok").addEventListener("click", async () => {
    const name = pendingInstall;
    pendingInstall = null;
    dialog.close();
    if (!name) return;
    await api("/api/module/" + encodeURIComponent(name) + "/install", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ confirm: true }),
    });
    loadModules();
  });
  document.getElementById("log-close").addEventListener("click", closeLog);
});

// ---- log viewer ----------------------------------------------------------
let logTimer = null;
let activeLog = null;

async function openLog(name) {
  activeLog = name;
  document.getElementById("panel-logs").hidden = false;
  document.getElementById("log-name").textContent = name;
  await refreshLog();
  if (logTimer) clearInterval(logTimer);
  logTimer = setInterval(refreshLog, 2000);
  document.getElementById("panel-logs").scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function closeLog() {
  activeLog = null;
  if (logTimer) { clearInterval(logTimer); logTimer = null; }
  document.getElementById("panel-logs").hidden = true;
}

async function refreshLog() {
  if (!activeLog) return;
  const { ok, data } = await api("/api/logs/" + encodeURIComponent(activeLog));
  if (ok && data) {
    const body = document.getElementById("log-body");
    const wasAtBottom = body.scrollTop + body.clientHeight >= body.scrollHeight - 10;
    body.textContent = data.log || "(empty)";
    if (wasAtBottom) body.scrollTop = body.scrollHeight;
  }
}

// ---- polling loop --------------------------------------------------------
async function poll() {
  try {
    const res = await fetch("status.json?_=" + Date.now(), { cache: "no-store" });
    const data = await res.json();
    render(data);
    document.getElementById("conn-status").textContent =
      "live — last update " + new Date(data.updated * 1000).toLocaleTimeString();
    document.getElementById("conn-status").className = "online";
  } catch (e) {
    document.getElementById("conn-status").textContent = "disconnected — metrics service may be down";
    document.getElementById("conn-status").className = "offline";
  }
}

function tickClock() {
  document.getElementById("clock").textContent = new Date().toLocaleTimeString();
}

setInterval(poll, 2000);
setInterval(tickClock, 1000);
setInterval(loadModules, 5000);
poll();
tickClock();
loadModules();
