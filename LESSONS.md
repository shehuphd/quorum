# Lessons

Things learned building and running Quorum that aren't obvious from the code.

## Cold starts on Azure Container Apps

The app runs on ACA with `minReplicas: 0`, so it's free between demos and cold-starts on the first request after a lull. The cold start pays for three things stacked: ACA scheduling and pulling the image, the BEAM/release booting, and the on-boot migration check. Ours measured ~28s from cold.

**Don't hold a replica warm to avoid it.** A KEDA cron rule (or `minReplicas: 1`) over demo hours can't fit the free tier. The memory grant binds first: 360,000 GiB-seconds/month is ~100 replica-hours at 1 GiB, and any daily window over demo hours (08:00–20:00 is ~360h, even weekdays 09:00–18:00 is ~200h) is several times over. Held time is billed at ACA's idle rate too, which may not draw from the grant at all. We tried the cron rule and reverted it.

**Warm it with a click instead.** [WARMUP.command](WARMUP.command) curls the live URL; double-click it 2–3 minutes before a demo. The wake keeps the app up through ACA's ~300s cooldown, so the demo starts warm, and the wake's active seconds are inside the free grant, so it's $0.

**Cut the cold start itself where that's free.** Migrations run inside the release's own boot now (`QUORUM_MIGRATE_ON_BOOT`, in `Quorum.Application.start/2`) rather than a separate `bin/migrate` node before it, so the BEAM boots once per container, not twice. The heartbeat (`Quorum.Heartbeat`) keeps Neon from suspending during a lull while the app is up; it doesn't hold the container up, so it stays free.

## Deploying to ACA: use the digest, not `:latest`

`az containerapp update --image ...:latest` when the app already points at `:latest` is a silent no-op: ACA sees the same reference, rolls no new revision, and keeps serving the old code with no error. Deploy by digest so every build is a new reference:

```bash
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' ghcr.io/shehuphd/quorum:latest)
az containerapp update --name quorum --resource-group quorum-demo --image "$DIGEST"
```

## Editing ACA scale rules via YAML

`rules: null` in an update YAML means "leave unchanged," not "clear the rules." To remove a scale rule, either set `rules` to the explicit list you want to keep, or use the CLI `--scale-rule-*` flags, which replace the whole rule set with the single rule you name. Secrets serialize name-only in the dumped YAML and keep their values on re-apply, so dumping the config and re-applying it is safe.

## A floor pin plus a cached Docker layer freezes the deployed version

The sidecar installs its Python deps in one layer: `COPY sidecar ./sidecar` then `pip3 install -r sidecar/requirements.txt`. That layer is keyed on the `sidecar/` tree, so while nothing under `sidecar/` changes, Docker reuses it. `requirements.txt` pins floors (`keycall>=1.12.0`, `rates>=1.0.1`), and a floor only sets the lowest allowed version, not the installed one. Put together: the image keeps whatever a floor resolved to when the layer first built, and new upstream releases don't reach it however many ship. `keycall` sat behind its floor this way until the floor was raised.

To move the deployed version, bump the floor in `requirements.txt`. The file changes, the layer rebuilds, and pip resolves the newest allowed. Don't trust the pin to tell you what shipped: read the version out of the built image, `docker run --rm --entrypoint python3 <image> -c "import importlib.metadata as m; print(m.version('keycall'))"`. The same caution applies to any dependency on a private API (the sidecar imports `keycall._registry`): test the exact imports against the new version before bumping, since a minor release can move a private module.
