# Frontend deploy: inject config, sync, invalidate

A static frontend deploy is three steps in order: **inject** real infrastructure
values into the committed config, **sync** to S3, **invalidate** the CDN. Skipping
or reordering any of them ships a broken or stale site.

## Why inject at deploy time

The frontend can't hardcode the API URL, Cognito pool/client IDs, etc. — those are
Terraform outputs that differ per environment and aren't known until apply. So the
repo commits a `config.js` with **placeholders**, and the pipeline substitutes the
real values after `terraform apply`:

```js
// web/config.js (committed)
window.APP_CONFIG = {
  API_BASE_URL: "__API_BASE_URL__",
  COGNITO_REGION: "__COGNITO_REGION__",
  COGNITO_POOL_ID: "__COGNITO_POOL_ID__",
  COGNITO_CLIENT_ID: "__COGNITO_CLIENT_ID__",
};
```

Read the outputs and replace the placeholders:

```yaml
- name: Inject frontend config
  run: |
    API_URL=$(terraform -chdir=infra output -raw api_invoke_url)
    REGION=$(terraform -chdir=infra output -raw aws_region)
    POOL_ID=$(terraform -chdir=infra output -raw cognito_user_pool_id)
    CLIENT_ID=$(terraform -chdir=infra output -raw cognito_app_client_id)

    sed -i \
      -e "s|__API_BASE_URL__|${API_URL}|" \
      -e "s|__COGNITO_REGION__|${REGION}|" \
      -e "s|__COGNITO_POOL_ID__|${POOL_ID}|" \
      -e "s|__COGNITO_CLIENT_ID__|${CLIENT_ID}|" \
      web/config.js
```

`terraform output -raw` gives the bare value with no quotes/JSON wrapping — ideal
for substitution. Do this **after apply** so the outputs exist and are current.
Never commit the substituted file back; it's a build artifact.

## Sync to S3

```yaml
- name: Sync to S3
  run: |
    BUCKET=$(terraform -chdir=infra output -raw web_bucket_id)
    aws s3 sync web/ "s3://${BUCKET}/" --delete
```

- `--delete` removes objects no longer in `web/`, so stale files (a renamed page)
  don't linger.
- The bucket is private (CloudFront OAC reads it); the deploy role's S3 permissions
  cover the sync. No public-read needed.
- Consider excluding files that shouldn't ship (`--exclude "*.map"` etc.) if any.

## Invalidate CloudFront

S3 sync alone isn't visible until CloudFront's cache expires. Invalidate so users
get the new files immediately:

```yaml
- name: Invalidate CloudFront
  run: |
    DIST_ID=$(terraform -chdir=infra output -raw cloudfront_distribution_id)
    aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "/*"
```

`/*` invalidates everything — fine for a small static site on each deploy. For
large sites, invalidate only changed paths to stay under the free-invalidation
quota, but for a handful of files `/*` is simplest and cheap.

## Order matters

The sequence is strict: **apply → inject → sync → invalidate**. Inject needs the
post-apply outputs; sync needs the injected config; invalidate needs the new
objects already in S3. A common bug is invalidating before syncing (nothing new to
serve) or syncing before injecting (ships placeholders).
