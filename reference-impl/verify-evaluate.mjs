// 量潮众包 · 验收求值器（参考实现）
// 读取 02b-verifier-instance.json 的配方，对 evidence 逐条执行规则，
// 输出 valid 与 quality_score。用于演示「可机器判定」的验收标准。
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const recipe = JSON.parse(readFileSync(join(here, '..', '02b-verifier-instance.json'), 'utf8'));

// ---- 规则求值器（示意）----
// 归一化公司名/电话哈希：实际实现应接真实去重索引，这里用简单的本地索引 mock。
const crmLeadIndex = new Set(['91110108MA01ABC123']); // 已在CRM的主体

function normalizeCompany(s){ return (s || '').trim().toLowerCase(); }
function hashPhone(p){ return 'h_' + (p || '').replace(/[^\d]/g,'').slice(-4); }

function runHardRule(rule, ev, task) {
  const c = rule.condition;
  switch (rule.ruleId) {
    case 'dedupe_v1':
      // 同一主体不在既有CRM：公司统一码 或 归一化公司名 或 电话哈希 三者任一命中即重复
      const dup = crmLeadIndex.has(ev.companyUnifiedCode)
        || crmLeadIndex.has(normalizeCompany(ev.companyName))
        || crmLeadIndex.has(hashPhone(ev.contactPhone));
      return { pass: !dup, detail: dup ? 'duplicate in CRM' : 'ok' };
    case 'format_phone_v1':
      return { pass: /^1[3-9]\d{9}$|^0\d{9,11}$/.test(ev.contactPhone), detail: 'phone format' };
    case 'format_email_v1':
      return { pass: /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(ev.contactEmail), detail: 'email format' };
    case 'persona_v1': {
      const okIndustry = ev.industry === '制造业';
      const okScale = task.userPersona.scale.includes(ev.scale);
      const okRegion = task.coverage.includes(ev.region);
      return { pass: okIndustry && okScale && okRegion, detail: `industry=${okIndustry},scale=${okScale},region=${okRegion}` };
    }
    case 'timeliness_v1': {
      const windowMs = task.windowHours * 3600 * 1000;
      const within = (Date.now() - new Date(ev.capturedAt).getTime()) <= windowMs;
      return { pass: within, detail: 'within window' };
    }
    default:
      return { pass: true, detail: 'no-op' };
  }
}

// 软规则（意向）：不阻断硬性判定，但计入 quality_score
function runSoftRule(rule, ev) {
  if (rule.ruleId === 'intent_v1') {
    return { pass: ev.intentLevel !== 'none', detail: `intent=${ev.intentLevel}` };
  }
  return { pass: true, detail: 'no-op' };
}

function evaluate(ev, task, crmIndex = []) {
  crmIndex.forEach(x => crmLeadIndex.add(x));
  const hardResults = recipe.rules.filter(r => r.level === 'hard').map(r => runHardRule(r, ev, task));
  const softResults = recipe.rules.filter(r => r.level === 'soft').map(r => runSoftRule(r, ev));
  const allPass = [...hardResults, ...softResults].every(r => r.pass);
  // quality_score 示意
  const intentWeight = { high: 1, mid: 0.7, low: 0.4, none: 0 }[ev.intentLevel] || 0;
  const score = Math.round(intentWeight * 100) / 100;
  return { valid: allPass, quality_score: score, hardResults, softResults };
}

// ---- 样例 ----
const task = { title: '华东制造业线索包', userPersona: { scale: ['100-499人'] }, coverage: ['广东', '江苏', '上海'], windowHours: 72 };

const good = {
  contactName: '李四', contactPhone: '13800138000', contactEmail: 'li@corp.cn',
  companyName: '江苏制造有限公司', companyUnifiedCode: '91320100MA01NEW123',
  industry: '制造业', scale: '100-499人', region: '江苏',
  intentLevel: 'high', source: 'exhibition', capturedAt: new Date(Date.now() - 3600e3).toISOString(),
};
const dup = { ...good, contactPhone: '13800138001', companyName: '江苏制造有限公司', companyUnifiedCode: '91320100MA01NEW123' }; // 撞统一码(CRM)
const none = { ...good, contactPhone: '13800138002', companyUnifiedCode: '91320100MA01NEW456', intentLevel: 'none' };

console.log('=== 样例1 有效线索 (good) ==='); console.log(JSON.stringify(evaluate(good, task), null, 2));
console.log('\n=== 样例2 重复线索 (dedupe fail) ==='); console.log(JSON.stringify(evaluate(dup, task, ['91320100MA01NEW123']), null, 2)); // 该主体已在CRM
console.log('\n=== 样例3 无意向 (soft fail) ==='); console.log(JSON.stringify(evaluate(none, task), null, 2));
