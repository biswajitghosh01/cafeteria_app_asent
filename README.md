# Food Court Counter

Food Court Counter is an operations and finance application for AS Enterprises. It provides a React web interface backed by a FastAPI API and a SQLAlchemy database.

## Features

- Sales, purchases, and fixed-expense records
- Employee, attendance, salary, advance, and payslip management
- PDF and Excel downloads for sales, purchases, expenses, and salary reports
- Profit and loss statements calculated from recorded transactions
- Dated, manually entered balance-sheet snapshots
- User authentication, administration, and audit logs

### Financial statement assumptions

The profit and loss statement uses the transactions recorded in the app:

- Sales revenue excludes the output GST recorded against sales.
- Purchases are treated as period costs, excluding separately recorded input GST. Inventory and cost of goods sold are not tracked.
- Commission, compliance, and other sales charges use their pre-GST values.
- Fixed expenses use the amounts entered in the fixed-expense register.
- Payroll includes recorded gross pay plus employer PF and ESI, grouped by pay month whether paid or unpaid.

The balance sheet is a manual snapshot because the application does not maintain a complete accounting ledger for cash, receivables, inventory, loans, and equity. Snapshots are stored by date and cannot be saved unless assets equal liabilities plus equity.

These statements summarize application data and are not a substitute for review by a qualified accountant.

## Project layout

```text
backend/
  app/                 FastAPI application, models, schemas, and API routers
  migrations/          Alembic configuration and migration environment
  requirements.txt     Python dependencies
frontend/
  src/                 React, TypeScript, and Vite application
  package.json         Frontend scripts and dependencies
deploy/
  scripts/             Local setup, Ubuntu deployment, and database backup
```

## Requirements

- Python 3.12 or newer
- Node.js and npm
- Git

SQLite is the zero-configuration local database. Production deployments use PostgreSQL.

## Local development

### First-time setup

From the project root, run:

```bash
bash deploy/scripts/setup-local.sh
```

The setup script creates the backend virtual environment and local configuration, installs Python and frontend dependencies, and asks which database to use. Choose SQLite for local development.

### Start the app

Open two terminals from the project root.

**Terminal 1 — API:**

```bash
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload --port 8000
```

**Terminal 2 — web app:**

```bash
cd frontend
npm run dev
```

Open <http://localhost:5173>. The API and interactive API documentation are available at <http://localhost:8000> and <http://localhost:8000/docs>.

On a new local database, the default accounts are:

| Role | Email | Password |
| --- | --- | --- |
| Administrator | `admin@example.com` | `Admin@12345` |
| Counter operator | `counter@example.com` | `Counter@12345` |

Change the default passwords before using the application beyond local development. Existing databases or a customized `backend/.env` may use different credentials.

Stop either development server with **Ctrl+C**.

### Useful local commands

```bash
# Frontend production bundle
cd frontend
npm run build

# Backend API is started from backend/
cd backend
source .venv/bin/activate
uvicorn app.main:app --reload --port 8000
```

## Updating an existing server with a code delta

Use this procedure to deploy a small code update to an existing installation without re-running server provisioning or replacing production configuration.

The examples below assume the application is installed at `/var/www/food-court-counter` and the systemd service is `food-court-api`. Adjust the application path, SSH user, server hostname, database name, and domain for your installation. Replace angle-bracket placeholders before running commands.

### 1. Validate and publish the change

On the development machine, review the worktree and stage only the intended application and documentation files. Do not include local databases, `.env` files, generated bundles, or unrelated changes.

```bash
git status --short
git diff --check
git add <intended-files>
git diff --cached
git commit -m "Describe the application update"
git push origin <deployment-branch>
```

Do not copy the entire project directory to deploy a small change. It may contain local databases, environment files, generated assets, or unrelated work.

For the financial-statements update, the application files are `backend/app/models.py`, `backend/app/schemas.py`, `backend/app/routers/reports.py`, and `frontend/src/pages/Reports.tsx`. Include the README and license changes if publishing this documentation update too. Stage only the paths you intend to publish.

### 2. Back up production data

SSH to the server and switch to the application directory:

```bash
cd /var/www/food-court-counter
```

Back up the PostgreSQL database before changing the running application. The repository backup script writes a compressed dump under `/var/backups/food-court-counter` by default. Set `POSTGRES_DB` if the database has a non-default name:

```bash
sudo env POSTGRES_DB=food_court_db bash deploy/scripts/backup.sh
```

Also make sure the server's `backend/.env` and any uploaded documents in the configured upload directory are included in your normal secure backup. They contain deployment configuration and user data and must not be committed or copied into source control.

### 3. Upload the code delta

Choose **one** of the following methods.

#### Git checkout deployment

Use this method only if the application directory on the server is a Git checkout. Check the server worktree before updating and stop if it has local changes:

```bash
cd /var/www/food-court-counter
git status --short
git pull --ff-only origin <deployment-branch>
```

`--ff-only` prevents an unexpected merge. Some installations use an `rsync` deployment and do not contain `.git`; use the file-upload method below for those servers.

#### Upload only selected changed files

Use this method when the server does not have a Git checkout, or when you explicitly need to transfer a small, reviewed delta. Run the first commands on your development machine from the project root. The example includes the financial-statements code and the consolidated documentation; remove paths you do not intend to deploy, and add every other changed file required by your change.

```bash
# From the project root on your development machine.
tar -czf /tmp/fcc-delta.tar.gz \
  backend/app/models.py \
  backend/app/schemas.py \
  backend/app/routers/reports.py \
  frontend/src/pages/Reports.tsx \
  README.md \
  LICENSE.md

scp /tmp/fcc-delta.tar.gz <ssh-user>@<server-host>:/tmp/fcc-delta.tar.gz
```

SSH into the server, extract the archive into a staging directory, then install only the listed files into the live application. This does not delete other application files or replace `backend/.env`.

```bash
ssh <ssh-user>@<server-host>

mkdir -p "$HOME/fcc-delta"
tar -xzf /tmp/fcc-delta.tar.gz -C "$HOME/fcc-delta"

sudo install -D -o www-data -g www-data -m 0644 \
  "$HOME/fcc-delta/backend/app/models.py" \
  /var/www/food-court-counter/backend/app/models.py
sudo install -D -o www-data -g www-data -m 0644 \
  "$HOME/fcc-delta/backend/app/schemas.py" \
  /var/www/food-court-counter/backend/app/schemas.py
sudo install -D -o www-data -g www-data -m 0644 \
  "$HOME/fcc-delta/backend/app/routers/reports.py" \
  /var/www/food-court-counter/backend/app/routers/reports.py
sudo install -D -o www-data -g www-data -m 0644 \
  "$HOME/fcc-delta/frontend/src/pages/Reports.tsx" \
  /var/www/food-court-counter/frontend/src/pages/Reports.tsx
sudo install -D -o www-data -g www-data -m 0644 \
  "$HOME/fcc-delta/README.md" \
  /var/www/food-court-counter/README.md
sudo install -D -o www-data -g www-data -m 0644 \
  "$HOME/fcc-delta/LICENSE.md" \
  /var/www/food-court-counter/LICENSE.md
```

For every additional changed or newly added file, add it to the archive and install it to the matching path under `/var/www/food-court-counter`. For a deleted file, remove it from the server only after confirming the deletion is intended and included in the reviewed delta. If the web-service account or application path differs, use the ownership and paths configured for that server.

Manual file uploads do not update Git metadata. Do not run `git pull` in a manually copied, Git-managed application directory until its worktree and deployed revision have been reconciled.

### 4. Install changed dependencies and rebuild

If backend dependency files changed, update the existing virtual environment:

```bash
cd /var/www/food-court-counter/backend
.venv/bin/pip install -r requirements.txt
```

If frontend dependency files changed, install from the lockfile. Build the frontend for every deployment that includes frontend changes:

```bash
cd /var/www/food-court-counter/frontend
npm ci --no-audit --no-fund
npm run build
```

Keep the server's production environment configuration intact. Do not replace `backend/.env` with local development settings.

### 5. Restart and verify

Restart the API after backend changes. The API creates missing tables at startup, so the new balance-sheet snapshot table is created automatically on first startup with this feature. `create_all` does not alter existing tables; future schema changes that modify existing columns or constraints need a reviewed database migration and backup.

```bash
sudo systemctl restart food-court-api
sudo systemctl status food-court-api --no-pager
curl -fsS https://<your-domain>/api/health
```

If the server uses HTTP or a different health-check URL, adjust the `curl` address. Check backend logs if the service does not become active:

```bash
sudo journalctl -u food-court-api -n 100 --no-pager
```

For Apache configuration changes only, validate the configuration and reload Apache:

```bash
sudo apachectl configtest
sudo systemctl reload apache2
```

For Nginx installations, use `sudo nginx -t` followed by `sudo systemctl reload nginx` instead. A code-only deployment normally does not require changing or reloading the reverse proxy.

### Rollback

If the updated application fails its health check, inspect the service logs and restore the last known-good application commit using a new commit or a fast-forward to the approved rollback commit, then rebuild the frontend if needed and restart the service. Avoid `git reset --hard` on a production server. Keep the pre-deployment database backup until the updated service has been verified.

### Full provisioning versus delta updates

`deploy-to-existing-server.sh` and `deploy/scripts/deploy-ubuntu.sh` are provisioning scripts, not routine code-update commands. They install/configure system packages, web-server services, databases, or environment files. Do not re-run them for a normal code delta: review the script and your existing configuration first, and use the backup-first update procedure above.

## Database schema

The application initializes missing tables on API startup using SQLAlchemy `Base.metadata.create_all`. This is suitable for adding a new table to an existing database, such as the balance-sheet snapshots table. It does not apply changes to existing tables.

Alembic is present in the backend dependencies. For schema changes that require altering existing tables, create and review a migration, take a database backup, apply the migration before restarting the application, and verify the result. Do not treat `create_all` as a substitute for a migration.

## License

This project is released under the MIT License. See [LICENSE.md](./LICENSE.md) for the license and dependency-license notes.
