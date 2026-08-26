# 托管结算 · 状态机 + 唯一归因

## 1. 结算状态机（验收 → 打款）

```
submitted ──► under_review ──► accepted ──► locked ──► settled ──► released
                   │               │                            │
                   ▼               ▼                            ▼
               rejected        (可申诉) ──► disputed       escrow_ledger 记账
```

- **托管池：** 需求方（量潮）在发布任务时向 `budget_pool` **预缴保证金**，由平台托管。
- **释放规则：** 只有 `accepted` 才将对应金额从 `pool` 的 `locked → settled → released` 划给接单者；验收未通过则资金不流出。
- **分阶段：**
  - **线索费**：验收通过即结（`accepted → settled`），短周期。
  - **成交佣金**：确权（合同号 + 订单号 + 金额 + 付款凭证 + 财务复核）后结，长周期。
- **全流程流水** `escrow_ledger`（pseudo-code）对接单者可见，体现透明。

## 2. 唯一归因（已确认：成交唯一归属 + 线索分档激励）

| 费用 | 归属 | 备注 |
|---|---|---|
| 线索费 | 线索提交者 | 靠去重保证唯一；若同一主体重复提交，先到 + 证据链完整者优先 |
| 成交佣金 | 成交完成方 `closerId` | **唯一归属**，不按贡献加权 |
| 冲突 | 线索提交者 ≠ 成交完成方 | **两笔独立、互不挤占**：线索方拿线索费，成交方拿成交佣金 |

- 不采用「首触+最近触加权」：更公平但更复杂、更易扯皮，首期不做。
- 同一成交被多人申报：先到者 + 证据链完整者优先，其余进 `disputed`。

## 3. 出入金示例（线索费）

```
发布：量潮预缴 10,000 → pool(total=10000, locked=0, released=0)
接单：worker A 领取
提交：A 提交 5 条线索 evidence
验收：verification_runs → 4 条 valid、1 条 rejected(去重失败)
结算：accepted=4 × 50 元 = 200 → pool(locked=200) → settle → released=200
      worker A 应收 200；escrow_ledger 记一条出金
信誉：A.pass_rate 更新
```
