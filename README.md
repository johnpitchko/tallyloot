# Tallyloot

A self-hosted retirement planner for Canadian households.

Enter your accounts, pensions, and government benefits, and Tallyloot projects your savings and retirement income year by year. It handles RRSPs, TFSAs, LIRAs, defined-benefit pensions, CPP and OAS, and an age-based investment glidepath.

Each install serves one household and has no login. On the first visit Tallyloot creates a sample household so the dashboard shows a real projection; replace the sample numbers with your own in the panel on the left.

Tallyloot is not financial advice.

## Running with Docker

```bash
docker run -d -p 3000:80 -v tallyloot:/rails/storage --name tallyloot ghcr.io/johnpitchko/tallyloot
```

Then open http://localhost:3000. Your data lives in the `tallyloot` volume. Images are built for Intel/AMD and ARM (Apple Silicon, Raspberry Pi).

To upgrade, pull the new image and recreate the container; your data stays in the volume:

```bash
docker pull ghcr.io/johnpitchko/tallyloot
docker rm -f tallyloot
docker run -d -p 3000:80 -v tallyloot:/rails/storage --name tallyloot ghcr.io/johnpitchko/tallyloot
```

To build the image yourself instead, run `docker build -t tallyloot .` in a clone of this repo.

Optional settings:

- `TALLYLOOT_ALLOWED_HOSTS` — Tallyloot has no login, so to stop other websites from reaching it through your browser (DNS rebinding), list the hostnames you use, e.g. `localhost,tallyloot.lan`. When unset, any hostname works.
- `TALLYLOOT_SSL=true` — set this when Tallyloot sits behind a reverse proxy that serves HTTPS.

## Development

Requires Ruby (see `.ruby-version`).

```bash
bin/setup     # install gems, prepare the database
bin/dev       # start the app on http://localhost:3000
bin/rails test
```

## Releasing

Push a version tag (e.g. `git tag v0.1.0 && git push origin v0.1.0`) and the Docker image workflow publishes `ghcr.io/johnpitchko/tallyloot` with that version and `latest`.

## License

[MIT](LICENSE)
