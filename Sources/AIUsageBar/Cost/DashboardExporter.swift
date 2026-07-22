import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// Builds a self-contained HTML cost dashboard (data embedded as JSON, charts as
/// inline SVG, no network) and opens it in the default browser — a server-less
/// take on the "open in browser" surface.
enum DashboardExporter {

    /// Per-day project/model cost breakdown + budgets, so the page computes every
    /// window client-side. Project keys are display labels (via `projectLabel`).
    static func payload(events: [UsageEvent], budgets: [String: Double],
                        pricing: Pricing = .shared, cal: Calendar = .current) -> [String: Any] {
        var days: [String: [String: Any]] = [:]
        var ignore = Set<String>()
        let fmt = DateFormatter(); fmt.calendar = cal; fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        for e in events {
            let key = fmt.string(from: e.timestamp)
            let cost = pricing.cost(for: e, unpriced: &ignore)
            var day = days[key] ?? ["projects": [String: Double](), "models": [String: Double]()]
            var projects = day["projects"] as! [String: Double]
            var models = day["models"] as! [String: Double]
            projects[projectLabel(e.project), default: 0] += cost
            models[e.model, default: 0] += cost
            day["projects"] = projects; day["models"] = models
            days[key] = day
        }
        let budgetLabels = Dictionary(budgets.map { (projectLabel($0.key), $0.value) },
                                      uniquingKeysWith: +)
        return ["days": days, "budgets": budgetLabels, "currency": "USD"]
    }

    static func html(events: [UsageEvent], budgets: [String: Double]) -> String {
        let obj = payload(events: events, budgets: budgets)
        let json = (try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return template.replacingOccurrences(of: "/*__AUB_DATA__*/",
                                             with: "window.__AUB_DATA__ = \(json);")
    }

    /// Write to Application Support and open in the browser. Returns the file URL.
    @discardableResult
    static func writeAndOpen(events: [UsageEvent], budgets: [String: Double]) -> URL? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("cost-dashboard.html")
        do { try html(events: events, budgets: budgets).write(to: url, atomically: true, encoding: .utf8) }
        catch { return nil }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
        return url
    }

    /// Fully self-contained template. No external URLs, no `<script src>`, and
    /// inline SVG carries no `xmlns` (not needed in HTML). `render()` reads
    /// `window.__AUB_DATA__`. Keep the `/*__AUB_DATA__*/` token exact.
    static let template = ##"""
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <title>AI Usage · Cost</title>
    <style>
      :root{--bg:#FBFBFC;--surface:#fff;--s2:#F4F5F7;--s3:#EDEEF1;--border:#E5E6EB;
        --text:#191A1D;--dim:#63666E;--faint:#9B9EA7;--accent:#CF7A3C;--accentSoft:rgba(207,122,60,.12);
        --ok:#2FA268;--warn:#D9902A;--over:#DC5A50;
        --mono:ui-monospace,"SF Mono",Menlo,monospace;--ui:system-ui,-apple-system,"Segoe UI",sans-serif;
        --shadow:0 1px 2px rgba(20,20,30,.04),0 8px 24px rgba(20,20,30,.06);}
      @media (prefers-color-scheme:dark){:root{--bg:#141317;--surface:#1D1B21;--s2:#252229;--s3:#2E2A33;
        --border:#302C38;--text:#F1EFF4;--dim:#A6A1B0;--faint:#6E6979;--accent:#E5A15C;--accentSoft:rgba(229,161,92,.14);
        --ok:#43C68C;--warn:#EDB13F;--over:#EE746C;--shadow:0 1px 2px rgba(0,0,0,.3),0 10px 30px rgba(0,0,0,.35);}}
      *{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--text);font-family:var(--ui);line-height:1.45}
      .wrap{max-width:960px;margin:0 auto;padding:26px 22px 56px}
      .num{font-variant-numeric:tabular-nums;font-family:var(--mono)}
      .eyebrow{font-size:11px;letter-spacing:.09em;text-transform:uppercase;color:var(--faint);font-weight:600}
      .seg{display:inline-flex;background:var(--s2);border:1px solid var(--border);border-radius:10px;padding:3px;margin-bottom:18px}
      .seg button{font:inherit;font-size:12.5px;font-weight:550;color:var(--dim);border:0;background:transparent;padding:6px 12px;border-radius:7px;cursor:pointer}
      .seg button[aria-selected="true"]{background:var(--surface);color:var(--text);box-shadow:var(--shadow)}
      .hero{background:var(--surface);border:1px solid var(--border);border-radius:16px;padding:22px 24px;box-shadow:var(--shadow);margin-bottom:16px}
      .big{font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:44px;font-weight:600;letter-spacing:-.02em;line-height:1;color:var(--accent)}
      .chart{margin-top:18px}.chart svg{width:100%;height:112px;display:block}
      .bar{transition:height .4s ease}
      .cols{display:grid;grid-template-columns:1.3fr 1fr;gap:16px}
      @media (max-width:680px){.cols{grid-template-columns:1fr}.big{font-size:36px}}
      .panel{background:var(--surface);border:1px solid var(--border);border-radius:15px;padding:18px 19px;box-shadow:var(--shadow)}
      .panel h3{margin:0 0 12px;font-size:12px;letter-spacing:.08em;text-transform:uppercase;color:var(--faint);font-weight:650}
      .row{display:grid;grid-template-columns:1fr auto;gap:4px 12px;align-items:center;padding:8px 4px}
      .row .t{font-size:13.5px;font-weight:550;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
      .row .c{font-family:var(--mono);font-variant-numeric:tabular-nums;font-size:13.5px;font-weight:600}
      .budget{grid-column:1/-1;display:flex;align-items:center;gap:9px;margin-top:2px}
      .track{flex:1;height:6px;border-radius:4px;background:var(--s3);overflow:hidden}
      .fill{height:100%;border-radius:4px}
      .bpct{font-family:var(--mono);font-size:11px;color:var(--dim);min-width:118px;text-align:right}
      .mtrack{grid-column:1/-1;height:5px;border-radius:3px;background:var(--s3);overflow:hidden;margin-top:2px}
      .mfill{height:100%;border-radius:3px;background:var(--accent);opacity:.85}
      .foot{margin-top:24px;font-size:12px;color:var(--faint)}
    </style></head><body>
    <div class="wrap">
      <div class="eyebrow" style="margin-bottom:14px">AI Usage · Cost</div>
      <div class="seg" id="tabs"></div>
      <div class="hero">
        <div class="eyebrow" id="heroLabel">Total cost</div>
        <div class="big" id="total" style="margin-top:8px">$0.00</div>
        <div class="chart" id="chart"></div>
      </div>
      <div class="cols">
        <div class="panel"><h3>By project</h3><div id="projects"></div></div>
        <div class="panel"><h3>By model</h3><div id="models"></div></div>
      </div>
      <div class="foot">Local only — cost is computed from your own session files on this Mac.</div>
    </div>
    <script>/*__AUB_DATA__*/</script>
    <script>
    (function(){
      var D = window.__AUB_DATA__ || {days:{},budgets:{},currency:"USD"};
      var keys = Object.keys(D.days).sort();
      var latest = keys.length ? keys[keys.length-1] : null;
      var WINS = [["today","Today"],["7d","7 days"],["30d","30 days"],["month","Month"],["all","All"]];
      var win = "7d";
      function parse(k){var p=k.split("-");return new Date(+p[0],+p[1]-1,+p[2]);}
      var latestDate = latest ? parse(latest) : new Date();
      function inWin(k){
        if(!latest) return false;
        if(win==="today") return k===latest;
        if(win==="all") return true;
        if(win==="month") return k.slice(0,7)===latest.slice(0,7);
        var n = win==="7d"?7:30, from=new Date(latestDate); from.setDate(from.getDate()-(n-1));
        return parse(k)>=from;
      }
      function money(v){return "$"+v.toLocaleString("en-US",{minimumFractionDigits:2,maximumFractionDigits:2});}
      function monthSpend(){
        var mp={}, mk=latest?latest.slice(0,7):"";
        keys.forEach(function(k){ if(k.slice(0,7)!==mk) return;
          var pr=D.days[k].projects||{}; for(var p in pr) mp[p]=(mp[p]||0)+pr[p]; });
        return mp;
      }
      function agg(){
        var total=0, proj={}, models={}, series=[];
        keys.filter(inWin).forEach(function(k){
          var day=D.days[k], dc=0, pr=day.projects||{}, md=day.models||{};
          for(var p in pr){proj[p]=(proj[p]||0)+pr[p]; dc+=pr[p];}
          for(var m in md){models[m]=(models[m]||0)+md[m];}
          total+=dc; series.push({k:k,cost:dc});
        });
        return {total:total,proj:proj,models:models,series:series};
      }
      function barsSVG(series){
        var W=880,H=112,n=series.length; if(!n) return "";
        var gap=n>20?2:4, bw=(W-(n-1)*gap)/n, max=0.001;
        series.forEach(function(s){max=Math.max(max,s.cost);});
        var out="";
        series.forEach(function(s,i){
          var h=Math.max(s.cost>0?3:0, s.cost/max*(H-12)), x=i*(bw+gap), y=H-h, last=i===n-1;
          out+='<rect class="bar" x="'+x.toFixed(1)+'" y="'+y.toFixed(1)+'" width="'+bw.toFixed(1)+'" height="'+h.toFixed(1)+'" rx="'+Math.min(3,bw/2).toFixed(1)+'" fill="'+(last?"var(--accent)":"var(--accentSoft)")+'" stroke="'+(last?"none":"var(--accent)")+'" stroke-opacity="'+(last?0:.35)+'"><title>'+s.k+' · '+money(s.cost)+'</title></rect>';
        });
        return '<svg viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="none"><line x1="0" y1="'+(H-0.5)+'" x2="'+W+'" y2="'+(H-0.5)+'" stroke="var(--border)"></line>'+out+'</svg>';
      }
      function budgetColor(f){return f>=1?"var(--over)":f>=0.8?"var(--warn)":"var(--ok)";}
      function render(){
        var a=agg(), ms=monthSpend();
        document.getElementById("tabs").innerHTML = WINS.map(function(w){
          return '<button data-w="'+w[0]+'" aria-selected="'+(w[0]===win)+'">'+w[1]+'</button>';}).join("");
        Array.prototype.forEach.call(document.querySelectorAll("#tabs button"),function(b){
          b.onclick=function(){win=b.getAttribute("data-w"); render();};});
        var wl = WINS.filter(function(w){return w[0]===win;})[0][1];
        document.getElementById("heroLabel").textContent = "Total cost · "+wl;
        document.getElementById("total").textContent = money(a.total);
        document.getElementById("chart").innerHTML = barsSVG(a.series);
        var projSorted = Object.keys(a.proj).sort(function(x,y){return a.proj[y]-a.proj[x];});
        document.getElementById("projects").innerHTML = projSorted.map(function(p){
          var cost=a.proj[p], lim=(D.budgets||{})[p], b="";
          if(lim){var spent=ms[p]||0, f=lim>0?spent/lim:0, pct=Math.round(f*100);
            b='<div class="budget"><div class="track"><div class="fill" style="width:'+Math.min(100,pct)+'%;background:'+budgetColor(f)+'"></div></div>'+
              '<div class="bpct">'+money(spent)+' / '+money(lim)+' · '+pct+'%</div></div>';}
          return '<div class="row"><div class="t">'+p+'</div><div class="c">'+money(cost)+'</div>'+b+'</div>';
        }).join("") || '<div class="row"><div class="t" style="color:var(--faint)">No spend</div></div>';
        var mSorted = Object.keys(a.models).sort(function(x,y){return a.models[y]-a.models[x];});
        var mMax=0.001; mSorted.forEach(function(m){mMax=Math.max(mMax,a.models[m]);});
        document.getElementById("models").innerHTML = mSorted.slice(0,6).map(function(m){
          return '<div class="row"><div class="t">'+m+'</div><div class="c">'+money(a.models[m])+'</div>'+
            '<div class="mtrack"><div class="mfill" style="width:'+(a.models[m]/mMax*100).toFixed(0)+'%"></div></div></div>';
        }).join("") || '<div class="row"><div class="t" style="color:var(--faint)">No spend</div></div>';
      }
      render();
    })();
    </script>
    </body></html>
    """##
}
