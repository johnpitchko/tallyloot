# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Tallyloot is an **open-source, self-hosted retirement planner** for Canadian households, built with Rails 8 and released under the MIT licence. It forecasts a household's retirement savings and income from its accounts, pensions, and government benefits.

Each install serves **one household and has no login**. Every request acts as the household's first member (`SelfHosted.owner`); on the first visit `SampleHousehold` creates example data so the dashboard shows a real projection. The whole app is a single page: the input panel on the left, the projection on the right.

### Product Positioning

Tallyloot occupies the **middle ground** between basic compound growth calculators and advanced financial modeling tools:
- **More than a basic calculator:** Handles multiple income sources (DB pensions, government benefits, personal savings), different account types, and age-based investment strategies
- **Less than professional software:** Approachable, simple-to-use, requires minimal user input and ongoing management

### Design Philosophy

**Approachability is paramount:**
- Minimize required user input
- Reduce ongoing management burden
- Make complex retirement planning accessible to non-financial experts
- Feature-rich without being overwhelming

When building features, always balance comprehensiveness with simplicity. If a feature requires extensive user input or ongoing maintenance, reconsider the approach.

**Easy to self-host:** the Docker image must run with no required configuration. Anything extra (allowed hosts, SSL) is opt-in through `TALLYLOOT_*` environment variables.

## Development Commands

### Server and Console
```bash
bin/rails server          # Start development server (default port 3000)
bin/rails console         # Open Rails console
bin/rails dbconsole       # Open database console
```

### Database
```bash
bin/rails db:create       # Create databases
bin/rails db:migrate      # Run pending migrations
bin/rails db:seed         # Load seed data
bin/rails db:reset        # Drop, create, migrate, and seed database
bin/rails db:rollback     # Rollback last migration
```

### Testing
```bash
bin/rails test                           # Run all tests
bin/rails test test/models/user_test.rb  # Run specific test file
bin/rails test test/models/user_test.rb:15  # Run single test at line 15
```

### Code Quality
```bash
bin/rubocop              # Run RuboCop linter
bin/rubocop -a           # Auto-fix RuboCop violations
bin/brakeman             # Run security vulnerability scanner
```

### Other Tools
```bash
bin/rails annotate       # Add schema annotations to models (via annotaterb gem)
bin/dev                  # Development script (check bin/dev for specifics)
```

### Environment Setup
The project uses `direnv` for environment variables. Copy `.envrc.example` to `.envrc` and customize values:
```bash
cp .envrc.example .envrc
direnv allow
```

### Docker
```bash
docker build -t tallyloot .
docker run -d -p 3000:80 -v tallyloot:/rails/storage --name tallyloot tallyloot
```
`bin/docker-entrypoint` generates `SECRET_KEY_BASE` on first boot and keeps it in the storage volume beside the SQLite databases. There are no Rails credentials.

### Website
The project website lives in `site/`: static HTML with Bulma from a CDN, no build step. Preview it with `python3 -m http.server -d site`. Pushes to `main` that touch `site/` deploy it to GitHub Pages (`.github/workflows/pages.yml`).

## Technical Stack

Tallyloot is built on **Rails 8** following modern Rails conventions:

### Frontend Architecture: Hotwire

**Turbo + Stimulus with minimal JavaScript:**
- Use **Turbo** for page updates, form submissions, and dynamic content
- Use **Stimulus** for interactive elements requiring JavaScript
- Avoid heavy JavaScript frameworks or complex client-side state management
- Prefer server-rendered HTML over JSON APIs

**When to use what:**
- **Turbo Frames:** Partial page updates (e.g., updating a single section)
- **Turbo Streams:** Multiple simultaneous updates (e.g., form validation feedback)
- **Stimulus controllers:** Progressive enhancement for interactive widgets
- **Plain Rails forms:** Default choice for most user input

**CSS Framework: Bulma**
- Use **Bulma** for all styling and layout
- Bulma is a modern CSS framework based on Flexbox
- Uses semantic class names (e.g., `button is-primary`, `table is-striped`)
- No JavaScript dependencies - pure CSS framework
- **Prefer adding existing Bulma classes to HTML elements** rather than creating custom CSS overrides. Only add custom CSS when no suitable Bulma class exists.
- Reference: https://bulma.io/documentation/

### Backend: SQLite + Rails 8 Solid Gems

- **SQLite** for all environments (development, test, production)
- **Solid Queue** for background jobs
- **Solid Cache** for caching
- **Solid Cable** for WebSocket connections
- This stack enables simple deployment without external dependencies (Redis, PostgreSQL, etc.)

### Standards

- Follow **Rails 8 best practices** and conventions
- Adhere to **Ruby style guide** (enforced via RuboCop)
- Write tests in **Minitest** (Rails default)
- Use Rails 8 features (attribute API, normalizations, authentication patterns)

## Core Architecture

### Domain Model Hierarchy

The application follows a hierarchical data structure:

```
Household (family unit)
├── Users (individuals in household)
│   ├── Accounts (401k, IRA, TFSA, etc.)
│   └── Pensions (future pension income)
└── Portfolio (investment strategy)
    ├── Allocation (equity/fixed income mix)
    └── Glidepath (age-based allocation changes)
```

**Key relationships:**
- A `Household` has many `Users` and one `Portfolio`
- Each `User` has many `Accounts` and `Pensions`
- `Portfolio` references an `Allocation` and `Glidepath` to define investment strategy
- There is no login: each install holds one household, and `ApplicationController` sets `Current.user` to its first member via `SelfHosted.owner` (which creates a `SampleHousehold` on first visit and refuses to run against a database with several households)

### Projection/Period Pattern

The application uses a sophisticated **dual-layer architecture** for financial modeling:

**Projection Layer** (`app/models/projection/`)
- Orchestrates multi-year calculations
- `Projection::Household` - Generates all periods for a household's financial future
- `Projection::Account` - Projects account balances year-by-year
- `Projection::Pension` - Projects pension income over time

**Period Layer** (`app/models/period/`)
- Immutable value objects representing a single year's snapshot
- `Period::Summary` - Aggregates all data for one year
- `Period::Account` - Account state for one year (balance, contributions, withdrawals, growth)
- `Period::Pension` - Pension income for one year

**Design rationale:** Separates iteration logic (Projection) from calculation logic (Period), making the code easier to test and reason about.

### Income Projection Scope

**The Income Projection chart covers the decumulation phase only** — it renders from the year the *entire* household is retired onward (`Household#fully_retired_year`, the latest member's retirement year), not the first member's.

The tool does **not model pre-retirement salary**: there is no current-income field on `User`, and working years only track account contributions. If the chart began at the first retirement, a household with staggered retirement ages would show a misleadingly low "Total Income" during the years one member still earns an (unmodelled) salary. Starting at full retirement avoids that.

- Predicates: `Household#fully_retired_as_of?(year)` / `Period::Summary#fully_retired?` (all members retired) vs. the existing `retired_as_of?` / `retired?` (any member retired).
- The income-chart data builders in `DashboardsController`, `WhatIfsController`, and `SimulatorsController` all filter periods with `fully_retired?`. `Simulation::SimHousehold` mirrors the predicate for what-if/simulator scenarios.
- Note: `avg_retirement_income` deliberately still uses the any-member `retired?` semantics.

### Calculator Pattern

`Calculator` class (`app/models/calculator.rb`) is a pure Ruby object (not ActiveRecord) that encapsulates financial calculations in a clear sequence:
- Opening balance → Contribution → Withdrawal → Growth → Ending balance
- Uses immutable attributes (attr_readers only)
- All financial logic centralized for consistency

### Year-Based Time Model

**Important:** The application is year-oriented, not date-oriented:
- Models use integer years for calculations: `age_in_year(year)`, `retired_as_of?(year)`
- Projections iterate over year ranges
- Methods accept year parameters rather than Date objects
- Birth dates stored as DATE, but converted to years for calculations

When adding time-based logic, follow this pattern and use years as the primary unit.

## Controller Organization

- `DashboardsController` - The single page (root): input panel and projection
- `AccountsController`, `PensionsController`, `BenefitsController`, `EmploymentsController` - Inline CRUD for the input panel (nested under users)
- `UsersController`, `HouseholdsController`, `PortfoliosController` - People, household settings, goals and assumptions
- `ProjectionsController`, `SimulatorsController`, `WhatIfsController`, `GlidepathsController` - Projection views and scenarios
- `SampleNoticesController` - Dismisses the sample-data notice

Input-panel edits replace the record's row in place via a Turbo Frame (`dom_id`), and saves refresh the workspace through the `RefreshesWorkspace` concern.

## Key Conventions

### Scope Data to the Current Household
- **Always load records through the current household**, e.g. `Current.user.household.accounts.find(id)`, never `Account.find(id)` or `Account.all`
- Each install holds one household today, so an unscoped query looks harmless. It keeps a future multi-household version one login away rather than a data-leak audit
- Validate any user-supplied foreign key against the household too (see `AccountsController#account_params` for the owner select)

### Money Storage
- **Always store money as integers (dollars)** to prevent floating-point errors
- Stored as whole dollars without cents
- Example: $50,704 stored as 50704 (integer)
- Display with currency formatting: `number_to_currency(amount)`

### Percentages
- Store as decimals with precision (5,4) or (5,2)
- Example: 75% stored as 0.75

### Default Values
- Use Rails attribute API for defaults:
  ```ruby
  attribute :inflation_rate, :decimal, default: 0.0
  attribute :life_expectancy, :integer, default: 82
  ```

### Inspectable Concern
- `Inspectable` concern provides cleaner `#inspect` output for debugging
- Models declare: `inspectable :name, :email`
- Formats BigDecimal, String, and other types appropriately
- Use this on new models for better console/debugging experience

### Scopes and Time Queries
```ruby
scope :for_year, ->(year) { where(start_year: ..year) }
scope :by_birth_year, -> { order('birth_date ASC') }
```

### Nominal vs Real Dollars
- **All projected financial values are in nominal (future) dollars** — account balances, withdrawals, pension/benefit income
- **Allocation return rates (`avg_nominal_return`) are nominal** — they include expected inflation
- **`inflation_rate` on Portfolio** converts between nominal and real:
  - `Period::Summary#deflate(amount)` converts nominal → real for display
  - `Allocation#real_return(inflation_rate)` derives the real return rate
  - `Portfolio#real_return_for_age(age)` convenience method for the above
- **Income goals (`retirement_income_goal`)** are stored in real (today's) dollars and inflated to nominal via `nominal_income_goal` for year-specific comparisons

### Delegation
- Use delegation for cleaner interfaces:
  ```ruby
  delegate :nominal_return_for_age, to: :glidepath
  delegate :user, to: :session, allow_nil: true
  ```

## Testing Practices

- Framework: Minitest (Rails default)
- Test location: `test/models/`, `test/controllers/`, `test/integration/`
- Fixtures in `test/fixtures/*.yml` define realistic scenarios
- Fixtures include several households, chiefly `non_retired` (John and Jane) and `retired` (Bob and Sue)

**Running specific tests:**
```bash
bin/rails test test/models/projection/household_test.rb
bin/rails test test/models/projection/household_test.rb:25
```

## Database Notes

- **SQLite** for all environments (development, test, production)
- Production uses multiple databases: primary, cache, queue, cable (Rails 8 Solid adapters)
- Foreign keys enforced with proper indexing
- Schema uses `force: :cascade` for easy reset

## Internationalization

**Current state:** The application is built for **Canadian** users and households.

**Account types reflect Canadian retirement accounts:**
- RRSP, TFSA, FHSA (Canadian registered accounts)
- Also supports 401k, IRA (US accounts) for cross-border scenarios

**Future consideration:** Multi-country support is planned. When adding new features:
- Avoid hardcoding country-specific assumptions
- Consider how pension systems, tax rules, and account types vary by country
- Design for eventual parameterization by region/country

## Code Style

- RuboCop configuration in `.rubocop.yml`
- Ruby 3.4 target version
- 120 character line length limit
- Single quotes preferred unless interpolation needed
- Trailing commas required in multi-line literals
- No top-level class/module documentation required
