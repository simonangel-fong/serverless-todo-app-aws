# Artifact build: packaging the Lambda

The packaging step must produce **exactly the zip the Terraform expects**. If the
Terraform builds the zip itself (via an `archive_file` data source over the source
dir), the pipeline may not need a packaging step at all — Terraform handles it on
apply. Know which model your config uses before adding steps.

## Two models

**A. Terraform packages it (`archive_file`).** The Terraform has:

```hcl
data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = "${path.module}/../lambda/src"
  output_path = "${path.module}/../lambda/build/api.zip"
}
```

Here the zip is built during `terraform plan/apply` from `lambda/src/`. The
pipeline just needs the source present (it's in the checkout) — **no separate
packaging step**. This is the simplest model and is preferred when the function has
no third-party dependencies (standard library + the boto3 the Lambda runtime
already provides).

**B. The pipeline packages it.** Needed when there are dependencies to vendor, or
the artifact is built/compiled. Then the pipeline builds the zip before Terraform
runs and the Terraform references a prebuilt file.

## Matching packaging to the current source layout

A frequent refactor bug: the packaging step predates a code reorganization. E.g.
the workflow still does:

```yaml
# STALE: zips a single file that no longer is the whole function
run: zip lambda.zip lambda/main.py
```

after the Lambda was split into a `lambda/src/` package. Or it builds a
dependencies **layer**:

```yaml
# STALE if the function no longer has third-party deps
run: pip install -r lambda/requirements.txt -t lambda/python && zip -r layer.zip lambda/python
```

When the function is pure stdlib + runtime-provided boto3, that layer is dead work
— drop it. Always reconcile packaging with (a) the current source tree and (b)
what the Terraform actually consumes.

## If you do vendor dependencies

Package for the Lambda runtime, not the runner's platform:

```bash
pip install -r lambda/requirements.txt \
  --target build/deps \
  --platform manylinux2014_x86_64 \
  --implementation cp \
  --only-binary=:all:
```

The `--platform`/`--only-binary` flags fetch Linux wheels so native extensions
match the Lambda environment (an x86_64 Amazon Linux) rather than the CI runner.
Skipping this is why "works locally, fails in Lambda" happens with compiled deps.

## Determinism

Prefer letting Terraform's `archive_file` + `source_code_hash` decide when to
redeploy — it hashes contents, so an unchanged function doesn't churn. If you build
the zip in CI, keep it reproducible (sorted files, no timestamps leaking in) so the
hash is stable across runs and Terraform doesn't see a spurious change every deploy.
