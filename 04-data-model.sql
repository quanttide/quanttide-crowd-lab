-- 量潮众包平台 · 首期数据模型 (PostgreSQL)
-- 设计原则：accepted 是唯一放行到 settled 的关口；托管池只从 accepted 状态扣款。

CREATE TABLE users (
  id            BIGSERIAL PRIMARY KEY,
  role          TEXT NOT NULL CHECK (role IN ('requester','worker','platform')),
  display_name  TEXT NOT NULL,
  identity_no   TEXT,                      -- 实名/企业信息（可选，用于提现）
  status        TEXT NOT NULL DEFAULT 'active',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 任务类型注册表（插件化）
CREATE TABLE task_types (
  key             TEXT PRIMARY KEY,        -- 'lead_acquisition' | 'deal'
  label           TEXT NOT NULL,
  schema          JSONB NOT NULL,          -- TaskFieldSchema
  verifier_recipe JSONB NOT NULL,          -- VerifierRecipe（见 02）
  pricing_model   JSONB NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 托管预算池（需求方预缴保证金，平台托管）
CREATE TABLE budget_pools (
  id             BIGSERIAL PRIMARY KEY,
  requester_id   BIGINT NOT NULL REFERENCES users(id),
  task_id        BIGINT NOT NULL,          -- 关联任务
  total_funded   NUMERIC(14,2) NOT NULL DEFAULT 0,
  locked         NUMERIC(14,2) NOT NULL DEFAULT 0,   -- 已验收待释放
  released       NUMERIC(14,2) NOT NULL DEFAULT 0,   -- 已释放
  status         TEXT NOT NULL DEFAULT 'open',        -- open | depleted | closed
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 任务
CREATE TABLE tasks (
  id              BIGSERIAL PRIMARY KEY,
  type_key        TEXT NOT NULL REFERENCES task_types(key),
  title           TEXT NOT NULL,
  schema_data     JSONB NOT NULL,
  state           TEXT NOT NULL DEFAULT 'draft',
  creator_id      BIGINT NOT NULL REFERENCES users(id),
  budget_pool_id  BIGINT REFERENCES budget_pools(id),
  published_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 定价表（明码标价，写死）
CREATE TABLE pricing_tables (
  id         BIGSERIAL PRIMARY KEY,
  task_id    BIGINT NOT NULL REFERENCES tasks(id),
  metric_key TEXT NOT NULL,               -- 有效线索 / 有效商机 / 成交
  unit       TEXT NOT NULL,               -- 条 / 单 / %
  price      NUMERIC(14,2) NOT NULL,      -- 或 percent
  price_kind TEXT NOT NULL DEFAULT 'fixed' CHECK (price_kind IN ('fixed','percent')),
  conditions JSONB,                       -- 触发条件（引用验收结果）
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 接单者的交付物（证据）
CREATE TABLE submissions (
  id          BIGSERIAL PRIMARY KEY,
  task_id     BIGINT NOT NULL REFERENCES tasks(id),
  worker_id   BIGINT NOT NULL REFERENCES users(id),
  evidence    JSONB NOT NULL,             -- 依据 type.schema
  state       TEXT NOT NULL DEFAULT 'submitted',  -- submitted|under_review|accepted|rejected
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 验收规则（配方版本化，可追溯）
CREATE TABLE verification_rules (
  id            BIGSERIAL PRIMARY KEY,
  type_key      TEXT NOT NULL,
  rule_id       TEXT NOT NULL,
  level         TEXT NOT NULL CHECK (level IN ('hard','soft')),
  condition     JSONB NOT NULL,
  version       TEXT NOT NULL,
  active        BOOLEAN NOT NULL DEFAULT true,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 验收运行结果（每条 submission 一次）
CREATE TABLE verification_runs (
  id             BIGSERIAL PRIMARY KEY,
  submission_id  BIGINT NOT NULL REFERENCES submissions(id),
  rule_results   JSONB NOT NULL,          -- [{rule_id, pass, detail}]
  valid          BOOLEAN NOT NULL,
  quality_score  NUMERIC(6,3),
  verified_by    TEXT NOT NULL DEFAULT 'auto',  -- auto | reviewer | requester
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 结算（accepted → settled → released）
CREATE TABLE settlements (
  id            BIGSERIAL PRIMARY KEY,
  submission_id BIGINT NOT NULL REFERENCES submissions(id),
  worker_id     BIGINT NOT NULL REFERENCES users(id),
  metric_key    TEXT NOT NULL,
  amount        NUMERIC(14,2) NOT NULL,
  stage         TEXT NOT NULL DEFAULT 'accepted',  -- accepted|locked|settled|released
  pool_id       BIGINT REFERENCES budget_pools(id),
  settled_at    TIMESTAMPTZ,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 出金流水（透明可见）
CREATE TABLE escrow_ledger (
  id            BIGSERIAL PRIMARY KEY,
  pool_id       BIGINT NOT NULL REFERENCES budget_pools(id),
  tx_type       TEXT NOT NULL,            -- fund | lock | settle | release | refund
  amount        NUMERIC(14,2) NOT NULL,
  ref_id        BIGINT,                   -- 关联 settlement/submission
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 信誉
CREATE TABLE reputations (
  user_id       BIGINT PRIMARY KEY REFERENCES users(id),
  pass_rate     NUMERIC(6,4) NOT NULL DEFAULT 0,
  on_time_rate  NUMERIC(6,4) NOT NULL DEFAULT 0,
  dispute_rate  NUMERIC(6,4) NOT NULL DEFAULT 0,
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 争议
CREATE TABLE disputes (
  id            BIGSERIAL PRIMARY KEY,
  submission_id BIGINT NOT NULL REFERENCES submissions(id),
  claimant_id   BIGINT NOT NULL REFERENCES users(id),
  evidence      JSONB,
  state         TEXT NOT NULL DEFAULT 'open',  -- open|resolved|rejected
  resolution    TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
