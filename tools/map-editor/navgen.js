(function (root) {
  "use strict";
  const ABOVE = 40, AIR = 375, STEP = 185, REACH = 650, CROSS_LINKS = 4, MERGE = 25, BRIDGE = 1400;

  const walkable = t => /Collision$/.test(t) && !/^(Lava|Dynamic|GameMode)/.test(t);
  const solid = t => /Collision$/.test(t) && !/^Dynamic/.test(t) && !/Soft/.test(t);

  function inside(px, py, solids) {
    let c = false;
    for (const s of solids) {
      if ((s.y1 > py) !== (s.y2 > py)) {
        const x = s.x1 + (py - s.y1) * (s.x2 - s.x1) / (s.y2 - s.y1);
        if (x > px) c = !c;
      }
    }
    return c;
  }
  function crosses(ax, ay, bx, by, s) {
    const d = (bx - ax) * (s.y2 - s.y1) - (by - ay) * (s.x2 - s.x1);
    if (Math.abs(d) < 1e-9) return false;
    const t = ((s.x1 - ax) * (s.y2 - s.y1) - (s.y1 - ay) * (s.x2 - s.x1)) / d;
    const u = ((s.x1 - ax) * (by - ay) - (s.y1 - ay) * (bx - ax)) / d;
    return t > 0.001 && t < 0.999 && u >= 0 && u <= 1;
  }
  const clear = (a, b, solids) => !solids.some(s => crosses(a.x, a.y, b.x, b.y, s));

  function generate(segments) {
    const solids = segments.filter(s => solid(s.tag));
    const floors = [];
    for (const s0 of segments) {
      if (!walkable(s0.tag)) continue;
      const s = s0.x1 <= s0.x2 ? s0 : { ...s0, x1: s0.x2, y1: s0.y2, x2: s0.x1, y2: s0.y1 };
      const dx = s.x2 - s.x1, dy = s.y2 - s.y1;
      if (dx < 60 || Math.abs(dy) > dx * 0.9) continue;
      const mx = (s.x1 + s.x2) / 2, my = (s.y1 + s.y2) / 2;
      if (solid(s.tag) && inside(mx, my - 15, solids)) continue;
      if (inside(mx, my - ABOVE, solids)) continue;
      floors.push({ ...s, soft: !solid(s.tag) });
    }
    const touches = (x, y, t) => Math.hypot(t.x1 - x, t.y1 - y) < 10 || Math.hypot(t.x2 - x, t.y2 - y) < 10;
    const other = (x, y, t) => Math.hypot(t.x1 - x, t.y1 - y) < 10 ? [t.x2, t.y2] : [t.x1, t.y1];
    function isLedge(f, x, y) {
      if (f.soft) return false;
      for (const g of floors) if (g !== f && touches(x, y, g)) return false;
      for (const s of solids) if (touches(x, y, s) && other(x, y, s)[1] < y - 10) return false;
      return true;
    }

    const nodes = [];
    const at = (x, y) => nodes.find(n => Math.hypot(n.x - x, n.y - y) < MERGE);
    function node(x, y, kind, floor) {
      if (inside(x, y, solids)) return null;
      const n = at(x, y);
      if (n) { n.floors.add(floor); if (kind === "L") n.kind = "L"; return n; }
      const m = { x, y, kind, floors: new Set([floor]), links: new Set() };
      nodes.push(m); return m;
    }
    function piece(start) {
      const got = new Set(start ? [start] : []), todo = start ? [start] : [];
      while (todo.length) for (const m of todo.pop().links) if (!got.has(m)) { got.add(m); todo.push(m); }
      return got;
    }
    const link = (a, b) => { if (a && b && a !== b) { a.links.add(b); b.links.add(a); } };

    floors.forEach((f, fi) => {
      const len = f.x2 - f.x1;
      const yAt = x => f.y1 + (f.y2 - f.y1) * (x - f.x1) / len;
      const leftLedge = isLedge(f, f.x1, f.y1), rightLedge = isLedge(f, f.x2, f.y2);
      const x0 = f.x1 + (leftLedge ? 0 : 30), x1 = f.x2 - (rightLedge ? 0 : 30);
      const count = x1 - x0 < 150 ? 1 : Math.max(2, Math.round((x1 - x0) / STEP) + 1);
      const ground = [];
      for (let i = 0; i < count; i++) {
        const x = count === 1 ? (x0 + x1) / 2 : x0 + (x1 - x0) * i / (count - 1);
        const ledge = count > 1 && ((i === 0 && leftLedge) || (i === count - 1 && rightLedge));
        const g = node(Math.round(x), Math.round(yAt(x) - ABOVE), ledge ? "L" : "", fi);
        if (g) ground.push(g);
      }
      if (!ground.length) return;
      const air = [];
      const pairs = ground.length === 1 ? [[ground[0], ground[0]]] : ground.slice(1).map((g, i) => [ground[i], g]);
      for (const [a, b] of pairs) {
        const p = { x: Math.round((a.x + b.x) / 2), y: Math.round(Math.min(a.y, b.y) + ABOVE - AIR) };
        air.push(inside(p.x, p.y, solids) || !clear(a, p, solids) || !clear(b, p, solids) ? null : node(p.x, p.y, "A", fi));
      }
      ground.forEach((g, i) => {
        for (const j of [i + 1, i + 2]) if (ground[j] && clear(g, ground[j], solids)) link(g, ground[j]);
        for (const k of [i - 2, i - 1, i, i + 1]) if (air[k] && clear(g, air[k], solids)) link(g, air[k]);
      });
      air.forEach((a, k) => { for (const j of [k + 1, k + 2]) if (a && air[j]) link(a, air[j]); });
    });

    for (const a of nodes) {
      const near = nodes
        .filter(b => b !== a && ![...b.floors].some(f => a.floors.has(f)))
        .map(b => [Math.hypot(a.x - b.x, a.y - b.y), b])
        .filter(([d, b]) => d <= REACH && clear(a, b, solids))
        .sort((p, q) => p[0] - q[0]).slice(0, CROSS_LINKS);
      for (const [, b] of near) link(a, b);
    }

    for (;;) {
      const part = piece(nodes[0]);
      if (!nodes.length || part.size === nodes.length) break;
      let best = null;
      for (const a of part) for (const b of nodes) {
        if (part.has(b)) continue;
        const d = Math.hypot(a.x - b.x, a.y - b.y);
        if (d <= BRIDGE && (!best || d < best[0]) && clear(a, b, solids)) best = [d, a, b];
      }
      if (!best) break;
      link(best[1], best[2]);
    }

    nodes.sort((a, b) => Math.min(...a.floors) - Math.min(...b.floors) || a.x - b.x || a.y - b.y);
    nodes.forEach((n, i) => { n.id = n.kind + (i + 1); });
    const seen = new Set(); let groups = 0;
    for (const n of nodes) if (!seen.has(n)) { groups++; for (const m of piece(n)) seen.add(m); }
    return {
      nodes: nodes.map(n => ({ id: n.id, x: n.x, y: n.y, links: [...n.links].map(m => m.id) })),
      floors: floors.length, groups,
    };
  }

  const api = { generate, inside };
  if (typeof module === "object" && module.exports) module.exports = api;
  else root.NavGen = api;
})(typeof window !== "undefined" ? window : globalThis);
