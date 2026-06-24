'use strict';
// Adaptive provider policy for cc-prompt-rewriter's `~`-rewrite requests.
//
// Learns per-provider TTFT/latency and failure rate from OpenRouter's
// /generation endpoint, then demotes providers whose recent stats are
// consistently worse than the Tier-A baseline. The bundle patch requires()
// this module: buildProvider() shapes the routing object before each request,
// record() folds the outcome of a finished request back into rolling stats.
//
// IMPORTANT: only latency and hard failures are observable from the client.
// Output QUALITY — e.g. damage from aggressive quantization — cannot be
// measured here, so the blocklist (BLOCKED) is the only quality lever.

const fs = require('fs');
const path = require('path');
const os = require('os');

const STATS_PATH = path.join(os.homedir(), '.cc-prompt-rewriter', 'provider-stats.json');

// Static tiers — cheapest-good-first, mirroring the patch's default provider
// object. Tier-A is the baseline cohort that demotion decisions compare against.
const TIER_S = ['baidu'];
const TIER_A = ['deepseek', 'gmicloud', 'siliconflow', 'parasail', 'novita', 'akashml'];
const BLOCKED = ['deepinfra']; // hard block (4-bit / heavy quant), never routed

const MIN_SAMPLES = 4; // attributed requests needed before a provider is judged
const FAIL_RATIO_MAX = 0.4; // demote if >40% of recent requests failed
const LAT_FACTOR = 2.0; // demote if latency EWMA > baseline * this
const EWMA_ALPHA = 0.3;
const DEMOTE_MS = 6 * 60 * 60 * 1000; // a demotion lasts this long, then re-tries
const GEN_DELAY_MS = 1500; // /generation lags slightly behind stream end

const KNOWN = new Set([...TIER_S, ...TIER_A, ...BLOCKED]);

function readStats() {
  try {
    return JSON.parse(fs.readFileSync(STATS_PATH, 'utf8'));
  } catch (_) {
    return { providers: {} };
  }
}

function writeStats(s) {
  try {
    fs.mkdirSync(path.dirname(STATS_PATH), { recursive: true });
    fs.writeFileSync(STATS_PATH, JSON.stringify(s));
  } catch (_) {}
}

function ewma(prev, x) {
  return prev == null ? x : prev * (1 - EWMA_ALPHA) + x * EWMA_ALPHA;
}

// OpenRouter /generation returns a display name ("DeepInfra"); routing uses a
// slug ("deepinfra"). Normalize so the two line up for the providers we know.
function normalizeSlug(name) {
  return String(name || '')
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, '');
}

// Higher is better. Failures dominate; latency (ms) breaks ties.
function trust(p) {
  const failRatio = p && p.n ? p.fails / p.n : 0;
  const lat = (p && p.latEwma) || 0;
  return -(failRatio * 1000 + lat);
}

// Shape the routing object from the static tiers, demoting providers whose
// recent stats fall behind the Tier-A baseline. `baseJson` is the patch's
// static default (used for the non-order fields and as the ultimate fallback).
function buildProvider(baseJson) {
  let base;
  try {
    base = JSON.parse(baseJson);
  } catch (_) {
    base = {};
  }
  const stats = readStats();
  const now = Date.now();

  // Baseline = mean latency EWMA across Tier-A providers that have enough samples.
  const aLat = TIER_A.map((s) => stats.providers[s])
    .filter((p) => p && p.n >= MIN_SAMPLES && p.latEwma)
    .map((p) => p.latEwma);
  const baseline = aLat.length ? aLat.reduce((a, b) => a + b, 0) / aLat.length : null;

  const demoted = new Set(BLOCKED);
  for (const slug of Object.keys(stats.providers)) {
    const p = stats.providers[slug];
    if (p.demoteUntil && p.demoteUntil > now) {
      demoted.add(slug);
      continue;
    }
    if (!p.n || p.n < MIN_SAMPLES) continue;
    const failRatio = p.fails / p.n;
    const tooSlow = baseline != null && p.latEwma > baseline * LAT_FACTOR;
    if (failRatio > FAIL_RATIO_MAX || tooSlow) demoted.add(slug);
  }

  // Tier-S first (if healthy), then Tier-A ranked by trust, minus demoted.
  const ranked = TIER_A.filter((s) => !demoted.has(s)).sort(
    (a, b) => trust(stats.providers[b]) - trust(stats.providers[a])
  );
  let order = [...TIER_S.filter((s) => !demoted.has(s)), ...ranked];
  let ignore = Array.from(demoted);

  // Never route into the void: if soft demotions emptied the tiers, reset to the
  // full static tiers and keep only the hard blocklist — a demoted provider must
  // never appear in both `order` and `ignore`, and a working fallback beats none.
  if (order.length === 0) {
    const hard = new Set(BLOCKED);
    order = [...TIER_S, ...TIER_A].filter((s) => !hard.has(s));
    ignore = Array.from(hard);
  }

  return {
    order,
    allow_fallbacks: true,
    ignore,
    quantizations: base.quantizations || ['bf16', 'fp16', 'fp8', 'int8', 'fp6', 'unknown'],
    sort: base.sort || 'price',
    preferred_max_latency: base.preferred_max_latency || { p90: 5 },
  };
}

// Fire-and-forget: attribute a finished request to its serving provider via the
// /generation endpoint, then fold latency + ok/fail into rolling stats. Marks a
// provider demoted (with a TTL) once it crosses the failure/latency thresholds.
function record(opts) {
  const o = opts || {};
  if (!o.genId || !o.apiKey) return; // no attribution possible
  const root = (o.endpoint || 'https://openrouter.ai/api/v1/chat/completions').replace(
    /\/chat\/completions.*$/,
    ''
  );
  const url = root + '/generation?id=' + encodeURIComponent(o.genId);
  setTimeout(() => {
    fetch(url, { headers: { Authorization: 'Bearer ' + o.apiKey } })
      .then((r) => (r.ok ? r.json() : null))
      .then((j) => {
        const d = j && (j.data || j);
        const raw = d && (d.provider_name || d.provider);
        const slug = normalizeSlug(raw);
        if (!slug || !KNOWN.has(slug)) return; // only act on providers we route to
        // Prefer the server's reported latency; fall back to our measured TTFT.
        // Both track "slowness" monotonically enough for the baseline comparison.
        const lat = (d.latency != null ? d.latency : o.ttft) || 0;
        const stats = readStats();
        const p = stats.providers[slug] || { n: 0, fails: 0, latEwma: null };
        p.n += 1;
        if (!o.ok) p.fails += 1;
        if (lat) p.latEwma = ewma(p.latEwma, lat);
        p.lastSeen = Date.now();

        // Stamp/refresh a demotion TTL when thresholds are crossed; clear it once
        // the provider has enough fresh samples and is back under the limits.
        const failRatio = p.n ? p.fails / p.n : 0;
        const aLat = TIER_A.map((s) => stats.providers[s])
          .filter((q) => q && q.n >= MIN_SAMPLES && q.latEwma)
          .map((q) => q.latEwma);
        const baseline = aLat.length ? aLat.reduce((a, b) => a + b, 0) / aLat.length : null;
        const tooSlow = baseline != null && p.latEwma > baseline * LAT_FACTOR;
        if (p.n >= MIN_SAMPLES && (failRatio > FAIL_RATIO_MAX || tooSlow)) {
          p.demoteUntil = Date.now() + DEMOTE_MS;
        } else if (p.demoteUntil && p.demoteUntil <= Date.now()) {
          delete p.demoteUntil;
        }

        stats.providers[slug] = p;
        writeStats(stats);
      })
      .catch(() => {});
  }, GEN_DELAY_MS);
}

module.exports = { buildProvider, record, _internals: { normalizeSlug, trust, readStats } };
