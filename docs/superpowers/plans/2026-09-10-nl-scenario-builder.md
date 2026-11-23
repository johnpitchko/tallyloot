# Natural-Language Scenario Builder Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a user type a plain-language what-if ("what if I retire at 60 and take CPP at 70?"), have it parsed into structured levers, confirmed, run through Tallyloot's existing deterministic projection engine, and explained in prose.

**Architecture:** A new `Scenario` layer converts named levers into a mutated in-memory copy of a household's records (`Scenario::Draft`) and feeds them to the untouched `Projection::Household`. Claude is used only at the edges — text to levers on the way in, computed numbers to prose on the way out — and never computes a financial figure. Tasks 1-10 contain no AI at all.

**Tech Stack:** Rails 8.0.5.1, Ruby 3.4.6, SQLite, Minitest, Hotwire (Turbo/Stimulus), Bulma, `anthropic` Ruby SDK, Claude Haiku 4.5.

**Spec:** `docs/superpowers/specs/2026-09-10-nl-scenario-builder-design.md`

## Global Constraints

- **Branch:** all work happens on a feature branch. Never commit to `main`.
- **No Claude references in commit messages.**
- **Money is stored as integer dollars** everywhere except `llm_calls.cost_micros`, which is millionths of a dollar (documented deviation — these values are fractions of a cent).
- **Percentages** are decimals, e.g. 75% is `0.75`.
- **HTML elements get `id` attributes.** For records, include the record id: `scenario_123`, `lever_retirement_age`.
- **Bulma classes first.** Only write custom CSS when no Bulma class fits.
- **Single quotes** unless interpolating. Trailing commas in multi-line literals. 120-char lines. Run `bin/rubocop -a` before every commit.
- **The LLM never produces a financial number.** Every figure displayed must originate in `Projection::Household`.
- **Never assert on `Period::Summary#income_amount`** to prove a benefit/pension/goal lever worked. Post-retirement withdrawals are goal-based and absorb the change. Assert on `benefit_income`, `net_worth`, or `adjusted_annual_amount`.
- **No test may call the Anthropic API** except the one explicitly gated behind `LIVE_AI=1`.
- **Tests run with:** `bin/rails test path/to/test.rb` or `bin/rails test path/to/test.rb:LINE`.

## Fixture Reference

The `non_retired` household (`households(:non_retired)`) is used throughout. Memorise this:

| Fixture | Detail |
|---|---|
| `households(:non_retired)` | Smith, `retirement_income_goal: 120000`, no province |
| `users(:working_user_john)` | John Worker, born 1980-01-01, `retirement_age: 65`, `life_expectancy: 82` |
| `users(:working_user_jane)` | Jane Worker, born 1981-01-01, `retirement_age: 65`, `life_expectancy: 82` |
| `accounts(:tfsa_john)` | `Account::Tfsa`, balance 100000, contribution 0 |
| `accounts(:rrsp_john)` | `Account::Rrsp`, balance 200000, `conversion_age: 71` |
| `accounts(:tfsa_jane)` | `Account::Tfsa`, balance 50000 |
| `accounts(:rrsp_jane)` | `Account::Rrsp`, balance 100000, `conversion_age: 65` |
| `benefits(:cpp_john)` | `Benefit::Cpp`, 15000, `start_age: 65` (John only — Jane has no benefits) |
| `benefits(:oas_john)` | `Benefit::Oas`, 8500, `start_age: 65` |
| `pensions(:indexed)` | John, 7000, `start_age: 65`, indexed |
| `employments(:john_employment)` | John, `annual_income: 0`, ages 65-70 |
| `employments(:jane_employment)` | Jane, `annual_income: 0`, ages 65-70 |
| `portfolios(:non_retired_portfolio)` | `inflation_rate: 0.02`, glidepath `standard_retirement` |

Known-good projection values for this household (verified against the real engine):

```
Projection::Household.from_household(households(:non_retired)).periods
  => 37 periods, first year 2026
  periods.first.net_worth        => 483750
  periods[10].net_worth (2036)   => 997022
  periods[30].net_worth (2056)   => 959904
  periods[30].benefit_income     => 29220
```

---

## Task 1: Scenario model and migration

**Files:**
- Create: `db/migrate/<timestamp>_create_scenarios.rb`
- Create: `app/models/scenario.rb`
- Modify: `app/models/household.rb`
- Test: `test/models/scenario_test.rb`

**Interfaces:**
- Produces: `Scenario` (ActiveRecord). `belongs_to :household`. Columns `raw_input:text`, `parsed_levers:json`, `confirmed_levers:json`, `status:string`, `clarifying_question:text`, `confirmed_at:datetime`. Statuses: `parsed`, `clarifying`, `confirmed`, `rejected`. Constant `Scenario::MAX_INPUT_LENGTH = 500`. Method `#confirm!(levers)`.

> **Why this is first:** `Scenario::Draft`, `Scenario::Lever::*` and friends all nest under `Scenario`. If a nested file defines `class Scenario` before `app/models/scenario.rb` exists, Zeitwerk creates a plain class and the later `class Scenario < ApplicationRecord` raises a superclass mismatch. Defining the AR model first avoids that entirely.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateScenarios
```

- [ ] **Step 2: Write the migration**

Replace the generated file's contents with:

```ruby
class CreateScenarios < ActiveRecord::Migration[8.0]
  def change
    create_table :scenarios do |t|
      t.references :household, null: false, foreign_key: true
      t.text :raw_input, null: false
      t.json :parsed_levers, default: [], null: false
      t.json :confirmed_levers, default: [], null: false
      t.string :status, default: 'parsed', null: false
      t.text :clarifying_question
      t.datetime :confirmed_at

      t.timestamps
    end

    add_index :scenarios, :status
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

Expected: `db/schema.rb` updated with a `scenarios` table.

- [ ] **Step 4: Write the failing test**

Create `test/models/scenario_test.rb`:

```ruby
require 'test_helper'

class ScenarioTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
  end

  test 'requires raw_input' do
    scenario = Scenario.new(household: @household)
    assert_not scenario.valid?
    assert_includes scenario.errors[:raw_input], "can't be blank"
  end

  test 'rejects raw_input longer than 500 characters' do
    scenario = Scenario.new(household: @household, raw_input: 'a' * 501)
    assert_not scenario.valid?
    assert_includes scenario.errors[:raw_input], 'is too long (maximum is 500 characters)'
  end

  test 'accepts raw_input at exactly 500 characters' do
    scenario = Scenario.new(household: @household, raw_input: 'a' * 500)
    assert scenario.valid?
  end

  test 'defaults to parsed status' do
    scenario = Scenario.create!(household: @household, raw_input: 'retire at 60')
    assert scenario.parsed?
  end

  test 'confirm! records the levers and timestamp' do
    scenario = Scenario.create!(household: @household, raw_input: 'retire at 60')
    levers = [{ 'lever' => 'retirement_age', 'person_id' => 1, 'value' => 60 }]

    scenario.confirm!(levers)

    assert scenario.confirmed?
    assert_equal levers, scenario.confirmed_levers
    assert_not_nil scenario.confirmed_at
  end

  test 'destroying a household destroys its scenarios' do
    household = Household.create!(name: 'Temp')
    Scenario.create!(household: household, raw_input: 'retire at 60')

    assert_difference 'Scenario.count', -1 do
      household.destroy
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario`.

- [ ] **Step 6: Write the model**

Create `app/models/scenario.rb`:

```ruby
# A single natural-language what-if question and its lifecycle.
#
# Holds what the user typed, what the model extracted from it, and what the
# user actually confirmed. The gap between parsed_levers and confirmed_levers
# is the extraction-accuracy metric.
#
# Nothing here is written to the user's profile. A Scenario is a staging record.
class Scenario < ApplicationRecord
  include Inspectable

  MAX_INPUT_LENGTH = 500

  belongs_to :household

  enum :status, {
    parsed: 'parsed',
    clarifying: 'clarifying',
    confirmed: 'confirmed',
    rejected: 'rejected',
  }

  validates :raw_input, presence: true, length: { maximum: MAX_INPUT_LENGTH }

  inspectable :raw_input, :status

  def confirm!(levers)
    update!(confirmed_levers: levers, status: :confirmed, confirmed_at: Time.current)
  end
end
```

- [ ] **Step 7: Add the association to Household**

In `app/models/household.rb`, immediately after the `has_one :portfolio, dependent: :destroy` line:

```ruby
  has_many :scenarios, dependent: :destroy
```

- [ ] **Step 8: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario_test.rb
```

Expected: PASS, 6 runs.

- [ ] **Step 9: Annotate and lint**

```bash
bin/rails annotate
bin/rubocop -a app/models/scenario.rb app/models/household.rb test/models/scenario_test.rb
```

- [ ] **Step 10: Commit**

```bash
git add db/migrate db/schema.rb app/models/scenario.rb app/models/household.rb test/models/scenario_test.rb
git commit -m "feat: add Scenario model for natural-language what-if requests"
```

---

## Task 2: Scenario::Draft

**Files:**
- Create: `app/models/scenario/draft.rb`
- Test: `test/models/scenario/draft_test.rb`

**Interfaces:**
- Consumes: `Scenario` (Task 1), existing `Projection::Household`.
- Produces: `Scenario::Draft.from(household) -> Scenario::Draft`. Instance methods `#household`, `#users`, `#portfolio`, `#accounts`, `#pensions`, `#benefits`, `#employments`, `#user(id)`, `#to_projection -> Projection::Household`.

> **Background — why this looks the way it does.** `Simulation` builds its working copy with `record.dup` and then repairs it twice: it reassigns the primary key (because `dup` clears it, and the engine matches records by id at `app/models/projection/household.rb:69`), and it hand-wires `association(:user).target` (because the household's `has_many :through` associations do not set `inverse_of`). Loading the graph through `Household.includes(users: ...)` makes both repairs unnecessary — ids are never lost and Rails wires the associations itself. **Do not reintroduce `dup` here.**
>
> The household and portfolio are loaded fresh rather than taken from the caller because the `IncomeGoal` and `Glidepath` levers mutate exactly those objects, and because `Household#terminal_year` and `#retired_as_of?` read `household.users` — eager-loading through the household makes that association the same objects the levers mutate.

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/draft_test.rb`:

```ruby
require 'test_helper'

class Scenario::DraftTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'loads all household records' do
    draft = Scenario::Draft.from(@household)

    assert_equal 2, draft.users.size
    assert_equal 4, draft.accounts.size
    assert_equal 1, draft.pensions.size
    assert_equal 2, draft.benefits.size
    assert_equal 2, draft.employments.size
  end

  test 'record ids are intact' do
    draft = Scenario::Draft.from(@household)

    assert draft.accounts.all? { |a| a.id.present? }, 'account ids must survive loading'
    assert draft.users.all? { |u| u.id.present? }
  end

  test 'account.user is the same object as the draft user' do
    draft = Scenario::Draft.from(@household)
    account = draft.accounts.first

    assert_same draft.user(account.user_id), account.user
  end

  test 'pension.user is the same object as the draft user' do
    draft = Scenario::Draft.from(@household)
    pension = draft.pensions.first

    assert_same draft.user(pension.user_id), pension.user
  end

  test 'household#terminal_year follows a mutated draft user' do
    draft = Scenario::Draft.from(@household)
    before = draft.household.terminal_year

    draft.users.each { |u| u.life_expectancy = 100 }

    assert_not_equal before, draft.household.terminal_year
    assert_equal draft.users.map(&:life_expectancy_year).max, draft.household.terminal_year
  end

  test 'household#retired_as_of? follows a mutated draft user' do
    draft = Scenario::Draft.from(@household)
    year = Time.zone.now.year + 5
    assert_not draft.household.retired_as_of?(year)

    draft.users.each { |u| u.retirement_age = 30 }

    assert draft.household.retired_as_of?(year)
  end

  test 'draft portfolio is not the caller portfolio object' do
    draft = Scenario::Draft.from(@household)

    assert_not_same @household.portfolio, draft.portfolio
  end

  test 'mutating the draft does not touch the database' do
    draft = Scenario::Draft.from(@household)
    draft.household.retirement_income_goal = 999_999
    draft.portfolio.glidepath_id = 12_345
    draft.users.each { |u| u.retirement_age = 40 }

    assert_equal 120_000, Household.find(@household.id).retirement_income_goal
    assert_equal 65, User.find(@john.id).retirement_age
  end

  test 'to_projection produces the same periods as the baseline' do
    baseline = Projection::Household.from_household(@household).periods
    drafted  = Scenario::Draft.from(@household).to_projection.periods

    assert_equal baseline.size, drafted.size
    assert_equal baseline.map(&:net_worth), drafted.map(&:net_worth)
  end

  test 'each account is tracked separately through the projection' do
    draft = Scenario::Draft.from(@household)
    periods = draft.to_projection.periods

    assert_equal 4, periods.first.account_periods.map(&:account_id).uniq.size
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/draft_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Draft`.

- [ ] **Step 3: Write the implementation**

Create `app/models/scenario/draft.rb`:

```ruby
class Scenario
  # An in-memory working copy of a household's records.
  #
  # These records are deliberately NEVER SAVED. Levers mutate them and
  # Projection::Household reads them. Nothing in this path calls save, update,
  # or destroy.
  #
  # Loaded via Household.includes(users: ...).find rather than from the caller's
  # household object, for two reasons:
  #
  #   1. Isolation. Household-scope levers mutate household.retirement_income_goal
  #      and portfolio.glidepath_id. Using the caller's objects would leak those
  #      mutations back into the request that asked for the projection.
  #
  #   2. Correctness. Household#terminal_year and #retired_as_of? read
  #      household.users. Eager-loading through the household makes that
  #      association the same objects the levers mutate, so both follow the draft
  #      rather than the database.
  #
  # inverse_of wires account.user / pension.user to the in-memory user, so no
  # association repair is needed and no record is duplicated. Do not reintroduce
  # ActiveRecord#dup here: it clears the primary key, and the engine matches
  # records by id (app/models/projection/household.rb:69).
  class Draft
    attr_reader :household

    def self.from(household)
      new(Household.includes(users: %i[accounts pensions benefits employment]).find(household.id))
    end

    def initialize(household)
      @household = household
    end

    def users = household.users.to_a
    def portfolio = household.portfolio
    def accounts = users.flat_map(&:accounts)
    def pensions = users.flat_map(&:pensions)
    def benefits = users.flat_map(&:benefits)
    def employments = users.filter_map(&:employment)

    def user(id) = users.find { |u| u.id == id }

    def to_projection
      Projection::Household.new(
        household: household,
        portfolio: portfolio,
        users: users,
        accounts: accounts,
        pensions: pensions,
        benefits: benefits,
        employments: employments
      )
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/draft_test.rb
```

Expected: PASS, 10 runs.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/draft.rb test/models/scenario/draft_test.rb
git add app/models/scenario/draft.rb test/models/scenario/draft_test.rb
git commit -m "feat: add Scenario::Draft for in-memory projection input"
```

---

## Task 3: Scenario::PersonResolver

**Files:**
- Create: `app/models/scenario/person_resolver.rb`
- Test: `test/models/scenario/person_resolver_test.rb`

**Interfaces:**
- Consumes: `Scenario` (Task 1).
- Produces: `Scenario::PersonResolver.new(household, current_user)`, method `#resolve(reference) -> User`, raises `Scenario::PersonResolver::AmbiguousPersonError`.

> **Why:** the model emits `"self"`, `"spouse"`, or a first name. Database IDs never appear in a prompt in either direction. Resolution is Ruby's job so the model cannot address the wrong person.

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/person_resolver_test.rb`:

```ruby
require 'test_helper'

class Scenario::PersonResolverTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
    @jane = users(:working_user_jane)
    @resolver = Scenario::PersonResolver.new(@household, @john)
  end

  test 'resolves self to the current user' do
    assert_equal @john, @resolver.resolve('self')
  end

  test 'resolves spouse to the other household member' do
    assert_equal @jane, @resolver.resolve('spouse')
  end

  test 'resolves a first name case-insensitively' do
    assert_equal @jane, @resolver.resolve('jane')
    assert_equal @jane, @resolver.resolve('JANE')
    assert_equal @john, @resolver.resolve('John')
  end

  test 'raises when spouse is requested in a single-member household' do
    solo = users(:single_user)
    resolver = Scenario::PersonResolver.new(households(:single), solo)

    error = assert_raises(Scenario::PersonResolver::AmbiguousPersonError) do
      resolver.resolve('spouse')
    end
    assert_match(/no spouse/i, error.message)
  end

  test 'raises on an unknown name' do
    error = assert_raises(Scenario::PersonResolver::AmbiguousPersonError) do
      @resolver.resolve('Gandalf')
    end
    assert_match(/Gandalf/, error.message)
  end

  test 'raises on a blank reference' do
    assert_raises(Scenario::PersonResolver::AmbiguousPersonError) { @resolver.resolve(nil) }
    assert_raises(Scenario::PersonResolver::AmbiguousPersonError) { @resolver.resolve('') }
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/person_resolver_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::PersonResolver`.

- [ ] **Step 3: Write the implementation**

Create `app/models/scenario/person_resolver.rb`:

```ruby
class Scenario
  # Maps the person references a language model emits ("self", "spouse", or a
  # first name) onto real User records.
  #
  # Database IDs are never sent to or accepted from the model. Every raise here
  # becomes a clarifying question rather than an error page.
  class PersonResolver
    class AmbiguousPersonError < StandardError; end

    SELF_REFERENCE = 'self'.freeze
    SPOUSE_REFERENCE = 'spouse'.freeze

    def initialize(household, current_user)
      @household = household
      @current_user = current_user
    end

    def resolve(reference)
      normalized = reference.to_s.strip.downcase
      raise AmbiguousPersonError, 'No person was specified.' if normalized.blank?

      case normalized
      when SELF_REFERENCE then @current_user
      when SPOUSE_REFERENCE then spouse
      else by_first_name(reference)
      end
    end

    private

    def members = @members ||= @household.users.to_a

    def spouse
      others = members.reject { |u| u.id == @current_user.id }
      if others.empty?
        raise AmbiguousPersonError, 'There is no spouse in this household.'
      elsif others.size > 1
        raise AmbiguousPersonError,
              "This household has more than one other member. Which one did you mean: #{names(others)}?"
      end

      others.first
    end

    def by_first_name(reference)
      matches = members.select { |u| u.first_name.to_s.casecmp?(reference.to_s.strip) }
      if matches.empty?
        raise AmbiguousPersonError, "I couldn't find #{reference} in this household. Members are: #{names(members)}."
      elsif matches.size > 1
        raise AmbiguousPersonError, "More than one household member is named #{reference}."
      end

      matches.first
    end

    def names(users) = users.map(&:first_name).join(', ')
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/person_resolver_test.rb
```

Expected: PASS, 6 runs.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/person_resolver.rb test/models/scenario/person_resolver_test.rb
git add app/models/scenario/person_resolver.rb test/models/scenario/person_resolver_test.rb
git commit -m "feat: add Scenario::PersonResolver for person reference resolution"
```

---

## Task 4: Lever base class and the two user-attribute levers

**Files:**
- Create: `app/models/scenario/lever.rb`
- Create: `app/models/scenario/lever/base.rb`
- Create: `app/models/scenario/lever/retirement_age.rb`
- Create: `app/models/scenario/lever/life_expectancy.rb`
- Test: `test/models/scenario/lever/retirement_age_test.rb`
- Test: `test/models/scenario/lever/life_expectancy_test.rb`

**Interfaces:**
- Consumes: `Scenario::Draft` (Task 2).
- Produces: `Scenario::Lever::Base.new(value:, person_id: nil)` with `#apply(draft)`, `#describe(draft) -> String`, `#key -> String`, `.key -> String`, `#to_h -> Hash`, `#==`. Subclasses `Scenario::Lever::RetirementAge`, `Scenario::Lever::LifeExpectancy`.

> **Pattern note:** this task establishes the shape every other lever follows. `person_id` is an integer resolved by `PersonResolver` before the lever is built — levers never see `"self"`. Household-scope levers pass `person_id: nil`.

- [ ] **Step 1: Write the failing tests**

Create `test/models/scenario/lever/retirement_age_test.rb`:

```ruby
require 'test_helper'

class Scenario::Lever::RetirementAgeTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'sets the retirement age on the target user only' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60).apply(draft)

    assert_equal 60, draft.user(@john.id).retirement_age
    assert_equal 65, draft.user(users(:working_user_jane).id).retirement_age
  end

  test 'changes the projection' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60).apply(draft)
    changed = draft.to_projection.periods

    assert_not_equal baseline.map(&:net_worth), changed.map(&:net_worth)
  end

  test 'describes itself with the person name' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)

    assert_equal 'John retires at age 60', lever.describe(draft)
  end

  test 'serialises to a hash' do
    lever = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)

    assert_equal({ 'lever' => 'retirement_age', 'person_id' => @john.id, 'value' => 60 }, lever.to_h)
  end

  test 'equality is by class, person and value' do
    a = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)
    b = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)
    c = Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 61)

    assert_equal a, b
    assert_not_equal a, c
  end
end
```

Create `test/models/scenario/lever/life_expectancy_test.rb`:

```ruby
require 'test_helper'

class Scenario::Lever::LifeExpectancyTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'sets the life expectancy on the target user' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::LifeExpectancy.new(person_id: @john.id, value: 95).apply(draft)

    assert_equal 95, draft.user(@john.id).life_expectancy
  end

  test 'extends the projection terminal year' do
    draft = Scenario::Draft.from(@household)
    before = draft.to_projection.periods.size

    Scenario::Lever::LifeExpectancy.new(person_id: @john.id, value: 95).apply(draft)

    assert_operator draft.to_projection.periods.size, :>, before
  end

  test 'describes itself with the person name' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::LifeExpectancy.new(person_id: @john.id, value: 95)

    assert_equal 'John lives to age 95', lever.describe(draft)
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/models/scenario/lever/retirement_age_test.rb test/models/scenario/lever/life_expectancy_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Lever`.

- [ ] **Step 3: Write the namespace and base class**

Create `app/models/scenario/lever.rb`:

```ruby
class Scenario
  # Namespace for scenario levers. Each lever encapsulates exactly one change a
  # user can make to a household's plan, and knows how to apply itself to a
  # Scenario::Draft and describe itself in plain English.
  module Lever
  end
end
```

Create `app/models/scenario/lever/base.rb`:

```ruby
class Scenario
  module Lever
    # Shared behaviour for every lever.
    #
    # person_id is an integer already resolved by Scenario::PersonResolver.
    # Levers never see the model's "self" / "spouse" references. Household-scope
    # levers pass person_id: nil.
    class Base
      attr_reader :person_id, :value

      def initialize(value:, person_id: nil)
        @person_id = person_id
        @value = value
      end

      # Mutate the draft. Subclasses must implement.
      def apply(_draft) = raise NotImplementedError, "#{self.class} must implement #apply"

      # Plain-English description for the confirmation UI. Subclasses must implement.
      def describe(_draft) = raise NotImplementedError, "#{self.class} must implement #describe"

      # Stable identifier used in the LLM schema and in persisted JSON.
      def self.key = name.demodulize.underscore

      def key = self.class.key

      def to_h = { 'lever' => key, 'person_id' => person_id, 'value' => value }

      def ==(other)
        other.instance_of?(self.class) && other.person_id == person_id && other.value == value
      end
      alias eql? ==

      def hash = [self.class, person_id, value].hash

      private

      def person_name(draft) = draft.user(person_id)&.first_name
    end
  end
end
```

- [ ] **Step 4: Write the two levers**

Create `app/models/scenario/lever/retirement_age.rb`:

```ruby
class Scenario
  module Lever
    class RetirementAge < Base
      def apply(draft)
        draft.user(person_id).retirement_age = value
      end

      def describe(draft) = "#{person_name(draft)} retires at age #{value}"
    end
  end
end
```

Create `app/models/scenario/lever/life_expectancy.rb`:

```ruby
class Scenario
  module Lever
    class LifeExpectancy < Base
      def apply(draft)
        draft.user(person_id).life_expectancy = value
      end

      def describe(draft) = "#{person_name(draft)} lives to age #{value}"
    end
  end
end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bin/rails test test/models/scenario/lever/retirement_age_test.rb test/models/scenario/lever/life_expectancy_test.rb
```

Expected: PASS, 8 runs.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/lever.rb app/models/scenario/lever test/models/scenario/lever
git add app/models/scenario/lever.rb app/models/scenario/lever test/models/scenario/lever
git commit -m "feat: add lever base class with retirement age and life expectancy levers"
```

---

## Task 5: Employment and account contribution levers

**Files:**
- Create: `app/models/scenario/lever/employment_end_age.rb`
- Create: `app/models/scenario/lever/employment_income.rb`
- Create: `app/models/scenario/lever/account_contribution.rb`
- Test: `test/models/scenario/lever/employment_levers_test.rb`
- Test: `test/models/scenario/lever/account_contribution_test.rb`

**Interfaces:**
- Consumes: `Scenario::Lever::Base` (Task 4), `Scenario::Draft` (Task 2).
- Produces: `Scenario::Lever::EmploymentEndAge.new(person_id:, value:)`, `Scenario::Lever::EmploymentIncome.new(person_id:, value:)`, `Scenario::Lever::AccountContribution.new(account_id:, value:)` with reader `#account_id`.

> **Note:** `Employment` has a `UNIQUE` index on `user_id` — exactly one per user, reached via `user.employment`. `AccountContribution` is the only lever that targets a specific record rather than a person, so it takes an extra keyword and overrides `to_h`.

- [ ] **Step 1: Write the failing tests**

Create `test/models/scenario/lever/employment_levers_test.rb`:

```ruby
require 'test_helper'

class Scenario::Lever::EmploymentLeversTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'employment end age sets the end age' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::EmploymentEndAge.new(person_id: @john.id, value: 75).apply(draft)

    assert_equal 75, draft.user(@john.id).employment.end_age
  end

  test 'employment end age describes itself' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::EmploymentEndAge.new(person_id: @john.id, value: 75)

    assert_equal 'John works until age 75', lever.describe(draft)
  end

  test 'employment income sets the annual income' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::EmploymentIncome.new(person_id: @john.id, value: 30_000).apply(draft)

    assert_equal 30_000, draft.user(@john.id).employment.annual_income
  end

  test 'employment income changes the projection' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::EmploymentIncome.new(person_id: @john.id, value: 40_000).apply(draft)
    changed = draft.to_projection.periods

    assert_not_equal baseline.map(&:net_worth), changed.map(&:net_worth)
  end

  test 'employment income describes itself with currency formatting' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::EmploymentIncome.new(person_id: @john.id, value: 30_000)

    assert_equal 'John earns $30,000/yr in post-retirement work', lever.describe(draft)
  end
end
```

Create `test/models/scenario/lever/account_contribution_test.rb`:

```ruby
require 'test_helper'

class Scenario::Lever::AccountContributionTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @tfsa = accounts(:tfsa_john)
  end

  test 'sets the contribution on the target account only' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000).apply(draft)

    target = draft.accounts.find { |a| a.id == @tfsa.id }
    others = draft.accounts.reject { |a| a.id == @tfsa.id }

    assert_equal 6000, target.contribution
    assert others.all? { |a| a.contribution.zero? }
  end

  test 'changes the projection' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000).apply(draft)

    assert_not_equal baseline.map(&:net_worth), draft.to_projection.periods.map(&:net_worth)
  end

  test 'describes itself with the account name' do
    draft = Scenario::Draft.from(@household)
    lever = Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000)

    assert_equal 'Contribute $6,000/yr to TFSA', lever.describe(draft)
  end

  test 'serialises with account_id' do
    lever = Scenario::Lever::AccountContribution.new(account_id: @tfsa.id, value: 6000)

    assert_equal(
      { 'lever' => 'account_contribution', 'person_id' => nil, 'account_id' => @tfsa.id, 'value' => 6000 },
      lever.to_h
    )
  end
end
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
bin/rails test test/models/scenario/lever/employment_levers_test.rb test/models/scenario/lever/account_contribution_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Lever::EmploymentEndAge`.

- [ ] **Step 3: Write the employment levers**

Create `app/models/scenario/lever/employment_end_age.rb`:

```ruby
class Scenario
  module Lever
    class EmploymentEndAge < Base
      def apply(draft)
        employment = draft.user(person_id)&.employment
        employment.end_age = value if employment
      end

      def describe(draft) = "#{person_name(draft)} works until age #{value}"
    end
  end
end
```

Create `app/models/scenario/lever/employment_income.rb`:

```ruby
class Scenario
  module Lever
    class EmploymentIncome < Base
      include ActiveSupport::NumberHelper

      def apply(draft)
        employment = draft.user(person_id)&.employment
        employment.annual_income = value if employment
      end

      def describe(draft)
        "#{person_name(draft)} earns #{number_to_currency(value, precision: 0)}/yr in post-retirement work"
      end
    end
  end
end
```

- [ ] **Step 4: Write the account contribution lever**

Create `app/models/scenario/lever/account_contribution.rb`:

```ruby
class Scenario
  module Lever
    # The only record-scoped lever: it targets a specific account rather than a
    # person, so it carries account_id instead of relying on person_id.
    class AccountContribution < Base
      include ActiveSupport::NumberHelper

      attr_reader :account_id

      def initialize(value:, account_id:, person_id: nil)
        super(value: value, person_id: person_id)
        @account_id = account_id
      end

      def apply(draft)
        target = account(draft)
        target.contribution = value if target
      end

      def describe(draft)
        "Contribute #{number_to_currency(value, precision: 0)}/yr to #{account(draft)&.name}"
      end

      def to_h = super.merge('account_id' => account_id)

      def ==(other) = super && other.account_id == account_id
      alias eql? ==

      def hash = [self.class, account_id, value].hash

      private

      def account(draft) = draft.accounts.find { |a| a.id == account_id }
    end
  end
end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bin/rails test test/models/scenario/lever/employment_levers_test.rb test/models/scenario/lever/account_contribution_test.rb
```

Expected: PASS, 9 runs.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/lever test/models/scenario/lever
git add app/models/scenario/lever test/models/scenario/lever
git commit -m "feat: add employment and account contribution levers"
```

---

## Task 6: MonthlySavings lever

**Files:**
- Create: `app/models/scenario/lever/monthly_savings.rb`
- Test: `test/models/scenario/lever/monthly_savings_test.rb`

**Interfaces:**
- Consumes: `Scenario::Lever::Base` (Task 4), `Scenario::Draft` (Task 2).
- Produces: `Scenario::Lever::MonthlySavings.new(person_id:, value:)` where `value` is a **monthly dollar delta** (may be negative).

> **Behaviour, matching `WhatIf#accounts_params` in `app/models/what_if.rb`:** multiply the monthly delta by 12, spread it evenly across the user's accounts that already have a positive contribution, fall back to *all* the user's accounts when none contribute, and floor each resulting contribution at zero. In the `non_retired` fixture no account has a contribution, so the fallback path is the one exercised: John has 2 accounts, so a $200/mo delta adds $1,200 to each ($2,400 / 2).

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/lever/monthly_savings_test.rb`:

```ruby
require 'test_helper'

class Scenario::Lever::MonthlySavingsTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'spreads the annualised delta across all accounts when none contribute' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 200).apply(draft)

    johns = draft.accounts.select { |a| a.user_id == @john.id }
    assert_equal 2, johns.size
    assert_equal [1200, 1200], johns.map(&:contribution).sort
  end

  test 'only targets accounts that already contribute when some do' do
    draft = Scenario::Draft.from(@household)
    tfsa = draft.accounts.find { |a| a.id == accounts(:tfsa_john).id }
    tfsa.contribution = 1000

    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 100).apply(draft)

    rrsp = draft.accounts.find { |a| a.id == accounts(:rrsp_john).id }
    assert_equal 2200, tfsa.contribution
    assert_equal 0, rrsp.contribution
  end

  test 'does not touch the other household member' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 200).apply(draft)

    janes = draft.accounts.select { |a| a.user_id == users(:working_user_jane).id }
    assert janes.all? { |a| a.contribution.zero? }
  end

  test 'floors contributions at zero for a negative delta' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: -500).apply(draft)

    johns = draft.accounts.select { |a| a.user_id == @john.id }
    assert johns.all? { |a| a.contribution >= 0 }
  end

  test 'increases projected net worth' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 500).apply(draft)

    assert_operator draft.to_projection.periods.map(&:net_worth).max, :>, baseline.map(&:net_worth).max
  end

  test 'describes itself' do
    draft = Scenario::Draft.from(@household)

    assert_equal 'John saves $500/mo more',
                 Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 500).describe(draft)
    assert_equal 'John saves $300/mo less',
                 Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: -300).describe(draft)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/lever/monthly_savings_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Lever::MonthlySavings`.

- [ ] **Step 3: Write the implementation**

Create `app/models/scenario/lever/monthly_savings.rb`:

```ruby
class Scenario
  module Lever
    # A monthly savings delta, fanned out across a user's accounts.
    #
    # Mirrors WhatIf#accounts_params: annualise the delta, spread it evenly over
    # the accounts that already contribute, fall back to all of the user's
    # accounts when none do, and floor each result at zero.
    class MonthlySavings < Base
      include ActiveSupport::NumberHelper

      def apply(draft)
        targets = target_accounts(draft)
        return if targets.empty?

        per_account = ((value * 12).to_f / targets.size).round
        targets.each do |account|
          account.contribution = [account.contribution.to_i + per_account, 0].max
        end
      end

      def describe(draft)
        direction = value.negative? ? 'less' : 'more'
        "#{person_name(draft)} saves #{number_to_currency(value.abs, precision: 0)}/mo #{direction}"
      end

      private

      def target_accounts(draft)
        owned = draft.accounts.select { |a| a.user_id == person_id }
        contributing = owned.select { |a| a.contribution.to_i.positive? }
        contributing.presence || owned
      end
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/lever/monthly_savings_test.rb
```

Expected: PASS, 6 runs.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/lever/monthly_savings.rb test/models/scenario/lever/monthly_savings_test.rb
git add app/models/scenario/lever/monthly_savings.rb test/models/scenario/lever/monthly_savings_test.rb
git commit -m "feat: add monthly savings lever with account fan-out"
```

---

## Task 7: Benefit and pension timing levers

**Files:**
- Create: `app/models/scenario/lever/cpp_start_age.rb`
- Create: `app/models/scenario/lever/oas_start_age.rb`
- Create: `app/models/scenario/lever/pension_start_age.rb`
- Test: `test/models/scenario/lever/timing_levers_test.rb`

**Interfaces:**
- Consumes: `Scenario::Lever::Base` (Task 4), `Scenario::Draft` (Task 2).
- Produces: `Scenario::Lever::CppStartAge`, `Scenario::Lever::OasStartAge`, `Scenario::Lever::PensionStartAge` — all `new(person_id:, value:)`, all fanning out across the person's matching records.

> **CRITICAL for the tests:** post-retirement withdrawals are goal-based, so raising guaranteed income lowers withdrawals and `Period::Summary#income_amount` stays flat. Verified against the real engine: moving John's CPP from 65 to 70 leaves total income identical while `benefit_income` moves 29,220 -> 34,556 and net worth 959,904 -> 869,261 in 2056. **Assert on `adjusted_annual_amount`, `benefit_income`, or `net_worth` — never on `income_amount`.**
>
> Age ranges are already enforced by the models: `Benefit::Cpp` allows 60-70, `Benefit::Oas` allows 65-70. Levers do not re-declare them; validation (Task 14) calls `.valid?`.

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/lever/timing_levers_test.rb`:

```ruby
require 'test_helper'

class Scenario::Lever::TimingLeversTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'cpp start age sets the age on the CPP benefit only' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::CppStartAge.new(person_id: @john.id, value: 70).apply(draft)

    cpp = draft.benefits.find { |b| b.is_a?(Benefit::Cpp) }
    oas = draft.benefits.find { |b| b.is_a?(Benefit::Oas) }

    assert_equal 70, cpp.start_age
    assert_equal 65, oas.start_age
  end

  test 'delaying cpp raises the adjusted annual amount' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::CppStartAge.new(person_id: @john.id, value: 70).apply(draft)

    cpp = draft.benefits.find { |b| b.is_a?(Benefit::Cpp) }
    # 0.7% per month for 60 months = +42% on 15000
    assert_equal 21_300, cpp.adjusted_annual_amount
  end

  test 'delaying cpp changes benefit income and net worth but not total income' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::CppStartAge.new(person_id: @john.id, value: 70).apply(draft)
    changed = draft.to_projection.periods

    index = 30 # year 2056
    assert_not_equal baseline[index].benefit_income, changed[index].benefit_income
    assert_not_equal baseline[index].net_worth, changed[index].net_worth
    # Goal-based withdrawals absorb the difference, so total income is unchanged:
    assert_equal baseline[index].income_amount, changed[index].income_amount
  end

  test 'oas start age sets the age on the OAS benefit only' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::OasStartAge.new(person_id: @john.id, value: 70).apply(draft)

    assert_equal 70, draft.benefits.find { |b| b.is_a?(Benefit::Oas) }.start_age
    assert_equal 65, draft.benefits.find { |b| b.is_a?(Benefit::Cpp) }.start_age
  end

  test 'pension start age fans out across all the persons pensions' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::PensionStartAge.new(person_id: @john.id, value: 60).apply(draft)

    johns = draft.pensions.select { |p| p.user_id == @john.id }
    assert johns.any?
    assert johns.all? { |p| p.start_age == 60 }
  end

  test 'timing levers describe themselves' do
    draft = Scenario::Draft.from(@household)

    assert_equal 'John starts CPP at age 70',
                 Scenario::Lever::CppStartAge.new(person_id: @john.id, value: 70).describe(draft)
    assert_equal 'John starts OAS at age 68',
                 Scenario::Lever::OasStartAge.new(person_id: @john.id, value: 68).describe(draft)
    assert_equal 'John starts their pension at age 60',
                 Scenario::Lever::PensionStartAge.new(person_id: @john.id, value: 60).describe(draft)
  end

  test 'a lever for a person with no matching record is a no-op' do
    draft = Scenario::Draft.from(@household)
    jane = users(:working_user_jane)

    assert_nothing_raised do
      Scenario::Lever::CppStartAge.new(person_id: jane.id, value: 70).apply(draft)
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/lever/timing_levers_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Lever::CppStartAge`.

- [ ] **Step 3: Write the CPP lever**

Create `app/models/scenario/lever/cpp_start_age.rb`:

```ruby
class Scenario
  module Lever
    # Valid range (60-70) is enforced by Benefit::Cpp's own validations, which
    # Scenario::Interpretation checks via #valid? rather than restating here.
    class CppStartAge < Base
      def apply(draft)
        draft.benefits
             .select { |b| b.user_id == person_id && b.is_a?(Benefit::Cpp) }
             .each { |b| b.start_age = value }
      end

      def describe(draft) = "#{person_name(draft)} starts CPP at age #{value}"
    end
  end
end
```

- [ ] **Step 4: Write the OAS lever**

Create `app/models/scenario/lever/oas_start_age.rb`:

```ruby
class Scenario
  module Lever
    # Valid range (65-70) is enforced by Benefit::Oas's own validations.
    class OasStartAge < Base
      def apply(draft)
        draft.benefits
             .select { |b| b.user_id == person_id && b.is_a?(Benefit::Oas) }
             .each { |b| b.start_age = value }
      end

      def describe(draft) = "#{person_name(draft)} starts OAS at age #{value}"
    end
  end
end
```

- [ ] **Step 5: Write the pension lever**

Create `app/models/scenario/lever/pension_start_age.rb`:

```ruby
class Scenario
  module Lever
    # Applies a single start age to ALL of a person's defined-benefit pensions,
    # matching WhatIf's fan-out behaviour.
    class PensionStartAge < Base
      def apply(draft)
        draft.pensions.select { |p| p.user_id == person_id }.each { |p| p.start_age = value }
      end

      def describe(draft) = "#{person_name(draft)} starts their pension at age #{value}"
    end
  end
end
```

- [ ] **Step 6: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/lever/timing_levers_test.rb
```

Expected: PASS, 7 runs.

- [ ] **Step 7: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/lever test/models/scenario/lever
git add app/models/scenario/lever test/models/scenario/lever
git commit -m "feat: add CPP, OAS and pension timing levers"
```

---

## Task 8: Household-scope levers

**Files:**
- Create: `app/models/scenario/lever/income_goal.rb`
- Create: `app/models/scenario/lever/glidepath.rb`
- Test: `test/models/scenario/lever/household_levers_test.rb`

**Interfaces:**
- Consumes: `Scenario::Lever::Base` (Task 4), `Scenario::Draft` (Task 2).
- Produces: `Scenario::Lever::IncomeGoal.new(value:)`, `Scenario::Lever::Glidepath.new(value:)` where `value` is a `Glidepath` id. Both leave `person_id` nil.

> **Isolation matters here.** These are the levers that mutate `draft.household` and `draft.portfolio`. `Scenario::Draft` loads both fresh precisely so this cannot leak back to the caller — there are explicit tests for that below.
>
> Note `Scenario::Lever::Glidepath` shadows the top-level `Glidepath` model inside its own namespace, so `#describe` must reference `::Glidepath` with the leading `::`.

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/lever/household_levers_test.rb`:

```ruby
require 'test_helper'

class Scenario::Lever::HouseholdLeversTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
  end

  test 'income goal sets the goal on the draft household' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::IncomeGoal.new(value: 90_000).apply(draft)

    assert_equal 90_000, draft.household.retirement_income_goal
  end

  test 'income goal does not leak to the caller or the database' do
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::IncomeGoal.new(value: 90_000).apply(draft)

    assert_equal 120_000, @household.retirement_income_goal
    assert_equal 120_000, Household.find(@household.id).retirement_income_goal
  end

  test 'income goal changes the projection' do
    baseline = Projection::Household.from_household(@household).periods

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::IncomeGoal.new(value: 200_000).apply(draft)

    assert_not_equal baseline.map(&:net_worth), draft.to_projection.periods.map(&:net_worth)
  end

  test 'income goal describes itself' do
    draft = Scenario::Draft.from(@household)

    assert_equal 'Household income goal of $90,000/yr',
                 Scenario::Lever::IncomeGoal.new(value: 90_000).describe(draft)
  end

  test 'glidepath sets the glidepath on the draft portfolio' do
    other = ::Glidepath.where.not(id: @household.portfolio.glidepath_id).first
    skip 'needs a second glidepath fixture' unless other

    draft = Scenario::Draft.from(@household)
    Scenario::Lever::Glidepath.new(value: other.id).apply(draft)

    assert_equal other.id, draft.portfolio.glidepath_id
  end

  test 'glidepath does not leak to the database' do
    other = ::Glidepath.where.not(id: @household.portfolio.glidepath_id).first
    skip 'needs a second glidepath fixture' unless other

    original = @household.portfolio.glidepath_id
    draft = Scenario::Draft.from(@household)
    Scenario::Lever::Glidepath.new(value: other.id).apply(draft)

    assert_equal original, Portfolio.find_by(household_id: @household.id).glidepath_id
  end

  test 'glidepath describes itself with the glidepath name' do
    draft = Scenario::Draft.from(@household)
    glidepath = ::Glidepath.first

    assert_equal "Switch investment strategy to #{glidepath.name}",
                 Scenario::Lever::Glidepath.new(value: glidepath.id).describe(draft)
  end

  test 'household levers have no person' do
    assert_nil Scenario::Lever::IncomeGoal.new(value: 90_000).person_id
    assert_nil Scenario::Lever::Glidepath.new(value: 1).person_id
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/lever/household_levers_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Lever::IncomeGoal`.

- [ ] **Step 3: Write the income goal lever**

Create `app/models/scenario/lever/income_goal.rb`:

```ruby
class Scenario
  module Lever
    # Household-scope. Mutates draft.household, which Scenario::Draft loads
    # fresh so the change cannot leak back to the caller.
    class IncomeGoal < Base
      include ActiveSupport::NumberHelper

      def apply(draft)
        draft.household.retirement_income_goal = value
      end

      def describe(_draft) = "Household income goal of #{number_to_currency(value, precision: 0)}/yr"
    end
  end
end
```

- [ ] **Step 4: Write the glidepath lever**

Create `app/models/scenario/lever/glidepath.rb`:

```ruby
class Scenario
  module Lever
    # Household-scope. value is a Glidepath id. Mutates draft.portfolio, which
    # Scenario::Draft loads fresh so the change cannot leak back to the caller.
    #
    # This class shadows the top-level Glidepath model inside this namespace, so
    # the model must be referenced as ::Glidepath.
    class Glidepath < Base
      def apply(draft)
        draft.portfolio.glidepath_id = value
      end

      def describe(_draft)
        "Switch investment strategy to #{::Glidepath.find_by(id: value)&.name}"
      end
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/lever/household_levers_test.rb
```

Expected: PASS, 8 runs (2 may skip if there is only one glidepath fixture).

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/lever test/models/scenario/lever
git add app/models/scenario/lever test/models/scenario/lever
git commit -m "feat: add household income goal and glidepath levers"
```

---

## Task 9: Scenario::LeverSet

**Files:**
- Create: `app/models/scenario/lever_set.rb`
- Test: `test/models/scenario/lever_set_test.rb`

**Interfaces:**
- Consumes: every `Scenario::Lever::*` class (Tasks 4-8), `Scenario::Draft` (Task 2).
- Produces: `Scenario::LeverSet.new(levers)`, `.from_h(array_of_hashes)`, `.build_lever(hash)`, `#apply(draft)`, `#descriptions(draft) -> Array<String>`, `#to_h -> Array<Hash>`, `#diff(other) -> Hash`, `#empty?`, `#size`, `#each` (Enumerable). Also `Scenario::LeverSet::REGISTRY` mapping lever keys to classes, and `Scenario::LeverSet::UnknownLeverError`.

> **`REGISTRY` is the single source of truth for the eleven levers.** The LLM schema (Task 14) is generated from it, so the model structurally cannot request a lever the engine does not implement.
>
> `#diff` returns `{ corrected:, added:, removed:, total_parsed: }` where the first three are arrays of lever keys. This is the extraction-accuracy measurement.

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/lever_set_test.rb`:

```ruby
require 'test_helper'

class Scenario::LeverSetTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'registry contains all eleven levers' do
    assert_equal 11, Scenario::LeverSet::REGISTRY.size
    assert_equal Scenario::Lever::RetirementAge, Scenario::LeverSet::REGISTRY['retirement_age']
    assert_equal Scenario::Lever::CppStartAge, Scenario::LeverSet::REGISTRY['cpp_start_age']
  end

  test 'applies every lever to the draft' do
    set = Scenario::LeverSet.new([
                                   Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60),
                                   Scenario::Lever::CppStartAge.new(person_id: @john.id, value: 70),
                                 ])
    draft = Scenario::Draft.from(@household)
    set.apply(draft)

    assert_equal 60, draft.user(@john.id).retirement_age
    assert_equal 70, draft.benefits.find { |b| b.is_a?(Benefit::Cpp) }.start_age
  end

  test 'builds from hashes' do
    set = Scenario::LeverSet.from_h([{ 'lever' => 'retirement_age', 'person_id' => @john.id, 'value' => 60 }])

    assert_equal 1, set.size
    assert_equal Scenario::Lever::RetirementAge, set.first.class
    assert_equal 60, set.first.value
  end

  test 'builds account contribution from a hash with account_id' do
    set = Scenario::LeverSet.from_h(
      [{ 'lever' => 'account_contribution', 'account_id' => accounts(:tfsa_john).id, 'value' => 6000 }]
    )

    assert_equal accounts(:tfsa_john).id, set.first.account_id
  end

  test 'raises on an unknown lever key' do
    error = assert_raises(Scenario::LeverSet::UnknownLeverError) do
      Scenario::LeverSet.from_h([{ 'lever' => 'buy_a_house', 'value' => 650_000 }])
    end
    assert_match(/buy_a_house/, error.message)
  end

  test 'round trips through to_h' do
    set = Scenario::LeverSet.new([Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)])

    assert_equal set.to_h, Scenario::LeverSet.from_h(set.to_h).to_h
  end

  test 'diff reports corrected, added and removed levers' do
    parsed = Scenario::LeverSet.new([
                                      Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60),
                                      Scenario::Lever::CppStartAge.new(person_id: @john.id, value: 70),
                                    ])
    confirmed = Scenario::LeverSet.new([
                                         Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 62),
                                         Scenario::Lever::OasStartAge.new(person_id: @john.id, value: 70),
                                       ])

    diff = parsed.diff(confirmed)

    assert_equal ['retirement_age'], diff[:corrected]
    assert_equal ['oas_start_age'], diff[:added]
    assert_equal ['cpp_start_age'], diff[:removed]
    assert_equal 2, diff[:total_parsed]
  end

  test 'diff of identical sets reports no changes' do
    set = Scenario::LeverSet.new([Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)])
    diff = set.diff(set)

    assert_empty diff[:corrected]
    assert_empty diff[:added]
    assert_empty diff[:removed]
  end

  test 'descriptions returns one string per lever' do
    set = Scenario::LeverSet.new([
                                   Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60),
                                   Scenario::Lever::IncomeGoal.new(value: 90_000),
                                 ])
    draft = Scenario::Draft.from(@household)

    assert_equal ['John retires at age 60', 'Household income goal of $90,000/yr'], set.descriptions(draft)
  end

  test 'empty set applied to a draft leaves the projection unchanged' do
    baseline = Projection::Household.from_household(@household).periods
    draft = Scenario::Draft.from(@household)
    Scenario::LeverSet.new([]).apply(draft)

    assert_equal baseline.map(&:net_worth), draft.to_projection.periods.map(&:net_worth)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/lever_set_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::LeverSet`.

- [ ] **Step 3: Write the implementation**

Create `app/models/scenario/lever_set.rb`:

```ruby
class Scenario
  # An ordered collection of levers.
  #
  # REGISTRY is the single source of truth for which levers exist. The LLM's
  # output schema is generated from it (see Ai::Prompt::Interpretation), so the
  # model structurally cannot request a lever the engine does not implement.
  class LeverSet
    include Enumerable

    class UnknownLeverError < StandardError; end

    REGISTRY = {
      'retirement_age' => Lever::RetirementAge,
      'life_expectancy' => Lever::LifeExpectancy,
      'monthly_savings' => Lever::MonthlySavings,
      'pension_start_age' => Lever::PensionStartAge,
      'employment_end_age' => Lever::EmploymentEndAge,
      'employment_income' => Lever::EmploymentIncome,
      'account_contribution' => Lever::AccountContribution,
      'cpp_start_age' => Lever::CppStartAge,
      'oas_start_age' => Lever::OasStartAge,
      'income_goal' => Lever::IncomeGoal,
      'glidepath' => Lever::Glidepath,
    }.freeze

    attr_reader :levers

    def self.from_h(rows)
      new(Array(rows).map { |row| build_lever(row.with_indifferent_access) })
    end

    def self.build_lever(row)
      row = row.with_indifferent_access
      klass = REGISTRY[row[:lever]]
      raise UnknownLeverError, "Unknown lever: #{row[:lever]}" if klass.nil?

      args = { value: row[:value], person_id: row[:person_id] }
      args[:account_id] = row[:account_id] if klass == Lever::AccountContribution
      klass.new(**args)
    end

    def initialize(levers)
      @levers = Array(levers)
    end

    def each(&) = levers.each(&)
    def size = levers.size
    def empty? = levers.empty?

    def apply(draft)
      levers.each { |lever| lever.apply(draft) }
      draft
    end

    def descriptions(draft) = levers.map { |lever| lever.describe(draft) }

    def to_h = levers.map(&:to_h)

    # Compares this set (as parsed) against another (as confirmed).
    # This is the extraction-accuracy measurement.
    def diff(other)
      mine = index_by_identity
      theirs = other.index_by_identity

      {
        corrected: (mine.keys & theirs.keys).reject { |k| mine[k].value == theirs[k].value }.map(&:first),
        added: (theirs.keys - mine.keys).map(&:first),
        removed: (mine.keys - theirs.keys).map(&:first),
        total_parsed: size,
      }
    end

    protected

    def index_by_identity
      levers.index_by { |l| [l.key, l.person_id, l.try(:account_id)] }
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/lever_set_test.rb
```

Expected: PASS, 11 runs.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/lever_set.rb test/models/scenario/lever_set_test.rb
git add app/models/scenario/lever_set.rb test/models/scenario/lever_set_test.rb
git commit -m "feat: add Scenario::LeverSet with lever registry and diff"
```

---

## Task 10: Scenario::Comparison

**Files:**
- Create: `app/models/scenario/comparison.rb`
- Test: `test/models/scenario/comparison_test.rb`

**Interfaces:**
- Consumes: `Scenario::Draft` (Task 2), `Scenario::LeverSet` (Task 9), existing `Projection::Household`.
- Produces: `Scenario::Comparison.build(household, lever_set)`, readers `#baseline_periods`, `#scenario_periods`, methods `#peak_net_worth(periods)`, `#peak_net_worth_delta`, `#final_net_worth(periods)`, `#final_net_worth_delta`, `#depletion_year(periods)`, `#avg_retirement_income(periods)`, `#avg_retirement_income_delta`, `#key_deltas -> Array<Hash>`, `#to_h`.

> **This is the product.** Every number here comes from `Projection::Household`. `Scenario::Narrative` (Task 15) only rephrases it, so if the API is unavailable the user still gets a complete, correct answer.

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/comparison_test.rb`:

```ruby
require 'test_helper'

class Scenario::ComparisonTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  def comparison_for(levers)
    Scenario::Comparison.build(@household, Scenario::LeverSet.new(levers))
  end

  test 'an empty lever set produces zero deltas' do
    comparison = comparison_for([])

    assert_equal 0, comparison.peak_net_worth_delta
    assert_equal 0, comparison.avg_retirement_income_delta
  end

  test 'baseline periods match the unmodified projection' do
    comparison = comparison_for([])
    expected = Projection::Household.from_household(@household).periods

    assert_equal expected.map(&:net_worth), comparison.baseline_periods.map(&:net_worth)
  end

  test 'retiring earlier lowers peak net worth' do
    comparison = comparison_for([Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)])

    assert_operator comparison.peak_net_worth_delta, :<, 0
  end

  test 'saving more raises peak net worth' do
    comparison = comparison_for([Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 500)])

    assert_operator comparison.peak_net_worth_delta, :>, 0
  end

  test 'key_deltas returns labelled from/to rows' do
    comparison = comparison_for([Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)])
    labels = comparison.key_deltas.map { |d| d[:label] }

    assert_includes labels, 'Peak net worth'
    assert_includes labels, 'Average retirement income'
    assert comparison.key_deltas.all? { |d| d.key?(:from) && d.key?(:to) }
  end

  test 'depletion_year returns the first year net worth hits zero' do
    comparison = comparison_for([Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)])
    year = comparison.depletion_year(comparison.scenario_periods)

    assert_not_nil year
    assert_operator year, :>, Time.zone.now.year
  end

  test 'depletion_year is nil when savings never deplete' do
    comparison = comparison_for([Scenario::Lever::MonthlySavings.new(person_id: @john.id, value: 5000)])

    assert_nil comparison.depletion_year(comparison.scenario_periods)
  end

  test 'to_h is serialisable and contains only computed numbers' do
    comparison = comparison_for([Scenario::Lever::RetirementAge.new(person_id: @john.id, value: 60)])
    hash = comparison.to_h

    assert hash.key?(:key_deltas)
    assert hash.key?(:baseline_depletion_year)
    assert hash.key?(:scenario_depletion_year)
    assert_nothing_raised { hash.to_json }
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/comparison_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Comparison`.

- [ ] **Step 3: Write the implementation**

Create `app/models/scenario/comparison.rb`:

```ruby
class Scenario
  # A structured before/after diff of two projections.
  #
  # THIS IS THE PRODUCT. Every number here is computed by Projection::Household.
  # Scenario::Narrative only rephrases what is already in here, so a failed or
  # skipped narrative call still leaves the user with a complete answer.
  class Comparison
    attr_reader :baseline_periods, :scenario_periods

    def self.build(household, lever_set)
      baseline = Draft.from(household).to_projection.periods

      draft = Draft.from(household)
      lever_set.apply(draft)
      scenario = draft.to_projection.periods

      new(baseline, scenario)
    end

    def initialize(baseline_periods, scenario_periods)
      @baseline_periods = baseline_periods
      @scenario_periods = scenario_periods
    end

    def peak_net_worth(periods) = periods.map(&:net_worth).max || 0

    def peak_net_worth_delta
      peak_net_worth(scenario_periods) - peak_net_worth(baseline_periods)
    end

    def final_net_worth(periods) = periods.last&.net_worth || 0

    def final_net_worth_delta
      final_net_worth(scenario_periods) - final_net_worth(baseline_periods)
    end

    # First year net worth reaches zero, or nil if savings never deplete.
    def depletion_year(periods)
      periods.find { |p| p.net_worth <= 0 }&.year
    end

    # Real (today's) dollars, averaged over retirement years with income.
    def avg_retirement_income(periods)
      retirement = periods.select { |p| p.retired? && p.income_amount.positive? }
      return 0 if retirement.empty?

      retirement.sum { |p| p.deflate(p.income_amount) } / retirement.size
    end

    def avg_retirement_income_delta
      avg_retirement_income(scenario_periods) - avg_retirement_income(baseline_periods)
    end

    def key_deltas
      [
        { label: 'Peak net worth',
          from: peak_net_worth(baseline_periods),
          to: peak_net_worth(scenario_periods), },
        { label: 'Average retirement income',
          from: avg_retirement_income(baseline_periods),
          to: avg_retirement_income(scenario_periods), },
        { label: 'Final net worth',
          from: final_net_worth(baseline_periods),
          to: final_net_worth(scenario_periods), },
      ]
    end

    def to_h
      {
        key_deltas: key_deltas,
        baseline_depletion_year: depletion_year(baseline_periods),
        scenario_depletion_year: depletion_year(scenario_periods),
      }
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/comparison_test.rb
```

Expected: PASS, 8 runs.

- [ ] **Step 5: Run the whole scenario suite as a regression check**

```bash
bin/rails test test/models/scenario test/models/scenario_test.rb
```

Expected: PASS, every test from Tasks 1-10.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop -a app/models/scenario/comparison.rb test/models/scenario/comparison_test.rb
git add app/models/scenario/comparison.rb test/models/scenario/comparison_test.rb
git commit -m "feat: add Scenario::Comparison for engine-computed before/after deltas"
```

> **Checkpoint.** Tasks 1-10 are the complete deterministic core. There is no AI in the codebase yet, and the full what-if capability already works end to end through Ruby. Everything after this point adds language understanding on top of a working feature.

---

## Task 11: LlmCall model and migration

**Files:**
- Create: `db/migrate/<timestamp>_create_llm_calls.rb`
- Create: `app/models/llm_call.rb`
- Modify: `app/models/scenario.rb`
- Test: `test/models/llm_call_test.rb`

**Interfaces:**
- Consumes: `Scenario` (Task 1).
- Produces: `LlmCall` (ActiveRecord) with `.spend_micros_this_month`, `.record!(scenario:, step:, model:, input_tokens:, output_tokens:, cache_read_tokens:, latency_ms:, success: true, error_message: nil)`, `.cost_micros_for(model, input, output, cached)`, `#cost_dollars`. Constants `LlmCall::PRICING`, `LlmCall::STEPS`.

> **Note on `cost_micros`:** a deliberate deviation from the project's integer-dollars rule. These values are fractions of a cent, so dollars would round everything to zero. Millionths of a dollar keeps per-call costs meaningful.

- [ ] **Step 1: Generate the migration**

```bash
bin/rails generate migration CreateLlmCalls
```

- [ ] **Step 2: Write the migration**

Replace the generated file's contents with:

```ruby
class CreateLlmCalls < ActiveRecord::Migration[8.0]
  def change
    create_table :llm_calls do |t|
      t.references :scenario, foreign_key: true
      t.string :step, null: false
      t.string :model, null: false
      t.integer :input_tokens, default: 0, null: false
      t.integer :output_tokens, default: 0, null: false
      t.integer :cache_read_tokens, default: 0, null: false
      t.integer :cost_micros, default: 0, null: false
      t.integer :latency_ms, default: 0, null: false
      t.boolean :success, default: true, null: false
      t.text :error_message

      t.timestamps
    end

    add_index :llm_calls, :created_at
    add_index :llm_calls, :step
  end
end
```

- [ ] **Step 3: Run the migration**

```bash
bin/rails db:migrate
```

- [ ] **Step 4: Write the failing test**

Create `test/models/llm_call_test.rb`:

```ruby
require 'test_helper'

class LlmCallTest < ActiveSupport::TestCase
  setup do
    @scenario = Scenario.create!(household: households(:non_retired), raw_input: 'retire at 60')
  end

  test 'requires step and model' do
    call = LlmCall.new
    assert_not call.valid?
    assert_includes call.errors[:step], "can't be blank"
    assert_includes call.errors[:model], "can't be blank"
  end

  test 'record! stores usage and computes cost for haiku' do
    call = LlmCall.record!(
      scenario: @scenario, step: :interpretation, model: 'claude-haiku-4-5',
      input_tokens: 1_000_000, output_tokens: 0, cache_read_tokens: 0, latency_ms: 900
    )

    # Haiku 4.5: $1.00 per million input tokens = 1_000_000 micros
    assert_equal 1_000_000, call.cost_micros
    assert_in_delta 1.0, call.cost_dollars, 0.0001
  end

  test 'record! prices output tokens higher than input' do
    call = LlmCall.record!(
      scenario: @scenario, step: :interpretation, model: 'claude-haiku-4-5',
      input_tokens: 0, output_tokens: 1_000_000, cache_read_tokens: 0, latency_ms: 900
    )

    # Haiku 4.5: $5.00 per million output tokens
    assert_equal 5_000_000, call.cost_micros
  end

  test 'record! prices cached reads at one tenth of input' do
    call = LlmCall.record!(
      scenario: @scenario, step: :interpretation, model: 'claude-haiku-4-5',
      input_tokens: 0, output_tokens: 0, cache_read_tokens: 1_000_000, latency_ms: 900
    )

    assert_equal 100_000, call.cost_micros
  end

  test 'record! stores a failure' do
    call = LlmCall.record!(
      scenario: @scenario, step: :interpretation, model: 'claude-haiku-4-5',
      input_tokens: 0, output_tokens: 0, cache_read_tokens: 0, latency_ms: 30,
      success: false, error_message: 'timeout'
    )

    assert_not call.success?
    assert_equal 'timeout', call.error_message
  end

  test 'spend_micros_this_month sums only the current month' do
    LlmCall.record!(scenario: @scenario, step: :interpretation, model: 'claude-haiku-4-5',
                    input_tokens: 1_000_000, output_tokens: 0, cache_read_tokens: 0, latency_ms: 1)
    old = LlmCall.record!(scenario: @scenario, step: :interpretation, model: 'claude-haiku-4-5',
                          input_tokens: 5_000_000, output_tokens: 0, cache_read_tokens: 0, latency_ms: 1)
    old.update_column(:created_at, 2.months.ago)

    assert_equal 1_000_000, LlmCall.spend_micros_this_month
  end

  test 'destroying a scenario destroys its llm calls' do
    LlmCall.record!(scenario: @scenario, step: :interpretation, model: 'claude-haiku-4-5',
                    input_tokens: 10, output_tokens: 10, cache_read_tokens: 0, latency_ms: 1)

    assert_difference 'LlmCall.count', -1 do
      @scenario.destroy
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it fails**

```bash
bin/rails test test/models/llm_call_test.rb
```

Expected: FAIL — `NameError: uninitialized constant LlmCall`.

- [ ] **Step 6: Write the model**

Create `app/models/llm_call.rb`:

```ruby
# One call to the Anthropic API: what it cost, how long it took, whether it
# worked. Written for every call without exception, which is what lets Ai::Budget
# enforce a spend ceiling from the same data.
#
# cost_micros is millionths of a dollar. This deliberately departs from the
# project convention of storing money as integer dollars: a single call costs a
# fraction of a cent, which integer dollars would round to zero. That convention
# governs user-facing financial modelling, not internal telemetry.
class LlmCall < ApplicationRecord
  include Inspectable

  # Dollars per million tokens. Haiku 4.5 is $1.00 input / $5.00 output.
  # Cached reads bill at 10% of the input rate.
  PRICING = {
    'claude-haiku-4-5' => { input: 1.0, output: 5.0 },
    'claude-sonnet-5' => { input: 3.0, output: 15.0 },
  }.freeze

  CACHE_READ_DISCOUNT = 0.1

  STEPS = %w[interpretation narrative].freeze

  belongs_to :scenario, optional: true

  validates :step, presence: true, inclusion: { in: STEPS }
  validates :model, presence: true

  inspectable :step, :model, :cost_micros, :latency_ms

  scope :this_month, -> { where(created_at: Time.current.beginning_of_month..) }

  def self.spend_micros_this_month = this_month.sum(:cost_micros)

  # rubocop:disable Metrics/ParameterLists
  def self.record!(scenario:, step:, model:, input_tokens:, output_tokens:, cache_read_tokens:,
                   latency_ms:, success: true, error_message: nil)
    create!(
      scenario: scenario, step: step.to_s, model: model,
      input_tokens: input_tokens, output_tokens: output_tokens,
      cache_read_tokens: cache_read_tokens, latency_ms: latency_ms,
      success: success, error_message: error_message,
      cost_micros: cost_micros_for(model, input_tokens, output_tokens, cache_read_tokens)
    )
  end
  # rubocop:enable Metrics/ParameterLists

  def self.cost_micros_for(model, input_tokens, output_tokens, cache_read_tokens)
    rates = PRICING[model]
    return 0 if rates.nil?

    ((input_tokens * rates[:input]) +
      (output_tokens * rates[:output]) +
      (cache_read_tokens * rates[:input] * CACHE_READ_DISCOUNT)).round
  end

  def cost_dollars = cost_micros / 1_000_000.0
end
```

- [ ] **Step 7: Add the association to Scenario**

In `app/models/scenario.rb`, immediately after `belongs_to :household`:

```ruby
  has_many :llm_calls, dependent: :destroy
```

- [ ] **Step 8: Run both model tests**

```bash
bin/rails test test/models/llm_call_test.rb test/models/scenario_test.rb
```

Expected: PASS, 13 runs.

- [ ] **Step 9: Annotate, lint and commit**

```bash
bin/rails annotate
bin/rubocop -a app/models/llm_call.rb app/models/scenario.rb test/models/llm_call_test.rb
git add db/migrate db/schema.rb app/models/llm_call.rb app/models/scenario.rb test/models/llm_call_test.rb
git commit -m "feat: add LlmCall model for API usage and cost instrumentation"
```

---

## Task 12: Ai::Budget

**Files:**
- Create: `app/models/ai.rb`
- Create: `app/models/ai/budget.rb`
- Test: `test/models/ai/budget_test.rb`

**Interfaces:**
- Consumes: `LlmCall` (Task 11).
- Produces: `Ai::Budget.new(monthly_limit_micros:)`, `.default`, `#exceeded?`, `#remaining_micros`, `#spent_micros`, `#monthly_limit_micros`, and `Ai::Budget::DEFAULT_MONTHLY_LIMIT_MICROS` (20_000_000, i.e. $20).

- [ ] **Step 1: Write the failing test**

Create `test/models/ai/budget_test.rb`:

```ruby
require 'test_helper'

class Ai::BudgetTest < ActiveSupport::TestCase
  setup do
    @scenario = Scenario.create!(household: households(:non_retired), raw_input: 'retire at 60')
  end

  def spend(micros)
    LlmCall.create!(scenario: @scenario, step: 'interpretation', model: 'claude-haiku-4-5',
                    cost_micros: micros, latency_ms: 1)
  end

  test 'is not exceeded when nothing has been spent' do
    assert_not Ai::Budget.new(monthly_limit_micros: 1_000_000).exceeded?
  end

  test 'is exceeded once spend reaches the limit' do
    spend(1_000_000)

    assert Ai::Budget.new(monthly_limit_micros: 1_000_000).exceeded?
  end

  test 'is not exceeded just below the limit' do
    spend(999_999)

    assert_not Ai::Budget.new(monthly_limit_micros: 1_000_000).exceeded?
  end

  test 'remaining_micros never goes negative' do
    spend(5_000_000)

    assert_equal 0, Ai::Budget.new(monthly_limit_micros: 1_000_000).remaining_micros
  end

  test 'ignores spend from previous months' do
    old = spend(9_000_000)
    old.update_column(:created_at, 2.months.ago)

    assert_not Ai::Budget.new(monthly_limit_micros: 1_000_000).exceeded?
  end

  test 'default limit is twenty dollars' do
    assert_equal 20_000_000, Ai::Budget::DEFAULT_MONTHLY_LIMIT_MICROS
    assert_equal 20_000_000, Ai::Budget.default.monthly_limit_micros
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/ai/budget_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Ai`.

- [ ] **Step 3: Write the namespace**

Create `app/models/ai.rb`:

```ruby
# Namespace for the only code in the application that knows Anthropic exists.
#
# Everything under Scenario is deterministic and testable without an API key.
# Everything under Ai is infrastructure: HTTP, prompts, budgets, logging.
module Ai
end
```

- [ ] **Step 4: Write the budget**

Create `app/models/ai/budget.rb`:

```ruby
module Ai
  # Monthly spend circuit breaker.
  #
  # Reads from the same llm_calls table written for instrumentation, so the
  # measurement and the enforcement can never disagree.
  class Budget
    DEFAULT_MONTHLY_LIMIT_MICROS = 20_000_000 # $20.00

    attr_reader :monthly_limit_micros

    def self.default = new(monthly_limit_micros: DEFAULT_MONTHLY_LIMIT_MICROS)

    def initialize(monthly_limit_micros:)
      @monthly_limit_micros = monthly_limit_micros
    end

    def spent_micros = LlmCall.spend_micros_this_month

    def exceeded? = spent_micros >= monthly_limit_micros

    def remaining_micros = [monthly_limit_micros - spent_micros, 0].max
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rails test test/models/ai/budget_test.rb
```

Expected: PASS, 6 runs.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop -a app/models/ai.rb app/models/ai/budget.rb test/models/ai/budget_test.rb
git add app/models/ai.rb app/models/ai/budget.rb test/models/ai/budget_test.rb
git commit -m "feat: add Ai::Budget monthly spend circuit breaker"
```

---

## Task 13: Anthropic client

**Files:**
- Modify: `Gemfile`
- Modify: `.envrc.example`
- Create: `app/models/ai/client.rb`
- Create: `test/support/fake_anthropic.rb`
- Test: `test/models/ai/client_test.rb`

**Interfaces:**
- Consumes: `LlmCall` (Task 11), `Ai::Budget` (Task 12).
- Produces: `Ai::Client.new(transport: nil, budget: Ai::Budget.default)`, `#call(step:, system_prompt:, user_content:, schema:, scenario: nil) -> Hash`. Raises `Ai::Client::BudgetExceededError`, `Ai::Client::ApiError`. Constants `Ai::Client::MODEL = 'claude-haiku-4-5'`, `Ai::Client::MAX_TOKENS = 1024`.
- Produces for tests: `FakeAnthropic.new(response_body:, usage:, raises:)` responding to `#create(**)` and exposing `#calls`.

> **VERIFY THE SDK BINDING BEFORE WRITING `#call`.** The Ruby SDK is the least-documented Anthropic SDK. Run:
>
> ```bash
> bundle exec ruby -e 'require "anthropic"; puts Anthropic::Client.new.messages.method(:create).parameters.inspect'
> ```
>
> and check the installed gem's own `examples/` directory for the structured-output parameter name. The code below assumes `output_config: { format: { type: 'json_schema', schema: ... } }`.
>
> **If that parameter is rejected, use tool use with `strict: true` instead** — define one tool whose `input_schema` is the schema, set `tool_choice: { type: 'tool', name: 'record_scenario' }`, and read the result from the `tool_use` block's `input` rather than from a text block. Both approaches give the same guarantee; only the extraction differs. Adjust `dispatch` and `parse_response` accordingly, update `FakeAnthropic` to return a matching shape, and note which path you took in the commit message.

- [ ] **Step 1: Add the gem**

In `Gemfile`, after the `gem 'stripe'` line:

```ruby
# Claude API client for the natural-language scenario builder
gem 'anthropic'
```

Then:

```bash
bundle install
```

- [ ] **Step 2: Document the environment variable**

Add to `.envrc.example`:

```bash
# Anthropic API key for the natural-language scenario builder.
# Get one at https://console.anthropic.com/ and SET A SPEND CAP there before use.
export ANTHROPIC_API_KEY="sk-ant-..."
```

- [ ] **Step 3: Write the test double**

Create `test/support/fake_anthropic.rb`:

```ruby
# Stands in for the Anthropic SDK client in tests.
#
# No test may reach the real API except the one gated behind LIVE_AI=1.
class FakeAnthropic
  Usage = Struct.new(:input_tokens, :output_tokens, :cache_read_input_tokens, keyword_init: true)
  TextBlock = Struct.new(:type, :text, keyword_init: true)
  Response = Struct.new(:content, :usage, keyword_init: true)

  attr_reader :calls

  def initialize(response_body: { 'changes' => [], 'unrecognized_input' => nil },
                 usage: { input_tokens: 1200, output_tokens: 150, cache_read_input_tokens: 0 },
                 raises: nil,
                 raw_text: nil)
    @response_body = response_body
    @usage = usage
    @raises = raises
    @raw_text = raw_text
    @calls = []
  end

  def create(**kwargs)
    @calls << kwargs
    raise @raises if @raises

    Response.new(
      content: [TextBlock.new(type: :text, text: @raw_text || @response_body.to_json)],
      usage: Usage.new(**@usage)
    )
  end
end
```

- [ ] **Step 4: Write the failing test**

Create `test/models/ai/client_test.rb`:

```ruby
require 'test_helper'
require_relative '../../support/fake_anthropic'

class Ai::ClientTest < ActiveSupport::TestCase
  setup do
    @scenario = Scenario.create!(household: households(:non_retired), raw_input: 'retire at 60')
    @schema = { 'type' => 'object', 'properties' => {} }
  end

  def call_with(transport, budget: Ai::Budget.default)
    Ai::Client.new(transport: transport, budget: budget).call(
      step: :interpretation,
      system_prompt: 'You extract levers.',
      user_content: 'retire at 60',
      schema: @schema,
      scenario: @scenario
    )
  end

  test 'returns the parsed JSON body' do
    fake = FakeAnthropic.new(response_body: { 'changes' => [{ 'lever' => 'retirement_age' }] })

    assert_equal [{ 'lever' => 'retirement_age' }], call_with(fake)['changes']
  end

  test 'records an LlmCall with usage' do
    fake = FakeAnthropic.new(usage: { input_tokens: 1000, output_tokens: 100, cache_read_input_tokens: 500 })

    assert_difference 'LlmCall.count', 1 do
      call_with(fake)
    end

    call = LlmCall.last
    assert_equal 'interpretation', call.step
    assert_equal Ai::Client::MODEL, call.model
    assert_equal 1000, call.input_tokens
    assert_equal 100, call.output_tokens
    assert_equal 500, call.cache_read_tokens
    assert call.success?
    assert_equal @scenario, call.scenario
  end

  test 'sends the model, max tokens and a cached system prompt' do
    fake = FakeAnthropic.new
    call_with(fake)
    sent = fake.calls.first

    assert_equal Ai::Client::MODEL, sent[:model]
    assert_equal Ai::Client::MAX_TOKENS, sent[:max_tokens]
    assert_equal({ type: 'ephemeral' }, sent[:system_][0][:cache_control])
  end

  test 'raises and records a failure when the transport raises' do
    fake = FakeAnthropic.new(raises: StandardError.new('boom'))

    assert_difference 'LlmCall.count', 1 do
      assert_raises(Ai::Client::ApiError) { call_with(fake) }
    end

    call = LlmCall.last
    assert_not call.success?
    assert_equal 'boom', call.error_message
  end

  test 'raises BudgetExceededError without calling the transport' do
    LlmCall.create!(scenario: @scenario, step: 'interpretation', model: Ai::Client::MODEL,
                    cost_micros: 5_000_000, latency_ms: 1)
    fake = FakeAnthropic.new

    assert_raises(Ai::Client::BudgetExceededError) do
      call_with(fake, budget: Ai::Budget.new(monthly_limit_micros: 1_000_000))
    end
    assert_empty fake.calls
  end

  test 'raises ApiError on unparseable JSON' do
    fake = FakeAnthropic.new(raw_text: 'not json at all')

    assert_raises(Ai::Client::ApiError) { call_with(fake) }
  end
end
```

- [ ] **Step 5: Run the test to verify it fails**

```bash
bin/rails test test/models/ai/client_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Ai::Client`.

- [ ] **Step 6: Write the client**

Create `app/models/ai/client.rb`:

```ruby
module Ai
  # The single egress point to the Anthropic API.
  #
  # Every call goes through here so that budget enforcement and usage logging
  # cannot be forgotten at a call site. Nothing else in the application may
  # construct an Anthropic client directly.
  class Client
    class ApiError < StandardError; end
    class BudgetExceededError < StandardError; end

    MODEL = 'claude-haiku-4-5'.freeze
    MAX_TOKENS = 1024

    def initialize(transport: nil, budget: Budget.default)
      @transport = transport
      @budget = budget
    end

    # Returns the parsed JSON object the model produced.
    def call(step:, system_prompt:, user_content:, schema:, scenario: nil)
      raise BudgetExceededError, 'Monthly AI budget reached' if @budget.exceeded?

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = dispatch(system_prompt, user_content, schema)
      parsed = parse_response(response)
      record(step, scenario, response, elapsed_ms(started))
      parsed
    rescue BudgetExceededError
      raise
    rescue StandardError => e
      record_failure(step, scenario, e, elapsed_ms(started))
      raise ApiError, e.message
    end

    private

    def transport = @transport ||= Anthropic::Client.new.messages

    def dispatch(system_prompt, user_content, schema)
      transport.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system_: [{ type: 'text', text: system_prompt, cache_control: { type: 'ephemeral' } }],
        output_config: { format: { type: 'json_schema', schema: schema } },
        messages: [{ role: 'user', content: user_content }]
      )
    end

    def parse_response(response)
      block = response.content.find { |b| b.type.to_s == 'text' }
      raise ApiError, 'No text block in response' if block.nil?

      JSON.parse(block.text)
    rescue JSON::ParserError => e
      raise ApiError, "Unparseable response: #{e.message}"
    end

    def record(step, scenario, response, latency_ms)
      usage = response.usage
      LlmCall.record!(
        scenario: scenario, step: step, model: MODEL,
        input_tokens: usage.input_tokens.to_i,
        output_tokens: usage.output_tokens.to_i,
        cache_read_tokens: usage.cache_read_input_tokens.to_i,
        latency_ms: latency_ms
      )
    end

    def record_failure(step, scenario, error, latency_ms)
      LlmCall.record!(
        scenario: scenario, step: step, model: MODEL,
        input_tokens: 0, output_tokens: 0, cache_read_tokens: 0,
        latency_ms: latency_ms, success: false, error_message: error.message
      )
    end

    def elapsed_ms(started)
      return 0 if started.nil?

      ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
    end
  end
end
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
bin/rails test test/models/ai/client_test.rb
```

Expected: PASS, 7 runs. If `output_config` is rejected by the installed SDK, switch to the tool-use fallback described in the task preamble and re-run.

- [ ] **Step 8: Lint and commit**

```bash
bin/rubocop -a app/models/ai/client.rb test/models/ai/client_test.rb test/support/fake_anthropic.rb
git add Gemfile Gemfile.lock .envrc.example app/models/ai/client.rb test/models/ai/client_test.rb test/support/fake_anthropic.rb
git commit -m "feat: add Ai::Client as the single Anthropic API egress point"
```

---

## Task 14: Interpretation prompt and validation gates

**Files:**
- Create: `app/models/ai/prompt.rb`
- Create: `app/models/ai/prompt/interpretation.rb`
- Create: `app/models/scenario/interpretation.rb`
- Test: `test/models/ai/prompt/interpretation_test.rb`
- Test: `test/models/scenario/interpretation_test.rb`

**Interfaces:**
- Consumes: `Scenario::LeverSet` (Task 9), `Scenario::PersonResolver` (Task 3), `Scenario::Draft` (Task 2).
- Produces: `Ai::Prompt::Interpretation.system_prompt -> String`, `.schema -> Hash`, `.user_content(household, raw_input) -> String`, `.LEVER_DESCRIPTIONS`. And `Scenario::Interpretation.from_response(response_hash, household:, current_user:) -> Scenario::Interpretation` with `#lever_set`, `#ambiguous?`, `#clarifying_question`, `#unrecognized_input`, `#problems`.

> **The four validation gates live in `Scenario::Interpretation`:** schema conformance (re-checked, never trusted), person resolution, domain validity (apply to a draft record and call `.valid?` — `Benefit::Cpp` already rejects age 75), and confidence. Any failure makes the interpretation ambiguous and produces a clarifying question rather than a projection.
>
> `Scenario::Interpretation` takes a plain Hash and knows nothing about Anthropic, so every test below runs with no API and no stubbing.

- [ ] **Step 1: Write the failing prompt test**

Create `test/models/ai/prompt/interpretation_test.rb`:

```ruby
require 'test_helper'

class Ai::Prompt::InterpretationTest < ActiveSupport::TestCase
  test 'schema enumerates exactly the registered levers' do
    enum = Ai::Prompt::Interpretation.schema
                                     .dig('properties', 'changes', 'items', 'properties', 'lever', 'enum')

    assert_equal Scenario::LeverSet::REGISTRY.keys.sort, enum.sort
  end

  test 'schema forbids additional properties' do
    schema = Ai::Prompt::Interpretation.schema

    assert_equal false, schema['additionalProperties']
    assert_equal false, schema.dig('properties', 'changes', 'items', 'additionalProperties')
  end

  test 'schema requires an unrecognized_input field' do
    assert_includes Ai::Prompt::Interpretation.schema['required'], 'unrecognized_input'
  end

  test 'system prompt names every lever' do
    prompt = Ai::Prompt::Interpretation.system_prompt

    Scenario::LeverSet::REGISTRY.each_key { |key| assert_includes prompt, key }
  end

  test 'system prompt forbids inventing values' do
    assert_match(/never infer/i, Ai::Prompt::Interpretation.system_prompt)
  end

  test 'system prompt is stable across calls so it can be cached' do
    assert_equal Ai::Prompt::Interpretation.system_prompt, Ai::Prompt::Interpretation.system_prompt
  end

  test 'user content includes household members without database ids' do
    content = Ai::Prompt::Interpretation.user_content(households(:non_retired), 'retire at 60')

    assert_includes content, 'John'
    assert_includes content, 'Jane'
    assert_includes content, 'retire at 60'
    assert_not_includes content, users(:working_user_john).id.to_s
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/models/ai/prompt/interpretation_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Ai::Prompt`.

- [ ] **Step 3: Write the prompt namespace and interpretation prompt**

Create `app/models/ai/prompt.rb`:

```ruby
module Ai
  # System prompts and JSON schemas. One module per call type.
  module Prompt
  end
end
```

Create `app/models/ai/prompt/interpretation.rb`:

```ruby
module Ai
  module Prompt
    # System prompt and JSON schema for turning a plain-language what-if into
    # structured levers.
    #
    # The schema's lever enum is generated from Scenario::LeverSet::REGISTRY, so
    # the model structurally cannot request a lever the engine does not
    # implement. Anything it cannot map lands in unrecognized_input instead.
    module Interpretation
      LEVER_DESCRIPTIONS = {
        'retirement_age' => 'the age a person stops working (value: age in years)',
        'life_expectancy' => 'how long a person expects to live (value: age in years)',
        'monthly_savings' => 'a change to monthly savings (value: dollars per month, may be negative)',
        'pension_start_age' => 'when a workplace pension starts (value: age in years)',
        'employment_end_age' => 'when post-retirement work stops (value: age in years)',
        'employment_income' => 'annual post-retirement employment income (value: dollars per year)',
        'account_contribution' => 'annual contribution to one named account (value: dollars per year)',
        'cpp_start_age' => 'when CPP starts (value: age 60-70)',
        'oas_start_age' => 'when OAS starts (value: age 65-70)',
        'income_goal' => 'the household retirement income goal (value: dollars per year)',
        'glidepath' => 'the investment strategy (value: a glidepath id)',
      }.freeze

      def self.schema
        {
          'type' => 'object',
          'additionalProperties' => false,
          'required' => %w[changes unrecognized_input],
          'properties' => {
            'changes' => {
              'type' => 'array',
              'items' => {
                'type' => 'object',
                'additionalProperties' => false,
                'required' => %w[lever value confidence],
                'properties' => {
                  'lever' => { 'type' => 'string', 'enum' => Scenario::LeverSet::REGISTRY.keys },
                  'person' => {
                    'type' => %w[string null],
                    'description' => 'self, spouse, or a first name. Null for household-wide levers.',
                  },
                  'value' => { 'type' => 'number' },
                  'confidence' => { 'type' => 'string', 'enum' => %w[high medium low] },
                },
              },
            },
            'unrecognized_input' => {
              'type' => %w[string null],
              'description' => 'Anything the user asked for that does not map to a lever. Null if everything mapped.',
            },
          },
        }
      end

      def self.system_prompt
        <<~PROMPT
          You translate plain-language retirement questions into structured parameters
          for a Canadian retirement planning tool. You do not perform any calculation.

          Extract only the changes the user explicitly stated. NEVER INFER a value the
          user did not give you, and never estimate a number. If a request does not map
          cleanly onto one of the levers below, put it in unrecognized_input instead of
          forcing it into a lever.

          Available levers:
          #{LEVER_DESCRIPTIONS.map { |key, desc| "  #{key}: #{desc}" }.join("\n")}

          Rules:
          - person must be "self", "spouse", or a first name from the household. Use
            null for income_goal and glidepath, which apply to the whole household.
          - Set confidence to "low" whenever you are unsure which lever, which person,
            or which value was meant. A low-confidence answer triggers a follow-up
            question, which is always better than a confident guess.
          - One-time purchases, house sales, inheritances, and windfalls CANNOT be
            modelled. Put them in unrecognized_input.
          - Return an empty changes array if nothing maps.
        PROMPT
      end

      def self.user_content(household, raw_input)
        members = household.users.map { |u| "#{u.first_name} (age #{u.age})" }.join(', ')
        <<~CONTENT
          Household members: #{members}
          User said: "#{raw_input}"
        CONTENT
      end
    end
  end
end
```

- [ ] **Step 4: Run the prompt test to verify it passes**

```bash
bin/rails test test/models/ai/prompt/interpretation_test.rb
```

Expected: PASS, 7 runs.

- [ ] **Step 5: Write the failing interpretation test**

Create `test/models/scenario/interpretation_test.rb`:

```ruby
require 'test_helper'

class Scenario::InterpretationTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  def interpret(response)
    Scenario::Interpretation.from_response(response, household: @household, current_user: @john)
  end

  def change(overrides = {})
    { 'lever' => 'retirement_age', 'person' => 'self', 'value' => 60, 'confidence' => 'high' }.merge(overrides)
  end

  test 'builds a lever set with resolved person ids' do
    result = interpret({ 'changes' => [change], 'unrecognized_input' => nil })

    assert_not result.ambiguous?
    assert_equal 1, result.lever_set.size
    assert_equal @john.id, result.lever_set.first.person_id
    assert_equal 60, result.lever_set.first.value
  end

  test 'resolves spouse' do
    result = interpret({ 'changes' => [change('person' => 'spouse')], 'unrecognized_input' => nil })

    assert_equal users(:working_user_jane).id, result.lever_set.first.person_id
  end

  test 'household levers need no person' do
    result = interpret({ 'changes' => [change('lever' => 'income_goal', 'person' => nil, 'value' => 90_000)],
                         'unrecognized_input' => nil, })

    assert_not result.ambiguous?
    assert_nil result.lever_set.first.person_id
  end

  test 'low confidence makes it ambiguous' do
    result = interpret({ 'changes' => [change('confidence' => 'low')], 'unrecognized_input' => nil })

    assert result.ambiguous?
    assert_match(/not sure/i, result.clarifying_question)
  end

  test 'unrecognized input makes it ambiguous and is quoted back' do
    result = interpret({ 'changes' => [change], 'unrecognized_input' => 'buy a place in Kelowna for $650k' })

    assert result.ambiguous?
    assert_match(/Kelowna/, result.clarifying_question)
    assert_match(/can't model/i, result.clarifying_question)
  end

  test 'an unresolvable person makes it ambiguous' do
    result = interpret({ 'changes' => [change('person' => 'Gandalf')], 'unrecognized_input' => nil })

    assert result.ambiguous?
    assert_match(/Gandalf/, result.clarifying_question)
  end

  test 'an unknown lever makes it ambiguous rather than raising' do
    result = interpret({ 'changes' => [change('lever' => 'buy_a_house')], 'unrecognized_input' => nil })

    assert result.ambiguous?
  end

  test 'an out of range CPP age is rejected by the model validation' do
    result = interpret({ 'changes' => [change('lever' => 'cpp_start_age', 'value' => 75)],
                         'unrecognized_input' => nil, })

    assert result.ambiguous?
    assert_match(/start age/i, result.clarifying_question)
  end

  test 'a valid CPP age passes' do
    result = interpret({ 'changes' => [change('lever' => 'cpp_start_age', 'value' => 70)],
                         'unrecognized_input' => nil, })

    assert_not result.ambiguous?
  end

  test 'no changes at all is ambiguous' do
    result = interpret({ 'changes' => [], 'unrecognized_input' => nil })

    assert result.ambiguous?
  end

  test 'a clean interpretation has no clarifying question' do
    result = interpret({ 'changes' => [change], 'unrecognized_input' => nil })

    assert_nil result.clarifying_question
  end
end
```

- [ ] **Step 6: Run it to verify it fails**

```bash
bin/rails test test/models/scenario/interpretation_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Scenario::Interpretation`.

- [ ] **Step 7: Write the interpretation**

Create `app/models/scenario/interpretation.rb`:

```ruby
class Scenario
  # What the model understood from a user's sentence, after validation.
  #
  # Four gates run here, in order. Any failure makes the interpretation
  # ambiguous, which produces a clarifying question instead of a projection:
  #
  #   1. Schema conformance - re-checked server side; the wire is never trusted
  #   2. Person resolution  - "self"/"spouse"/name resolved by PersonResolver
  #   3. Domain validity    - the lever is applied to a throwaway draft and the
  #                           record's own validations are run (Benefit::Cpp
  #                           already rejects age 75, so nothing is restated here)
  #   4. Confidence         - any low-confidence lever, or leftover text
  #
  # This class knows nothing about Anthropic. It takes a plain Hash, so it is
  # fully testable with no API and no stubbing.
  class Interpretation
    attr_reader :lever_set, :unrecognized_input, :problems

    def self.from_response(response, household:, current_user:)
      Builder.new(response.to_h.with_indifferent_access, household, current_user).build
    end

    def initialize(lever_set:, unrecognized_input: nil, problems: [], low_confidence: false)
      @lever_set = lever_set
      @unrecognized_input = unrecognized_input
      @problems = problems
      @low_confidence = low_confidence
    end

    def ambiguous?
      problems.any? || unrecognized_input.present? || @low_confidence || lever_set.empty?
    end

    def clarifying_question
      return nil unless ambiguous?

      parts = []
      parts << "I can't model this yet: #{unrecognized_input}." if unrecognized_input.present?
      parts.concat(problems)
      parts << "I'm not sure I understood that correctly. Could you rephrase it?" if @low_confidence
      parts << 'I could not find anything to change. Could you rephrase that?' if parts.empty?
      parts.join(' ')
    end

    # Translates a raw response hash into a validated Interpretation.
    class Builder
      def initialize(body, household, current_user)
        @body = body
        @household = household
        @resolver = PersonResolver.new(household, current_user)
        @problems = []
        @low_confidence = false
      end

      def build
        levers = Array(@body[:changes]).filter_map { |row| build_lever(row) }

        Interpretation.new(
          lever_set: LeverSet.new(levers),
          unrecognized_input: @body[:unrecognized_input].presence,
          problems: @problems,
          low_confidence: @low_confidence
        )
      end

      private

      def build_lever(row)
        @low_confidence = true if row[:confidence].to_s == 'low'

        person_id = resolve_person(row)
        return nil if person_id == :error

        lever = LeverSet.build_lever(lever_attributes(row, person_id))
        validate(lever) ? lever : nil
      rescue LeverSet::UnknownLeverError => e
        @problems << e.message
        nil
      end

      def resolve_person(row)
        return nil if row[:person].blank?

        @resolver.resolve(row[:person]).id
      rescue PersonResolver::AmbiguousPersonError => e
        @problems << e.message
        :error
      end

      def lever_attributes(row, person_id)
        attrs = { lever: row[:lever], person_id: person_id, value: row[:value]&.round }
        attrs[:account_id] = row[:account_id] if row[:lever] == 'account_contribution'
        attrs.with_indifferent_access
      end

      # Gate 3: apply to a throwaway draft and let the records' own validations
      # decide. Range rules live on the models, not here.
      def validate(lever)
        probe = Draft.from(@household)
        lever.apply(probe)
        invalid = (probe.users + probe.benefits + probe.pensions + probe.accounts).reject(&:valid?)
        return true if invalid.empty?

        @problems << invalid.first.errors.full_messages.first
        false
      end
    end
  end
end
```

- [ ] **Step 8: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/interpretation_test.rb
```

Expected: PASS, 11 runs.

- [ ] **Step 9: Lint and commit**

```bash
bin/rubocop -a app/models/ai/prompt.rb app/models/ai/prompt app/models/scenario/interpretation.rb test/models/ai/prompt test/models/scenario/interpretation_test.rb
git add app/models/ai/prompt.rb app/models/ai/prompt app/models/scenario/interpretation.rb test/models/ai/prompt test/models/scenario/interpretation_test.rb
git commit -m "feat: add interpretation prompt, schema and validation gates"
```

---

## Task 15: Narrative

**Files:**
- Create: `app/models/ai/prompt/narrative.rb`
- Create: `app/models/scenario/narrative.rb`
- Test: `test/models/scenario/narrative_test.rb`

**Interfaces:**
- Consumes: `Scenario::Comparison` (Task 10), `Ai::Client` (Task 13).
- Produces: `Ai::Prompt::Narrative.system_prompt`, `.schema`, `.user_content(comparison)`. And `Scenario::Narrative.for(comparison, scenario: nil, client: Ai::Client.new) -> Scenario::Narrative | nil` with `#summary`.

> **The narrative receives only numbers the engine already computed** and is told to copy figures rather than derive them. Any failure returns `nil` and the results page renders without it — the comparison table is the answer, the prose is decoration. `.for` swallows `Ai::Client::ApiError` and `BudgetExceededError` deliberately so no caller has to.

- [ ] **Step 1: Write the failing test**

Create `test/models/scenario/narrative_test.rb`:

```ruby
require 'test_helper'
require_relative '../../support/fake_anthropic'

class Scenario::NarrativeTest < ActiveSupport::TestCase
  setup do
    @household = households(:non_retired)
    @scenario = Scenario.create!(household: @household, raw_input: 'retire at 60')
    @comparison = Scenario::Comparison.build(
      @household,
      Scenario::LeverSet.new([Scenario::Lever::RetirementAge.new(person_id: users(:working_user_john).id, value: 60)])
    )
  end

  def client_for(body)
    Ai::Client.new(transport: FakeAnthropic.new(response_body: body))
  end

  test 'builds a narrative from the response' do
    client = client_for({ 'summary' => 'Retiring five years earlier lowers your peak net worth.' })
    narrative = Scenario::Narrative.for(@comparison, scenario: @scenario, client: client)

    assert_equal 'Retiring five years earlier lowers your peak net worth.', narrative.summary
  end

  test 'records the call against the narrative step' do
    client = client_for({ 'summary' => 'Anything.' })

    assert_difference 'LlmCall.count', 1 do
      Scenario::Narrative.for(@comparison, scenario: @scenario, client: client)
    end

    assert_equal 'narrative', LlmCall.last.step
  end

  test 'returns nil when the API fails' do
    client = Ai::Client.new(transport: FakeAnthropic.new(raises: StandardError.new('down')))

    assert_nil Scenario::Narrative.for(@comparison, scenario: @scenario, client: client)
  end

  test 'returns nil when the budget is exceeded' do
    LlmCall.create!(scenario: @scenario, step: 'interpretation', model: Ai::Client::MODEL,
                    cost_micros: 999_999, latency_ms: 1)
    client = Ai::Client.new(transport: FakeAnthropic.new, budget: Ai::Budget.new(monthly_limit_micros: 1))

    assert_nil Scenario::Narrative.for(@comparison, scenario: @scenario, client: client)
  end

  test 'user content contains only engine-computed numbers' do
    content = Ai::Prompt::Narrative.user_content(@comparison)

    assert_includes content, 'Peak net worth'
    assert_includes content, @comparison.peak_net_worth(@comparison.baseline_periods).to_s
  end

  test 'system prompt forbids inventing numbers' do
    assert_match(/do not calculate/i, Ai::Prompt::Narrative.system_prompt)
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bin/rails test test/models/scenario/narrative_test.rb
```

Expected: FAIL — `NameError: uninitialized constant Ai::Prompt::Narrative`.

- [ ] **Step 3: Write the prompt**

Create `app/models/ai/prompt/narrative.rb`:

```ruby
module Ai
  module Prompt
    # System prompt and schema for explaining a Scenario::Comparison.
    #
    # The model receives ONLY numbers Projection::Household already computed and
    # is instructed to copy them rather than derive anything. It cannot see the
    # household's records, the levers, or any raw financial data.
    module Narrative
      def self.schema
        {
          'type' => 'object',
          'additionalProperties' => false,
          'required' => ['summary'],
          'properties' => {
            'summary' => {
              'type' => 'string',
              'description' => 'Two to four sentences explaining what changed and why.',
            },
          },
        }
      end

      def self.system_prompt
        <<~PROMPT
          You explain retirement projection results in plain language for a Canadian
          retirement planning tool.

          You are given figures that have already been calculated. DO NOT CALCULATE,
          derive, or invent any number. Every figure you mention must be copied
          exactly from the data you are given. If a number is not in the data, do not
          mention it.

          Write two to four short sentences. Explain what changed and, briefly, why
          that would happen. Be direct and neutral. Do not give financial advice, do
          not recommend a course of action, and do not speculate about the user's
          circumstances.

          All dollar figures are Canadian dollars. Average retirement income is in
          today's dollars; net worth figures are in future dollars.
        PROMPT
      end

      def self.user_content(comparison)
        lines = comparison.key_deltas.map { |delta| "#{delta[:label]}: #{delta[:from]} -> #{delta[:to]}" }
        lines << "Savings run out (current plan): #{comparison.depletion_year(comparison.baseline_periods) || 'never'}"
        lines << "Savings run out (this scenario): #{comparison.depletion_year(comparison.scenario_periods) || 'never'}"
        lines.join("\n")
      end
    end
  end
end
```

- [ ] **Step 4: Write the narrative**

Create `app/models/scenario/narrative.rb`:

```ruby
class Scenario
  # Plain-language wrapper over a Scenario::Comparison.
  #
  # This is DECORATION, not the answer. Every figure originates in
  # Projection::Household and is already present in the Comparison. When the API
  # is unavailable, the budget is spent, or the call fails, .for returns nil and
  # the results page renders the comparison table on its own.
  class Narrative
    attr_reader :summary

    def self.for(comparison, scenario: nil, client: Ai::Client.new)
      response = client.call(
        step: :narrative,
        system_prompt: Ai::Prompt::Narrative.system_prompt,
        user_content: Ai::Prompt::Narrative.user_content(comparison),
        schema: Ai::Prompt::Narrative.schema,
        scenario: scenario
      )
      new(summary: response['summary'])
    rescue Ai::Client::ApiError, Ai::Client::BudgetExceededError
      nil
    end

    def initialize(summary:)
      @summary = summary
    end
  end
end
```

- [ ] **Step 5: Run the test to verify it passes**

```bash
bin/rails test test/models/scenario/narrative_test.rb
```

Expected: PASS, 6 runs.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop -a app/models/ai/prompt/narrative.rb app/models/scenario/narrative.rb test/models/scenario/narrative_test.rb
git add app/models/ai/prompt/narrative.rb app/models/scenario/narrative.rb test/models/scenario/narrative_test.rb
git commit -m "feat: add narrative explanation over engine-computed comparisons"
```

---

## Task 16: Routes, controller, gating and rate limiting

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/scenarios_controller.rb`
- Test: `test/controllers/scenarios_controller_test.rb`

**Interfaces:**
- Consumes: everything from Tasks 1-15.
- Produces: routes `scenarios_path`, `new_scenario_path`, `scenario_path(id)`. Controller actions `index`, `new`, `create`, `show`, `update`. Instance variables for views: `@scenario`, `@scenarios`, `@interpretation`, `@draft`, `@lever_set`, `@descriptions`, `@comparison`, `@narrative`.

> **Spend control layers 1, 2, 4 and 5 land here.** The feature is admin-only for now (layer 1 — a stranger on live Tallyloot gets a redirect, not a bill), has a cache-backed kill switch (layer 2), is rate limited to 10 requests per hour per user (layer 4), and `Scenario`'s 500-character validation caps input (layer 5). Layers 3, 6 and 7 are in `Ai::Client` and `Ai::Budget`; layer 0 is the Console spend cap, set outside this repository.
>
> **This task's tests will not pass until Task 17 adds the views.** That is expected and called out in the steps below.

- [ ] **Step 1: Add the routes**

In `config/routes.rb`, immediately after the `resource :what_if, only: [:show]` line:

```ruby
  resources :scenarios, only: %i[index new create show update]
```

- [ ] **Step 2: Write the failing test**

Create `test/controllers/scenarios_controller_test.rb`:

```ruby
require 'test_helper'
require_relative '../support/fake_anthropic'

class ScenariosControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:admin_user)
    @regular = users(:regular_user)
    @household = @admin.household
  end

  def sign_in(user)
    post session_path, params: { email_address: user.email_address, password: 'password' }
  end

  # Replaces the controller's client with one backed by FakeAnthropic.
  def stub_ai(body)
    fake = FakeAnthropic.new(response_body: body)
    original = Ai::Client.instance_method(:transport)
    Ai::Client.define_method(:transport) { fake }
    yield
  ensure
    Ai::Client.define_method(:transport, original)
  end

  # ─── Access control ───────────────────────────────────────────────────────────

  test 'unauthenticated access redirects to login' do
    get new_scenario_path
    assert_redirected_to new_session_path
  end

  test 'non-admin users cannot reach the feature' do
    sign_in(@regular)
    get new_scenario_path

    assert_redirected_to root_path
  end

  test 'admin users can reach the feature' do
    sign_in(@admin)
    get new_scenario_path

    assert_response :success
  end

  test 'the kill switch blocks the feature without a deploy' do
    sign_in(@admin)
    Rails.cache.write(ScenariosController::KILL_SWITCH_KEY, true)

    get new_scenario_path

    assert_redirected_to root_path
  ensure
    Rails.cache.delete(ScenariosController::KILL_SWITCH_KEY)
  end

  test 'the kill switch does not consume budget when thrown' do
    sign_in(@admin)
    Rails.cache.write(ScenariosController::KILL_SWITCH_KEY, true)

    assert_no_difference 'LlmCall.count' do
      post scenarios_path, params: { scenario: { raw_input: 'what if I retire at 60' } }
    end
  ensure
    Rails.cache.delete(ScenariosController::KILL_SWITCH_KEY)
  end

  # ─── Input validation ─────────────────────────────────────────────────────────

  test 'rejects input longer than 500 characters without calling the API' do
    sign_in(@admin)

    assert_no_difference 'LlmCall.count' do
      post scenarios_path, params: { scenario: { raw_input: 'a' * 501 } }
    end
    assert_response :unprocessable_entity
  end

  test 'rejects blank input without calling the API' do
    sign_in(@admin)

    assert_no_difference 'LlmCall.count' do
      post scenarios_path, params: { scenario: { raw_input: '' } }
    end
    assert_response :unprocessable_entity
  end

  # ─── Parse and confirm ────────────────────────────────────────────────────────

  test 'create parses input and renders the confirmation' do
    sign_in(@admin)
    body = { 'changes' => [{ 'lever' => 'retirement_age', 'person' => 'self',
                             'value' => 60, 'confidence' => 'high', }],
             'unrecognized_input' => nil, }

    stub_ai(body) do
      assert_difference 'Scenario.count', 1 do
        post scenarios_path, params: { scenario: { raw_input: 'what if I retire at 60' } }
      end
    end

    assert_response :success
    assert_equal 'parsed', Scenario.last.status
  end

  test 'create marks the scenario clarifying when the request is unmodellable' do
    sign_in(@admin)
    body = { 'changes' => [], 'unrecognized_input' => 'buy a place in Kelowna for $650k' }

    stub_ai(body) { post scenarios_path, params: { scenario: { raw_input: 'buy a place in Kelowna' } } }

    assert_response :success
    assert_equal 'clarifying', Scenario.last.status
    assert_match(/Kelowna/, Scenario.last.clarifying_question)
  end

  test 'update confirms the scenario and renders results' do
    sign_in(@admin)
    scenario = Scenario.create!(
      household: @household, raw_input: 'retire at 60',
      parsed_levers: [{ 'lever' => 'retirement_age', 'person_id' => @admin.id, 'value' => 60 }]
    )
    levers = [{ 'lever' => 'retirement_age', 'person_id' => @admin.id, 'value' => 62 }]

    stub_ai({ 'summary' => 'Retiring later leaves more savings.' }) do
      patch scenario_path(scenario), params: { scenario: { confirmed_levers: levers.to_json } }
    end

    assert_response :success
    scenario.reload
    assert scenario.confirmed?
    assert_equal 62, scenario.confirmed_levers.first['value']
  end

  test 'a user cannot confirm another households scenario' do
    sign_in(@admin)
    other = Scenario.create!(household: households(:non_retired), raw_input: 'retire at 60')

    patch scenario_path(other), params: { scenario: { confirmed_levers: '[]' } }

    assert_response :not_found
  end

  # ─── Budget ───────────────────────────────────────────────────────────────────

  test 'an exhausted budget degrades gracefully instead of erroring' do
    sign_in(@admin)
    scenario = Scenario.create!(household: @household, raw_input: 'x')
    LlmCall.create!(scenario: scenario, step: 'interpretation', model: Ai::Client::MODEL,
                    cost_micros: Ai::Budget::DEFAULT_MONTHLY_LIMIT_MICROS, latency_ms: 1)

    post scenarios_path, params: { scenario: { raw_input: 'what if I retire at 60' } }

    assert_response :unprocessable_entity
    assert_match(/budget/i, response.body)
  end
end
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
bin/rails test test/controllers/scenarios_controller_test.rb
```

Expected: FAIL — `NameError: uninitialized constant ScenariosController`.

- [ ] **Step 4: Write the controller**

Create `app/controllers/scenarios_controller.rb`:

```ruby
# Natural-language scenario builder.
#
# Spend control layers that live here (design spec, section 11):
#   1. Feature gate - admin only for now; a stranger gets a redirect, not a bill
#   2. Kill switch  - a cache flag disables the feature without a deploy
#   4. Rate limit   - 10 requests per hour per user
#   5. Input cap    - enforced by Scenario's 500-character validation
#
# Layers 3, 6 and 7 live in Ai::Client and Ai::Budget. Layer 0 is the Anthropic
# Console spend cap, set outside this repository.
class ScenariosController < ApplicationController
  # Spend control layer 2. Flip from the console, no deploy required:
  #   Rails.cache.write(ScenariosController::KILL_SWITCH_KEY, true)
  #   Rails.cache.delete(ScenariosController::KILL_SWITCH_KEY)
  KILL_SWITCH_KEY = 'scenarios:disabled'.freeze

  before_action :require_feature_access
  before_action :set_scenario, only: %i[show update]

  rate_limit to: 10, within: 1.hour, by: -> { Current.user.id }, only: %i[create update],
             with: -> { redirect_to new_scenario_path, alert: 'Too many requests. Please try again later.' }

  def index
    @scenarios = household.scenarios.order(created_at: :desc).limit(50)
  end

  def new
    @scenario ||= Scenario.new
  end

  def create
    @scenario = household.scenarios.new(raw_input: scenario_params[:raw_input])
    return render :new, status: :unprocessable_entity unless @scenario.save

    interpret_and_render
  end

  def show
    load_results
  end

  def update
    levers = JSON.parse(scenario_params[:confirmed_levers].presence || '[]')
    @scenario.confirm!(levers)
    load_results
    render :show
  rescue JSON::ParserError
    redirect_to new_scenario_path, alert: 'Could not read the confirmed changes.'
  end

  private

  def household = Current.user.household

  def require_feature_access
    return redirect_to root_path, alert: 'Not available yet.' unless Current.user&.admin?
    return unless Rails.cache.read(KILL_SWITCH_KEY).present?

    redirect_to root_path, alert: 'The scenario builder is temporarily unavailable.'
  end

  def set_scenario
    @scenario = household.scenarios.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    head :not_found
  end

  def scenario_params
    params.require(:scenario).permit(:raw_input, :confirmed_levers)
  end

  def load_results
    @draft = Scenario::Draft.from(household)
    @lever_set = Scenario::LeverSet.from_h(@scenario.confirmed_levers)
    @descriptions = @lever_set.descriptions(@draft)
    @comparison = Scenario::Comparison.build(household, @lever_set)
    @narrative = Scenario::Narrative.for(@comparison, scenario: @scenario, client: ai_client)
  end

  def interpret_and_render
    response = ai_client.call(
      step: :interpretation,
      system_prompt: Ai::Prompt::Interpretation.system_prompt,
      user_content: Ai::Prompt::Interpretation.user_content(household, @scenario.raw_input),
      schema: Ai::Prompt::Interpretation.schema,
      scenario: @scenario
    )
    build_interpretation(response)
    render :confirm
  rescue Ai::Client::BudgetExceededError
    fail_with('The monthly AI budget has been reached. Please use the manual planning pages.')
  rescue Ai::Client::ApiError => e
    fail_with("Could not read that request: #{e.message}")
  end

  def fail_with(message)
    @scenario.update!(status: :rejected)
    flash.now[:alert] = message
    render :new, status: :unprocessable_entity
  end

  def build_interpretation(response)
    @interpretation = Scenario::Interpretation.from_response(
      response, household: household, current_user: Current.user
    )
    @draft = Scenario::Draft.from(household)
    @descriptions = @interpretation.lever_set.descriptions(@draft)
    @scenario.update!(
      parsed_levers: @interpretation.lever_set.to_h,
      status: @interpretation.ambiguous? ? :clarifying : :parsed,
      clarifying_question: @interpretation.clarifying_question
    )
  end

  def ai_client = @ai_client ||= Ai::Client.new
end
```

- [ ] **Step 5: Run the test and confirm the failures are template errors**

```bash
bin/rails test test/controllers/scenarios_controller_test.rb
```

Expected: FAIL with `ActionView::MissingTemplate` (`scenarios/new`, `scenarios/confirm`, `scenarios/show`). **This is correct at this point** — views arrive in Task 17. Verify every failure is a missing-template error and not a controller logic error before moving on. The two access-control tests that redirect should already pass.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop -a app/controllers/scenarios_controller.rb config/routes.rb
git add config/routes.rb app/controllers/scenarios_controller.rb test/controllers/scenarios_controller_test.rb
git commit -m "feat: add scenarios controller with feature gating and rate limiting"
```

---

## Task 17: Views

**Files:**
- Create: `app/views/scenarios/new.html.erb`
- Create: `app/views/scenarios/confirm.html.erb`
- Create: `app/views/scenarios/show.html.erb`
- Create: `app/views/scenarios/index.html.erb`

**Interfaces:**
- Consumes: `@scenario`, `@scenarios`, `@interpretation`, `@draft`, `@lever_set`, `@descriptions`, `@comparison`, `@narrative` from `ScenariosController` (Task 16).
- Produces: no Ruby interface. Element ids: `scenario_form`, `scenario_input`, `scenario_submit`, `scenario_<id>`, `lever_<key>`, `scenario_confirm_form`, `scenario_confirmed_levers`, `scenario_confirm`, `scenario_restart`, `scenario_key_deltas`, `scenario_narrative`, `scenario_clarifying_question`, `scenario_new`.

> **Bulma only.** Use existing classes (`box`, `field`, `control`, `textarea`, `button is-primary`, `notification is-warning`, `table is-fullwidth is-striped`, `tag`). Do not add custom CSS.

- [ ] **Step 1: Write the input view**

Create `app/views/scenarios/new.html.erb`:

```erb
<div class="section">
  <div class="container">
    <h1 class="title">Ask a what-if question</h1>
    <p class="subtitle is-6">
      Describe a change in plain language. Every number is calculated by Tallyloot's
      projection engine — the assistant only reads your question and explains the result.
    </p>

    <%= form_with model: @scenario, url: scenarios_path, method: :post, id: 'scenario_form' do |f| %>
      <div class="field">
        <div class="control">
          <%= f.text_area :raw_input, id: 'scenario_input', class: 'textarea', rows: 3,
                          maxlength: Scenario::MAX_INPUT_LENGTH,
                          placeholder: 'What if I retire at 60 and take CPP at 70?' %>
        </div>
        <% if @scenario.errors.any? %>
          <p class="help is-danger" id="scenario_input_error"><%= @scenario.errors.full_messages.to_sentence %></p>
        <% end %>
      </div>

      <div class="field">
        <div class="control">
          <%= f.submit 'Run this scenario', class: 'button is-primary', id: 'scenario_submit' %>
        </div>
      </div>
    <% end %>

    <div class="content is-small mt-5">
      <p class="has-text-grey">Things you can ask about:</p>
      <ul>
        <li>Retirement age, life expectancy</li>
        <li>Monthly savings, account contributions</li>
        <li>CPP and OAS start ages, workplace pension timing</li>
        <li>Post-retirement work, household income goal, investment strategy</li>
      </ul>
    </div>
  </div>
</div>
```

- [ ] **Step 2: Write the confirmation view**

Create `app/views/scenarios/confirm.html.erb`:

```erb
<div class="section">
  <div class="container" id="scenario_<%= @scenario.id %>">
    <h1 class="title">Did I understand that correctly?</h1>
    <blockquote class="mb-5"><%= @scenario.raw_input %></blockquote>

    <% if @interpretation.ambiguous? %>
      <div class="notification is-warning" id="scenario_clarifying_question">
        <%= @interpretation.clarifying_question %>
      </div>
    <% end %>

    <% if @descriptions.any? %>
      <div class="box">
        <h2 class="subtitle is-5">Changes I found</h2>
        <ul>
          <% @interpretation.lever_set.each_with_index do |lever, index| %>
            <li id="lever_<%= lever.key %>" class="mb-2"><%= @descriptions[index] %></li>
          <% end %>
        </ul>
      </div>

      <%= form_with url: scenario_path(@scenario), method: :patch, id: 'scenario_confirm_form' do |f| %>
        <%= hidden_field_tag 'scenario[confirmed_levers]',
                             @interpretation.lever_set.to_h.to_json,
                             id: 'scenario_confirmed_levers' %>
        <div class="field is-grouped">
          <div class="control">
            <%= f.submit 'Yes, run it', class: 'button is-primary', id: 'scenario_confirm' %>
          </div>
          <div class="control">
            <%= link_to 'Start over', new_scenario_path, class: 'button is-light', id: 'scenario_restart' %>
          </div>
        </div>
      <% end %>
    <% else %>
      <%= link_to 'Try another question', new_scenario_path, class: 'button is-primary', id: 'scenario_restart' %>
    <% end %>
  </div>
</div>
```

- [ ] **Step 3: Write the results view**

Create `app/views/scenarios/show.html.erb`:

```erb
<div class="section">
  <div class="container" id="scenario_<%= @scenario.id %>">
    <h1 class="title">Your scenario</h1>
    <blockquote class="mb-5"><%= @scenario.raw_input %></blockquote>

    <% if @descriptions.any? %>
      <div class="box">
        <h2 class="subtitle is-5">Changes applied</h2>
        <ul>
          <% @lever_set.each_with_index do |lever, index| %>
            <li id="lever_<%= lever.key %>" class="mb-2"><%= @descriptions[index] %></li>
          <% end %>
        </ul>
      </div>
    <% end %>

    <div class="box">
      <h2 class="subtitle is-5">What changes</h2>
      <div class="table-container">
        <table class="table is-fullwidth is-striped" id="scenario_key_deltas">
          <thead>
            <tr>
              <th>Measure</th>
              <th class="has-text-right">Now</th>
              <th class="has-text-right">Scenario</th>
              <th class="has-text-right">Change</th>
            </tr>
          </thead>
          <tbody>
            <% @comparison.key_deltas.each do |delta| %>
              <tr>
                <td><%= delta[:label] %></td>
                <td class="has-text-right"><%= number_to_currency(delta[:from], precision: 0) %></td>
                <td class="has-text-right"><%= number_to_currency(delta[:to], precision: 0) %></td>
                <td class="has-text-right <%= delta[:to] >= delta[:from] ? 'has-text-success' : 'has-text-danger' %>">
                  <%= number_to_currency(delta[:to] - delta[:from], precision: 0) %>
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <% depletion = @comparison.depletion_year(@comparison.scenario_periods) %>
      <% if depletion %>
        <p class="help">Savings are projected to run out in <%= depletion %>.</p>
      <% end %>
    </div>

    <% if @narrative %>
      <div class="box" id="scenario_narrative">
        <h2 class="subtitle is-5">In plain language</h2>
        <p><%= @narrative.summary %></p>
      </div>
    <% end %>

    <%= link_to 'Ask another question', new_scenario_path, class: 'button is-primary', id: 'scenario_restart' %>
  </div>
</div>
```

- [ ] **Step 4: Write the index view**

Create `app/views/scenarios/index.html.erb`:

```erb
<div class="section">
  <div class="container">
    <h1 class="title">Past scenarios</h1>

    <% if @scenarios.any? %>
      <div class="table-container">
        <table class="table is-fullwidth is-striped">
          <thead>
            <tr><th>Question</th><th>Status</th><th>Asked</th></tr>
          </thead>
          <tbody>
            <% @scenarios.each do |scenario| %>
              <tr id="scenario_<%= scenario.id %>">
                <td>
                  <% if scenario.confirmed? %>
                    <%= link_to scenario.raw_input, scenario_path(scenario) %>
                  <% else %>
                    <%= scenario.raw_input %>
                  <% end %>
                </td>
                <td><span class="tag"><%= scenario.status %></span></td>
                <td><%= scenario.created_at.to_date %></td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    <% else %>
      <p class="has-text-grey">No scenarios yet.</p>
    <% end %>

    <%= link_to 'Ask a question', new_scenario_path, class: 'button is-primary mt-4', id: 'scenario_new' %>
  </div>
</div>
```

- [ ] **Step 5: Run the controller test to verify it passes**

```bash
bin/rails test test/controllers/scenarios_controller_test.rb
```

Expected: PASS, 12 runs.

- [ ] **Step 6: Run the full suite as a regression check**

```bash
bin/rails test
```

Expected: PASS. No existing test should have changed behaviour — nothing in Tasks 1-17 modifies `WhatIf`, `Simulation`, or `Projection::Household`.

- [ ] **Step 7: Commit**

```bash
git add app/views/scenarios
git commit -m "feat: add scenario builder views"
```

---

## Task 18: Reporting task and live smoke test

**Files:**
- Create: `lib/tasks/scenarios.rake`
- Create: `test/models/ai/live_test.rb`
- Test: `test/lib/tasks/scenarios_rake_test.rb`

**Interfaces:**
- Consumes: `Scenario` (Task 1), `LlmCall` (Task 11), `Scenario::LeverSet` (Task 9), `Ai::Prompt::Interpretation` (Task 14), `Ai::Client` (Task 13).
- Produces: `rake scenarios:report`, and a `LIVE_AI=1`-gated smoke test.

> **A log nobody reads is pure cost.** The report ships with the tables, not after them. It answers the three metrics that are meaningful at one user: cost, model routing, and extraction accuracy.

- [ ] **Step 1: Write the failing test**

Create `test/lib/tasks/scenarios_rake_test.rb`:

```ruby
require 'test_helper'
require 'rake'

class ScenariosRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task['scenarios:report'].reenable

    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  test 'reports zero state without raising' do
    output = capture_io { Rake::Task['scenarios:report'].invoke }.first

    assert_match(/Scenarios/, output)
  end

  test 'reports cost, routing and extraction accuracy' do
    scenario = Scenario.create!(
      household: @household, raw_input: 'retire at 60',
      parsed_levers: [{ 'lever' => 'retirement_age', 'person_id' => @john.id, 'value' => 60 }],
      confirmed_levers: [{ 'lever' => 'retirement_age', 'person_id' => @john.id, 'value' => 62 }],
      status: 'confirmed', confirmed_at: Time.current
    )
    LlmCall.record!(scenario: scenario, step: :interpretation, model: 'claude-haiku-4-5',
                    input_tokens: 1200, output_tokens: 150, cache_read_tokens: 0, latency_ms: 900)

    output = capture_io { Rake::Task['scenarios:report'].invoke }.first

    assert_match(/claude-haiku-4-5/, output)
    assert_match(/Corrected/, output)
    assert_match(/retirement_age/, output)
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/lib/tasks/scenarios_rake_test.rb
```

Expected: FAIL — `Don't know how to build task 'scenarios:report'`.

- [ ] **Step 3: Write the rake task**

Create `lib/tasks/scenarios.rake`:

```ruby
# Reads back the instrumentation the scenario builder writes.
#
# Answers the three questions that are meaningful at a single user: what did it
# cost, which model handled it, and how often was the parse wrong?
namespace :scenarios do
  desc 'Report on natural-language scenario usage, cost and extraction accuracy'
  task report: :environment do
    puts "\n=== Scenarios ==="
    puts "Total:      #{Scenario.count}"
    Scenario.statuses.each_key { |status| puts "  #{status.ljust(12)} #{Scenario.where(status: status).count}" }

    puts "\n=== Cost ==="
    puts "This month: $#{format('%.4f', LlmCall.spend_micros_this_month / 1_000_000.0)}"
    puts "All time:   $#{format('%.4f', LlmCall.sum(:cost_micros) / 1_000_000.0)}"
    confirmed = Scenario.confirmed.count
    if confirmed.positive?
      puts "Per confirmed scenario: $#{format('%.4f', LlmCall.sum(:cost_micros) / 1_000_000.0 / confirmed)}"
    end

    puts "\n=== Model routing ==="
    LlmCall.group(:model, :step).count.each { |(model, step), count| puts "  #{model} / #{step}: #{count}" }
    failures = LlmCall.where(success: false).count
    puts "  failures: #{failures}" if failures.positive?

    puts "\n=== Latency ==="
    LlmCall.group(:step).average(:latency_ms).each { |step, avg| puts "  #{step}: #{avg.to_i}ms average" }

    puts "\n=== Extraction accuracy ==="
    scenarios = Scenario.confirmed.reject { |s| s.parsed_levers.blank? }
    if scenarios.empty?
      puts '  No confirmed scenarios yet.'
    else
      totals = Hash.new(0)
      corrected_levers = Hash.new(0)
      scenarios.each do |scenario|
        diff = Scenario::LeverSet.from_h(scenario.parsed_levers)
                                 .diff(Scenario::LeverSet.from_h(scenario.confirmed_levers))
        totals[:parsed] += diff[:total_parsed]
        totals[:corrected] += diff[:corrected].size
        totals[:added] += diff[:added].size
        totals[:removed] += diff[:removed].size
        diff[:corrected].each { |key| corrected_levers[key] += 1 }
      end

      accuracy = totals[:parsed].positive? ? (1 - (totals[:corrected].to_f / totals[:parsed])) * 100 : 100
      puts "  Scenarios:     #{scenarios.size}"
      puts "  Levers parsed: #{totals[:parsed]}"
      puts "  Corrected: #{totals[:corrected]}  Added: #{totals[:added]}  Removed: #{totals[:removed]}"
      puts "  Accuracy:      #{format('%.1f', accuracy)}%"
      if corrected_levers.any?
        puts '  Most corrected levers:'
        corrected_levers.sort_by { |_, v| -v }.first(5).each { |key, count| puts "    #{key}: #{count}" }
      end
    end
    puts
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bin/rails test test/lib/tasks/scenarios_rake_test.rb
```

Expected: PASS, 2 runs.

- [ ] **Step 5: Write the live smoke test**

Create `test/models/ai/live_test.rb`:

```ruby
require 'test_helper'

# The ONLY test that talks to the real Anthropic API.
#
# Skipped unless LIVE_AI=1. Run it by hand after changing a prompt:
#   LIVE_AI=1 bin/rails test test/models/ai/live_test.rb
class Ai::LiveTest < ActiveSupport::TestCase
  setup do
    skip 'Set LIVE_AI=1 to run live API tests' unless ENV['LIVE_AI'] == '1'
    skip 'ANTHROPIC_API_KEY is not set' if ENV['ANTHROPIC_API_KEY'].blank?

    @household = households(:non_retired)
    @john = users(:working_user_john)
  end

  def interpret(text)
    scenario = Scenario.create!(household: @household, raw_input: text)
    response = Ai::Client.new.call(
      step: :interpretation,
      system_prompt: Ai::Prompt::Interpretation.system_prompt,
      user_content: Ai::Prompt::Interpretation.user_content(@household, text),
      schema: Ai::Prompt::Interpretation.schema,
      scenario: scenario
    )
    Scenario::Interpretation.from_response(response, household: @household, current_user: @john)
  end

  test 'extracts a single retirement age' do
    result = interpret('What if I retire at 60?')

    assert_not result.ambiguous?, "Expected a clean parse, got: #{result.clarifying_question}"
    assert_equal 1, result.lever_set.size
    assert_equal Scenario::Lever::RetirementAge, result.lever_set.first.class
    assert_equal 60, result.lever_set.first.value
  end

  test 'extracts a compound request' do
    result = interpret('What if I retire at 60 and take CPP at 70?')

    assert_equal %w[cpp_start_age retirement_age], result.lever_set.map(&:key).sort
  end

  test 'refuses an unmodellable request instead of guessing' do
    result = interpret('What if I buy a place in Kelowna for $650k?')

    assert result.ambiguous?
    assert_match(/kelowna|can't model/i, result.clarifying_question)
  end

  test 'reports whether the prompt cache is working' do
    interpret('What if I retire at 60?')
    interpret('What if I retire at 61?')

    cached = LlmCall.last.cache_read_tokens
    puts "\n  cache_read_tokens on second call: #{cached}"
    puts '  (zero means the system prompt is under the ~1024 token minimum)' if cached.zero?
  end
end
```

- [ ] **Step 6: Run the full suite**

```bash
bin/rails test
```

Expected: PASS. The four live tests skip.

- [ ] **Step 7: Run the linters**

```bash
bin/rubocop
bin/brakeman -q
```

Expected: no offences, no new warnings.

- [ ] **Step 8: Commit**

```bash
bin/rubocop -a lib/tasks/scenarios.rake test/lib/tasks/scenarios_rake_test.rb test/models/ai/live_test.rb
git add lib/tasks/scenarios.rake test/lib/tasks/scenarios_rake_test.rb test/models/ai/live_test.rb
git commit -m "feat: add scenario usage report and live API smoke test"
```

---

## Post-implementation checklist

Not tasks — things to do before this is usable, and before it is ever exposed beyond the allowlist.

- [ ] **Set a hard spend cap in the Anthropic Console.** This is spend control layer 0 and the only one no application bug can bypass. Do this before the first real call.
- [ ] Add `ANTHROPIC_API_KEY` to `.envrc` locally and to Kamal secrets for production.
- [ ] Run `LIVE_AI=1 bin/rails test test/models/ai/live_test.rb` and read the reported `cache_read_tokens`. If it is zero, the system prompt is under the ~1,024-token cache minimum — either accept it (cost is negligible) or lengthen the prompt with worked examples.
- [ ] Run `rake scenarios:report` after ten or so real questions and look at which levers get corrected most. Compound sentences are the expected weak point.

**Before opening this beyond the admin allowlist:**

- [ ] Update `app/views/pages/privacy.html.erb` to disclose a third-party AI processor. This is required by the feature itself, not by the logging.
- [ ] Decide on raw-text retention. Storing free-text financial disclosures without a retention policy is fine for a single-user pre-alpha and is not fine with real users.
- [ ] Reconsider `readonly!` on `Scenario::Draft`'s record graph (design spec section 6.3). It must mark **every** record — users, accounts, pensions, benefits, employments, and the portfolio — because neither `.each(&:readonly!)` nor relation-level `.readonly` cascades to included associations.

**Follow-up work this plan deliberately excludes:**

- [ ] Remove `WhatIf`, `Simulation`, `WhatIfsController`, `SimulatorsController` and their views in a separate PR. `Scenario::LeverSet::REGISTRY` covers the union of both pages' levers, so nothing is lost.
- [ ] Fix the N+1 in `Projection::Household.from_household` — it eager-loads `:user` for employments but not for accounts, pensions, or benefits, while `Pension#start_year` and `Benefit#start_year` both call `user.birth_year` (design spec section 6.4).
