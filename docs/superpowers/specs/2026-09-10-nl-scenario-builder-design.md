# Natural-Language Scenario Builder — Design

**Date:** 2026-09-10
**Status:** Approved design, pending implementation plan
**Phase 1 scope:** Parse plain-language what-if questions into the existing
deterministic projection engine, and explain the results.

---

## 1. Purpose

Let a user describe a retirement what-if in plain language:

> "What if I retire at 60 and take CPP at 70?"

The system extracts structured parameters, runs them through Tallyloot's
existing deterministic engine, and returns both the projection and a plain
language summary of what changed.

The model is used strictly for **language understanding in** and **explanation
out**. It performs no financial calculation.

### Project context

Tallyloot is pre-alpha with effectively no users. This feature is built as a
learning exercise and as a tool for forecasting the author's own retirement.
That framing is load-bearing throughout: it justifies storing raw input without
a retention policy, running LLM calls inline rather than queued, and building
only the instrumentation that can produce a real number at n=1.

---

## 2. Non-negotiable constraint

**The LLM is never the source of truth for a financial number.**

- It may extract *inputs* ("retiring at 60" → `retirement_age: 60`).
- It may narrate *outputs* the engine already computed.
- It must never compute a projection, balance, or tax figure.

This is enforced structurally, not by prompt instruction:

1. The parse step's output schema contains **only the eleven levers the engine
   implements**. A request the engine cannot model has nowhere to land except
   the `unrecognized_input` field.
2. The explain step receives only `Scenario::Comparison` — a structure whose
   every number originates in `Projection::Household`.

---

## 3. Scope decisions

### 3.1 Phase 1 uses existing levers only

The original spec's flagship example ("retire at 60 and buy a place in Kelowna
for $650k") is **not implementable**. There is no one-time-expense lever in
`Projection::Household`. A `properties` table exists in `db/schema.rb` with
mortgage, sale, and rental columns, but there is no `Property` model, no
association, and no projection code — it is orphaned schema.

Phase 1 therefore covers only levers the engine already runs. Out-of-scope
requests produce an explicit "I can't model one-time purchases yet" response
rather than a silently wrong projection.

### 3.2 A fresh Scenario layer, not an extension of WhatIf

`WhatIf` and `Simulation` are not extended. Both are slated for removal in a
separate PR. Consequently the new `Scenario` layer must cover the **union of
both pages' levers** so that removal loses no functionality.

`Projection::Household` — the actual financial engine — is reused unchanged.

### 3.3 Phase 2 is conversational scenario *refinement*, not onboarding

The original Phase 2 was conversational onboarding. At n=1 that feature would
be exercised once and never again. Phase 2 is instead multi-turn refinement of
a scenario, which exercises identical machinery (context replay, field
tracking, reference resolution) on something used regularly. See §13.

---

## 4. Architecture

```
"What if I retire at 60 and take CPP at 70?"
   |
   v  Ai::Client -> Scenario::Interpretation      [LLM, structured output]
   |     person references + lever names + values + confidence
   v
   |  Scenario::LeverSet.build                    [pure Ruby]
   |     resolve "self" -> User#17
   |     reject unknown levers
   |     delegate range checks to existing model validations
   v
   |  Confirmation UI                             [user reviews and edits]
   v
   |  Scenario::Draft + Projection::Household     [NO LLM INVOLVEMENT]
   |     -> Scenario::Comparison
   v
   |  Ai::Client -> Scenario::Narrative           [LLM, given computed numbers]
   v
   Chart + prose
```

### 4.1 Layering

```
DOMAIN — knows nothing about Anthropic, tests offline with no stubs
--------------------------------------------------------------------
Scenario                  AR aggregate root: raw_input, status, lifecycle
Scenario::Draft           container of freshly-loaded AR records (see §6)
Scenario::LeverSet        collection; #apply(draft), #diff(other)
Scenario::Lever::*        the eleven levers
Scenario::Interpretation  value object: proposed LeverSet, confidence,
                            leftover text; #ambiguous?, #clarifying_question
Scenario::Comparison      value object: baseline vs scenario deltas.
                            EVERY NUMBER COMPUTED BY Projection::Household
Scenario::Narrative       value object: summary + key_deltas
Scenario::PersonResolver  "self" / "spouse" / first name -> User

INFRASTRUCTURE — the only code aware Anthropic exists
--------------------------------------------------------------------
Ai::Client                single egress: HTTP, logging, budget, retries
Ai::Budget                monthly spend circuit breaker
Ai::Prompt::Interpretation   system prompt + JSON schema
Ai::Prompt::Narrative        system prompt + JSON schema

LlmCall                   AR: per-call instrumentation
```

**`Comparison` is the product; `Narrative` is decoration.** `Comparison` is a
complete, structured, useful answer on its own. If the API is down, the budget
is exhausted, or the explain call fails, the user still receives the full
comparison and loses only the prose. The core constraint of §2 is expressed as
architecture rather than as a rule someone must remember.

---

## 5. The lever catalogue

Eleven levers — the union of what `/what_if` and `/simulator` expose today.

| Scope | Lever | Target attribute |
|---|---|---|
| Person | `RetirementAge` | `user.retirement_age` |
| Person | `LifeExpectancy` | `user.life_expectancy` |
| Person | `MonthlySavings` | fans out across `user.accounts.contribution` |
| Person | `PensionStartAge` | fans out across `user.pensions.start_age` |
| Person | `EmploymentEndAge` | `user.employment.end_age` |
| Person | `EmploymentIncome` | `user.employment.annual_income` |
| Record | `AccountContribution` | `account.contribution` |
| Record | `CppStartAge` | `Benefit::Cpp#start_age` |
| Record | `OasStartAge` | `Benefit::Oas#start_age` |
| Household | `IncomeGoal` | `household.retirement_income_goal` |
| Household | `Glidepath` | `portfolio.glidepath_id` |

Each lever class exposes:

```ruby
def apply(draft)    # mutate the draft
def description     # plain-English, for the confirmation UI
def person          # nil for household-scope levers
```

`MonthlySavings` fans a monthly delta across the user's contributing accounts,
matching `WhatIf#accounts_params` behaviour: distribute `delta * 12` evenly
across accounts with a positive contribution, falling back to all accounts if
none contribute, and flooring each result at zero.

---

## 6. Scenario::Draft

### 6.1 The problem

The engine needs household records with a few values changed, run through a
projection, **without persisting anything**.

`Simulation` solves this with `dup` plus two manual repairs. Both repairs exist
to compensate for how the records are loaded, and both are avoidable.

**Problem 1 — `dup` erases the primary key.** Verified:

```
original.id=697784213    dup.id=nil
```

The engine matches records by id while walking years:

```ruby
# app/models/projection/household.rb:69
account = accounts.find { |a| a.id == ap.account_id }
```

With every dup carrying `id == nil`, `find` matches the **first account every
time**. All four accounts collapse into one identity: account 1 absorbs every
ending balance, accounts 2-4 are never written. The projection still runs and
still renders a chart. It is silently wrong.

`Simulation` repairs this with `d.id = account.id`.

**Problem 2 — associations re-query the database.** A dup'd pension still holds
`user_id`, so `pension.user` runs a query and returns the *original* user, not
the modified copy. `Simulation` repairs this with
`d.association(:user).target = sim_users_by_id[...]`.

Root cause: `Projection::Household.from_household` loads collections via
`has_many :through` (`household.accounts`, `household.pensions`). Through
associations do not set `inverse_of`. Verified:

```
household.pensions.first.user.equal?(matching household.users) => false
user.pensions.first.user.equal?(user)                          => true
```

Rails wires the association for free when records are loaded **from the users
down**. The manual repair compensates for a load path, not a language limit.

### 6.2 The solution

`Scenario::Draft` is a **container**, not a parallel model layer. It holds
ordinary `User`, `Account`, `Pension`, `Benefit`, `Employment`, and `Portfolio`
records, loaded fresh from the users down.

```ruby
class Scenario::Draft
  # Loads a household's object graph as an in-memory working copy.
  #
  # These records are deliberately never saved. Levers mutate them and
  # Projection::Household reads them. Nothing in this path calls save,
  # update, or destroy.
  #
  # Loaded via Household.includes(users: ...).find rather than from the caller's
  # household object, for two reasons:
  #
  #   1. Isolation. Household-scope levers mutate household.retirement_income_goal
  #      and portfolio.glidepath_id. Using the caller's objects leaks those
  #      mutations back into the request that asked for the projection.
  #
  #   2. Correctness. Household#terminal_year and #retired_as_of? read
  #      household.users. Eager-loading through the household makes that
  #      association the same objects the levers mutate, so both methods follow
  #      the draft instead of the database.
  #
  # inverse_of wires account.user / pension.user to the in-memory user, so no
  # association repair is needed and no record is duplicated.
  def self.from(household)
    new(Household.includes(users: %i[accounts pensions benefits employment])
                 .find(household.id))
  end

  def initialize(household) = @household = household

  attr_reader :household

  def users       = household.users.to_a
  def portfolio   = household.portfolio
  def accounts    = users.flat_map(&:accounts)
  def pensions    = users.flat_map(&:pensions)
  def benefits    = users.flat_map(&:benefits)
  def employments = users.filter_map(&:employment)
  def user(id)    = users.find { |u| u.id == id }

  def to_projection
    Projection::Household.new(
      household:, portfolio:, users:, accounts:, pensions:, benefits:, employments:
    )
  end
end
```

Verified end to end against the real engine with the `non_retired` fixture:

```
periods generated                => 37
distinct account ids in period 1 => 4 of 4 accounts
terminal_year follows a mutated draft life_expectancy  => 2063 -> 2081
retired_as_of? follows a mutated draft retirement_age  => false -> true
caller isolation: draft.portfolio.equal?(caller.portfolio) => false
caller isolation: DB values unchanged after all mutations  => true
```

Four distinct accounts, not one account four times. No `dup`, no id
reassignment, no association repair.

**Passing the caller's `household` and `portfolio` was verified to be wrong** and
is the reason for the eager-load above. Mutating `household.retirement_income_goal`
or `portfolio.glidepath_id` on the caller's objects is visible to the caller
immediately, and a plain `Household.find` ignores draft users entirely — its
`terminal_year` returned 2063 where the draft implied 2081.

### 6.3 Rejected alternatives

**`dup` + reassign id (what `Simulation` does).** Rejected: every new lever
touching a new association requires manual target wiring, and getting it wrong
produces a plausible wrong chart rather than an error. Silent-and-wrong is the
worst failure mode for a financial tool.

**`readonly!` on the whole graph.** Verified to work — `save!`, `update!`,
`update_column`, `update_columns`, and `destroy` all raise `ReadOnlyRecord`;
`delete` bypasses it; in-memory mutation stays allowed. Deferred rather than
rejected: nothing in the projection path calls `save`, this is a single-engineer
pre-alpha project, and it is a one-line addition to `Draft.from` the day it
feels warranted. Note it does **not** cascade — neither `.each(&:readonly!)` on
users nor relation-level `.readonly` reaches included associations, so it would
have to mark every record in the graph explicitly.

**Parallel `ActiveModel` domain objects.** The theoretically correct answer —
value objects with no persistence semantics, matching the "functional core,
imperative shell" pattern. Rejected for now because it requires a parallel class
hierarchy (`Scenario::Account::Rrsp` alongside `Account::Rrsp`, and four more
STI siblings). Attributes could be derived from the schema and behaviour shared
via extracted rule modules, but the class skeleton cannot be deduplicated: every
future account type would need adding in two places, failing only in scenarios
and not on the dashboard. That is a permanent tax on the model layer paid to
support one feature.

**Transaction + rollback.** Rejected: SQLite has a single writer, so scenario
runs would serialize against all other writes, and baseline and scenario cannot
be held simultaneously for comparison.

`Scenario::Draft` remains the seam where a pure value-object boundary would be
introduced if the engine ever needs one — most likely trigger being Monte Carlo
simulation, where AR object allocation becomes prohibitive.

### 6.4 Known latent issue (out of scope)

`Projection::Household.from_household` passes `household.employments.includes(:user)`
but has no `includes` for accounts, pensions, or benefits, while
`Pension#start_year` and `Benefit#start_year` both call `user.birth_year`. That
is an N+1 on the baseline path. Loading from the users down avoids it in the
scenario path. Fixing `from_household` itself is deliberately excluded here —
it is called by `/dashboard`, `/projection`, `/simulator`, `/what_if`, and
`/try`, a blast radius this feature does not justify.

---

## 7. Person resolution

The model emits `"self"`, `"spouse"`, or a first name. Database IDs never appear
in a prompt, in either direction.

```ruby
Scenario::PersonResolver.new(household, current_user).resolve("spouse")
```

- `"self"` → the authenticated user
- `"spouse"` → the other household member; raises `AmbiguousPersonError` if
  there are zero or more than one
- a name → case-insensitive match on `first_name`; raises if no unique match

Any raise becomes a clarifying question rather than an error page.

---

## 8. Validation gates

Four gates between parse and engine, in order. Failing any gate produces a
clarifying question instead of a projection.

1. **Schema conformance.** Re-validated server-side even though structured
   output should guarantee it. Never trust the wire.
2. **Person resolution.** Per §7.
3. **Domain validity.** Apply the lever to the draft record and call `.valid?`.
   Existing model validations already enforce the ranges — `Benefit::Cpp`
   restricts `start_age` to 60-70, `Benefit::Oas` to 65-70, `User#retirement_age`
   and `#life_expectancy` to 0-120. The AI layer inherits these rather than
   restating them.
4. **Confidence.** Any lever with `confidence: low`, or a non-null
   `unrecognized_input`, triggers a clarifying question.

---

## 9. The AI layer

### 9.1 Dependency

Add `gem 'anthropic'` (official Ruby SDK). `ANTHROPIC_API_KEY` via `direnv` in
development (`.envrc`), Kamal secrets in production.

### 9.2 Model routing

Both steps use **Haiku 4.5** (`claude-haiku-4-5`). Both are bounded, structured,
low-reasoning tasks. `LlmCall#model` records which model handled each request so
any escalation to Sonnet 5 is a measured decision rather than a guess.

Cost: roughly 1,200 input / 150 output tokens per call, two calls per scenario,
at $1/$5 per million tokens — approximately **$0.004 per scenario**.

### 9.3 Structured output

The parse step constrains output to a fixed JSON schema so the model cannot
express a lever the engine does not implement:

```json
{
  "changes": [
    { "person": "self|spouse|<first name>",
      "lever": "<one of the eleven>",
      "value": 60,
      "confidence": "high|medium|low" }
  ],
  "unrecognized_input": "string | null"
}
```

The explain step is likewise constrained to `{summary, key_deltas: [{label,
from, to}]}` so the UI renders deltas rather than parsing prose.

**Implementation note:** the Ruby SDK is the least-documented Anthropic SDK. The
exact binding for `output_config.format` is to be verified against the SDK
repository during implementation rather than assumed. If it is not cleanly
exposed in Ruby, the fallback is tool use with `strict: true`, which is
equivalent for this purpose.

### 9.4 Prompt caching

The system prompt is byte-identical across requests and carries
`cache_control: {type: "ephemeral"}`. Household context (names and ages) goes
**after** the cached prefix, since it varies.

Caching requires a prefix of roughly 1,024 tokens or it silently does not cache.
Eleven lever descriptions will likely clear that, but this is confirmed by
observing `usage.cache_read_input_tokens`, not assumed.

### 9.5 Latency

Both calls run inline in the request cycle. At one user there is no thread
contention, and fewer moving parts means faster prompt iteration. If the explain
step later feels slow, moving it into a lazily-loaded Turbo Frame is a small,
self-contained change.

---

## 10. Persistence and instrumentation

```
scenarios
  household_id        references, not null
  raw_input           text, not null       (max 500 chars, see §11)
  parsed_levers       json                 (what the model extracted)
  confirmed_levers    json                 (what the user approved)
  status              string               parsed|clarifying|confirmed|rejected
  clarifying_question text, nullable
  confirmed_at        datetime, nullable
  timestamps

llm_calls
  scenario_id         references, nullable
  step                string               interpretation|narrative
  model               string
  input_tokens        integer
  output_tokens       integer
  cache_read_tokens   integer
  cost_micros         integer
  latency_ms          integer
  success             boolean
  error_message       text, nullable
  timestamps
```

`Household has_many :scenarios, dependent: :destroy`;
`Scenario has_many :llm_calls, dependent: :destroy`.

**Extraction accuracy** is `parsed_levers` vs `confirmed_levers`, computed on
read. Nothing is precomputed.

**Deliberate deviation from `CLAUDE.md`:** money is stored as integer dollars
throughout Tallyloot. `cost_micros` uses millionths of a dollar instead, because
these values are fractions of a cent. That convention governs user-facing
financial modelling, not internal telemetry.

**Storing unconfirmed data does not violate the original spec's non-goal.** That
non-goal prohibits writing to the user's *profile* before confirmation. Nothing
here writes to `users`, `accounts`, `benefits`, or any household record. A
staging row is what makes the confirmation gate auditable.

### 10.1 What is measured

Only metrics that produce a real number at n=1:

| Metric | Built |
|---|---|
| Cost per scenario | Yes |
| Model routing breakdown | Yes |
| Extraction accuracy | Yes |
| Adoption: NL vs manual | No — single user is 100% of both |
| Onboarding completion rate | No — n=1, one-time event |
| Time to complete | No — same |

A `rake scenarios:report` task ships **with** the tables. An unread log is pure
cost.

---

## 11. Spend controls

Seven layers, outermost first. The outer layers matter most because they hold
even if the application has a bug.

**0. Anthropic Console hard spend cap.** Configured outside the application, so
no code path can bypass it. Set before any implementation begins. This is the
actual backstop.

**1. Feature gate.** The strongest control is unreachability. Gated to
`Current.user.admin?` plus an explicit allowlist. A stranger reaching live
Tallyloot receives a 404, not a bill.

**2. Kill switch.** A cache-backed flag disabling the feature without a deploy.

**3. Budget circuit breaker.** `llm_calls` is already written for
instrumentation, so it doubles as enforcement:

```ruby
Ai::Budget.new(monthly_limit_micros: 20_000_000).exceeded?  # $20/month
```

Checked before every call. On exceed, the feature degrades to the manual path
with a plain message.

**4. Per-user rate limit.** Rails 8 native, backed by Solid Cache:

```ruby
rate_limit to: 10, within: 1.hour, by: -> { Current.user.id }, only: %i[create update]
```

**5. Input length cap.** `validates :raw_input, length: {maximum: 500}`. A pasted
document is the cheapest way to burn tokens.

**6. `max_tokens: 1024`.** A hard per-call output ceiling.

**7. No retries on 4xx.** Bounded retries on 5xx only. A retry loop on a
malformed request turns one bug into a hundred calls.

Worst realistic case with all layers: 10 calls/hour at ~$0.004 is about 4 cents
per hour per allowlisted user, hard-stopped at $20/month by layer 3 and again by
layer 0.

---

## 12. Surface

New and self-contained. `/what_if` and `/simulator` are untouched by this work.

```ruby
resources :scenarios, only: %i[index new create show update]
```

| Route | Action |
|---|---|
| `GET /scenarios/new` | text input |
| `POST /scenarios` | parse; render confirmation in a Turbo Frame |
| `PATCH /scenarios/:id` | confirm (with any user edits); run engine; render results |
| `GET /scenarios/:id` | results — chart plus narrative |
| `GET /scenarios` | history |

Element IDs follow the project convention: `scenario_123`,
`lever_retirement_age`. Styling uses existing Bulma classes.

---

## 13. Phase 2 preview — conversational refinement

Not specified in detail here; recorded so Phase 1 does not foreclose it.

```
"What if I retire at 60?"     -> retirement_age: 60
"and take CPP at 70?"          -> retirement_age: 60, cpp_start_age: 70
"actually make that 62"        -> retirement_age: 62, cpp_start_age: 70
```

Same parse/validate/confirm pattern across multiple turns. Because the API is
stateless, conversation history is stored and replayed on every call — this is
the state Phase 1's tables establish a pattern for.

Phase 2 will require a `scenario_turns` table, with `scenarios` becoming the
container and per-turn `raw_input` / `parsed_levers` moving into the child. That
migration is small and deliberately deferred: Phase 1 is single-turn and should
not carry multi-turn structure speculatively.

---

## 14. Testing

The suite must not depend on a non-deterministic external service.

- **Lever, Draft, and Comparison tests touch no API.** Pure fixtures. This is
  where financial correctness is proven, and it is the bulk of the suite.
- **Assert on the right quantity.** Post-retirement withdrawals are goal-based,
  so extra guaranteed income is offset by smaller withdrawals and
  `Period::Summary#income_amount` stays flat. Verified: moving CPP from 65 to 70
  left total income identical while `benefit_income` moved 29,220 -> 34,556 and
  net worth 959,904 -> 869,261 in 2056. Benefit, pension, and income-goal lever
  tests must assert on `benefit_income`, `net_worth`, or `adjusted_annual_amount`
  — never on `income_amount`.
- **Equivalence test:** the same levers run through `Simulation` and through
  `Scenario` must produce identical periods. This is the acceptance criterion
  for the new engine path and the precondition for removing `WhatIf` later.
- **Interpretation tests replay recorded JSON** from a stubbed `Ai::Client`.
  Deterministic, offline, fast.
- **One live test, skipped unless `LIVE_AI=1`.** Run by hand when changing
  prompts.
- **Controller and integration tests** stub `Ai::Client` entirely.
- **A `readonly` guard test is not included**, per §6.3. If `readonly!` is added
  later, a test asserting every record in a draft is readonly should come with
  it.

Per project convention, system tests remain limited to critical smoke paths;
everything here is covered by integration and model tests.

---

## 15. Build order

1. **`Scenario::Draft`, `Lever::*`, `LeverSet`, `PersonResolver`** — no AI.
   TDD. Verified against `Simulation` by the equivalence test.
2. **`LlmCall` + `Ai::Client` + `Ai::Budget`** — logging and spend controls
   before the first real call.
3. **`Ai::Prompt::Interpretation` + `Scenario::Interpretation` + validation
   gates** — script-driven, no UI.
4. **Controller, confirmation UI, engine wiring, `Scenario::Comparison`.**
5. **`Ai::Prompt::Narrative` + `Scenario::Narrative`.**
6. **`rake scenarios:report`.**

Step 1 is the largest single chunk and contains no AI at all. Step 3 will take
longer than it appears: compound sentences ("retire at 60 **and** take CPP at
70") are where extraction accuracy is won or lost, and the prompt will need
iteration.

---

## 16. Explicit non-goals

- No open-ended chat. Every interaction is scoped to a schema and a step.
- No LLM-performed math, tax calculation, or projection logic.
- No writing to the user's profile before confirmation.
- No replacement of the manual `/what_if` and `/simulator` paths in this work.
- No one-time expense or property modelling (§3.1).
- No changes to `Projection::Household` or `from_household` (§6.4).

---

## 17. Decision log

Recorded because several reversed an earlier position, and the reasoning matters
more than the conclusion.

| Decision | Reasoning |
|---|---|
| Phase 1 on existing levers only | The flagship example needs an engine lever that does not exist; `properties` is orphaned schema |
| Fresh `Scenario` layer, reuse `Projection::Household` | The engine is clean and tested; `WhatIf` is the crufty layer |
| Parse target is named levers with person references, not the params hash | A hash keyed on database IDs is an unsafe and awkward LLM target |
| `Draft` loads fresh, no `dup` | Reversed an earlier decision after probing: `inverse_of` and intact ids remove both manual repairs |
| `readonly!` deferred, not rejected | One line, adds real safety, but unnecessary at one engineer with no save in the path |
| ActiveModel domain objects rejected | Attributes and behaviour can be deduplicated; the parallel class skeleton cannot |
| Store raw input without a retention policy | Pre-alpha, single user, own data. Revisit before any real user reaches this feature |
| Instrumentation limited to n=1-meaningful metrics | Adoption and completion-rate comparisons need users; building the plumbing now means maintaining dead code |
| Phase 2 is refinement, not onboarding | Same learning value, on a surface actually used more than once |

---

## 18. Open risks

**Ruby SDK documentation.** The exact structured-output binding is unverified
(§9.3). Fallback identified.

**Compound sentence extraction.** The known weak point of the parse step (§15).
The extraction accuracy log exists precisely to measure it.

**Prompt cache minimum.** May not reach the ~1,024-token threshold; verify
empirically rather than assume (§9.4).

**Privacy posture is scoped to pre-alpha.** Storing raw financial free text
without retention or disclosure is acceptable for a single-user project and is
**not** acceptable once real users exist. Before opening this feature beyond the
allowlist: update `app/views/pages/privacy.html.erb` to disclose a third-party
AI processor, and decide on raw-text retention. Third-party disclosure is
required by the feature itself, independent of whether the log is kept.
