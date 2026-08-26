# 通用任务模型 · 生命周期状态机 + 任务类型插件

## 1. 生命周期状态机

```
            ┌────────────────────────────────────────────────┐
            ▼                                                │
 draft ──► published ──► applied ──► assigned ──► in_progress
            │                                             │
            │                                            ▼
            │                                      submitted
            │                                        │
            │                          ┌─────────────┴─────────────┐
            │                          ▼                           ▼
            │                    under_review                 (直接 rejected)
            │                          │
            │             ┌────────────┴────────────┐
            │             ▼                         ▼
            │        accepted                     rejected
            │             │                         │
            │             ▼                         ▼
            │        settled ──► closed          (可申诉) ──► disputed
            │                                        │
            └────────────── revoked / cancelled / archived（任一态可进入）
                                    └─────────────┘
```

**关键关口：** `submitted`（接单者声称完成）与 `accepted`（需求方/系统验收）是两个独立状态，**只有 `accepted` 放行到 `settled`**。这就是托管资金的心跳。

- `draft` → `published`：需求方发布任务（挂验收配方 + 定价表 + 托管池）
- `published` → `applied/assigned`：接单者领取或申请
- `in_progress` → `submitted`：接单者提交证据
- `submitted` → `under_review`：进入自动验收
- `under_review` → `accepted | rejected`：验收仅通过硬规则 + 软规则达标则 accepted，否则 rejected（带原因）
- `accepted` → `settled` → `closed`：从托管池划款，结算完成后关闭
- 任一态 → `disputed`：争议仲裁；`revoked / cancelled / archived` 由平台或需求方触发

## 2. 任务类型插件接口（最小可用）

每个任务类型是一份「元数据 + 钩子」，平台按类型加载。首期只实现 `lead_acquisition` 与 `deal`。

```ts
interface TaskType {
  key: string;                       // "lead_acquisition" | "deal"
  label: string;
  schema: TaskFieldSchema;           // 发布任务时需填写的字段定义
  verifier: VerifierRecipe;          // ← 验收配方（见 02）
  pricing: PricingModel;             // 定价表：metric/unit/price/conditions
  lifecycle: {
    onSubmitted?: (sub) => void;
    onAccepted?:   (sub) => void;
    onSettled?:    (sub) => void;
  };
}

interface PricingModel {
  metrics: PricingMetric[];          // 如「有效线索」「有效商机」「成交」
}
interface PricingMetric {
  key: string;
  unit: string;                      // 条 / 单 / %
  price: number | { percent: number };// 明码标价，写死
  conditions?: string[];             // 触发条件（引用验收结果）
}
```

## 3. 关键实体（与 04 数据模型对应）

`users` / `task_types` / `tasks` / `pricing_tables` / `budget_pools` / `escrow_ledger` /
`submissions` / `verification_runs` / `verification_rules` / `settlements` / `reputations` / `disputes`

详见 `04-data-model.sql`。
