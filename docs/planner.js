/**
 * 웹 페이스 플래너.
 *
 * 앱과 같은 v4 데이터(`/pace/manifest.json` → `/pace/v4/<version>/<division>.json`)를
 * 읽어 목표 완주 시간을 구간별 목표로 나눈다. 계산은 전부 브라우저 안에서 끝나고
 * 서버로 아무것도 보내지 않는다.
 */
(function () {
  "use strict";

  var MANIFEST_URL = "./pace/manifest.json";
  var DIVISION_NAMES = {
    menOpenSingle: "Men's Open — Singles",
    menProSingle: "Men's Pro — Singles",
    womenOpenSingle: "Women's Open — Singles",
    womenProSingle: "Women's Pro — Singles",
    menOpenDouble: "Men's Open — Doubles",
    menProDouble: "Men's Pro — Doubles",
    womenOpenDouble: "Women's Open — Doubles",
    womenProDouble: "Women's Pro — Doubles",
    mixedDouble: "Mixed — Doubles"
  };
  var STATION_NAMES = {
    skiErg: "SkiErg 1000m",
    sledPush: "Sled Push 50m",
    sledPull: "Sled Pull 50m",
    burpeeBroadJumps: "Burpee Broad Jumps 80m",
    rowing: "Row 1000m",
    farmersCarry: "Farmers Carry 200m",
    sandbagLunges: "Sandbag Lunges 100m",
    wallBalls: "Wall Balls"
  };
  var STATION_ORDER = [
    "skiErg", "sledPush", "sledPull", "burpeeBroadJumps",
    "rowing", "farmersCarry", "sandbagLunges", "wallBalls"
  ];

  var datasets = {};
  var manifest = null;
  var els = {};

  function $(id) { return document.getElementById(id); }

  function t(key, fallback) {
    var node = document.querySelector('[data-i18n="' + key + '"]');
    return (node && node.textContent.trim()) || fallback || key;
  }

  function parseGoal(text) {
    var parts = String(text || "").trim().split(":").map(function (p) { return p.trim(); });
    if (parts.some(function (p) { return p === "" || !/^\d+$/.test(p); })) return null;
    var seconds = 0;
    if (parts.length === 3) {
      seconds = Number(parts[0]) * 3600 + Number(parts[1]) * 60 + Number(parts[2]);
    } else if (parts.length === 2) {
      seconds = Number(parts[0]) * 60 + Number(parts[1]);
    } else if (parts.length === 1) {
      seconds = Number(parts[0]) * 60;
    } else {
      return null;
    }
    return seconds > 0 ? seconds : null;
  }

  function formatSeconds(total) {
    var s = Math.max(0, Math.round(total));
    var h = Math.floor(s / 3600);
    var m = Math.floor((s % 3600) / 60);
    var sec = s % 60;
    var mm = (h > 0 && m < 10) ? "0" + m : String(m);
    var ss = sec < 10 ? "0" + sec : String(sec);
    return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
  }

  /** 단조 증가 배열에서 값의 위치를 선형 보간한다. */
  function interpolate(xs, ys, x) {
    if (!xs.length) return null;
    if (x <= xs[0]) return { value: ys[0], clamped: x < xs[0] };
    var last = xs.length - 1;
    if (x >= xs[last]) return { value: ys[last], clamped: x > xs[last] };
    for (var i = 1; i <= last; i += 1) {
      if (x <= xs[i]) {
        var span = xs[i] - xs[i - 1];
        var ratio = span === 0 ? 0 : (x - xs[i - 1]) / span;
        return { value: ys[i - 1] + (ys[i] - ys[i - 1]) * ratio, clamped: false };
      }
    }
    return { value: ys[last], clamped: false };
  }

  function componentsAt(dataset, percentile) {
    var grid = dataset.grid_p;
    var runRox = interpolate(grid, dataset.components.run_rox_s, percentile).value;
    var stations = {};
    STATION_ORDER.forEach(function (key) {
      var series = dataset.components.stations_s[key];
      stations[key] = series ? interpolate(grid, series, percentile).value : 0;
    });
    return { runRox: runRox, stations: stations };
  }

  function buildPlan(dataset, goalSeconds) {
    var p = interpolate(dataset.overall_s, dataset.grid_p, goalSeconds);
    var comps = componentsAt(dataset, p.value);
    var raw = comps.runRox + STATION_ORDER.reduce(function (sum, key) { return sum + comps.stations[key]; }, 0);
    // 보간값 합계를 사용자의 목표에 정확히 맞춘다.
    var scale = raw > 0 ? goalSeconds / raw : 1;
    var rows = [];
    var runRox = comps.runRox * scale;
    rows.push({ key: "runRox", name: t("planner.result.runblock", "Running + Roxzone"), seconds: runRox });
    STATION_ORDER.forEach(function (key) {
      rows.push({ key: key, name: STATION_NAMES[key], seconds: comps.stations[key] * scale });
    });
    return {
      percentile: p.value,
      clamped: p.clamped,
      rows: rows,
      total: goalSeconds,
      perBlock: runRox / 8
    };
  }

  function render(plan, dataset) {
    els.percentile.textContent = "top " + plan.percentile.toFixed(1) + "%";
    els.perBlock.textContent = formatSeconds(plan.perBlock);
    els.rangeWarning.hidden = !plan.clamped;

    els.rows.innerHTML = "";
    plan.rows.forEach(function (row) {
      var tr = document.createElement("tr");
      var name = document.createElement("td");
      name.textContent = row.name;
      var target = document.createElement("td");
      target.className = "planner-num";
      target.textContent = formatSeconds(row.seconds);
      var share = document.createElement("td");
      share.className = "planner-num";
      share.textContent = Math.round((row.seconds / plan.total) * 100) + "%";
      tr.appendChild(name);
      tr.appendChild(target);
      tr.appendChild(share);
      els.rows.appendChild(tr);
    });

    var totalRow = document.createElement("tr");
    totalRow.className = "planner-total-row";
    var totalName = document.createElement("td");
    totalName.textContent = t("planner.result.total", "Total");
    var totalValue = document.createElement("td");
    totalValue.className = "planner-num";
    totalValue.textContent = formatSeconds(plan.total);
    var totalShare = document.createElement("td");
    totalShare.className = "planner-num";
    totalShare.textContent = "100%";
    totalRow.appendChild(totalName);
    totalRow.appendChild(totalValue);
    totalRow.appendChild(totalShare);
    els.rows.appendChild(totalRow);

    var coverage = dataset.coverage || {};
    var seasons = coverage.seasons ? coverage.seasons.join("–") : "";
    var events = coverage.events ? coverage.events + " events" : "";
    var athletes = dataset.cleaning && dataset.cleaning.n_overall
      ? dataset.cleaning.n_overall.toLocaleString() + " results"
      : "";
    els.coverage.textContent = [seasons, events, athletes].filter(Boolean).join(" · ");
    els.result.hidden = false;
    els.status.hidden = true;
  }

  function fileNameFor(division) {
    if (!manifest) return null;
    for (var i = 0; i < manifest.files.length; i += 1) {
      var name = manifest.files[i].name;
      if (name.indexOf("/" + division + ".json") !== -1) return name;
    }
    return null;
  }

  function loadDataset(division) {
    if (datasets[division]) return Promise.resolve(datasets[division]);
    var name = fileNameFor(division);
    if (!name) return Promise.reject(new Error("unknown division"));
    return fetch("./pace/" + name).then(function (res) {
      if (!res.ok) throw new Error("http " + res.status);
      return res.json();
    }).then(function (json) {
      datasets[division] = json;
      return json;
    });
  }

  function calculate() {
    var division = els.division.value;
    var goal = parseGoal(els.goal.value);
    if (!goal) {
      els.status.hidden = false;
      els.status.textContent = t("planner.error", "Could not load the data.");
      return;
    }
    loadDataset(division).then(function (dataset) {
      render(buildPlan(dataset, goal), dataset);
    }).catch(function () {
      els.result.hidden = true;
      els.status.hidden = false;
      els.status.textContent = t("planner.error", "Could not load the data.");
    });
  }

  function start() {
    els = {
      division: $("planner-division"),
      goal: $("planner-goal"),
      submit: $("planner-submit"),
      status: $("planner-status"),
      result: $("planner-result"),
      percentile: $("planner-percentile"),
      perBlock: $("planner-perblock"),
      rangeWarning: $("planner-range-warning"),
      rows: $("planner-rows"),
      coverage: $("planner-coverage-value")
    };
    if (!els.division) return;

    Object.keys(DIVISION_NAMES).forEach(function (key) {
      var option = document.createElement("option");
      option.value = key;
      option.textContent = DIVISION_NAMES[key];
      els.division.appendChild(option);
    });

    els.submit.addEventListener("click", calculate);
    els.goal.addEventListener("keydown", function (event) {
      if (event.key === "Enter") calculate();
    });
    els.division.addEventListener("change", function () {
      if (!els.result.hidden) calculate();
    });

    fetch(MANIFEST_URL).then(function (res) {
      if (!res.ok) throw new Error("http " + res.status);
      return res.json();
    }).then(function (json) {
      manifest = json;
      calculate();
    }).catch(function () {
      els.status.textContent = t("planner.error", "Could not load the data.");
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
