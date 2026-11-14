# The image of the local CI runner (docs/ops/ci-runner.md): GitHub's own
# runner plus Node, the GitHub CLI and (optionally) the system packages
# Playwright's browsers need, so a job only downloads what changes (npm
# packages, browser builds: both cached in volumes).
#
# Keep the runner version recent: GitHub refuses runners that are too old.
# Dependabot (package-ecosystem: docker, directory: /docker/ci-runner) bumps it.
FROM ghcr.io/actions/actions-runner:2.338.0

# Empty = no Node (non-Node repo).
ARG NODE_MAJOR=
# Empty = no browser system packages (repo without Playwright).
ARG PLAYWRIGHT_VERSION=
ARG PLAYWRIGHT_BROWSERS="chromium"

USER root
RUN set -eu \
  && if [ -n "$NODE_MAJOR" ]; then \
       curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR}.x" | bash -; \
     fi \
  && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends git gh \
  && if [ -n "$NODE_MAJOR" ]; then apt-get install -y --no-install-recommends nodejs; fi \
  && if [ -n "$PLAYWRIGHT_VERSION" ]; then \
       npx --yes "playwright@${PLAYWRIGHT_VERSION}" install-deps $PLAYWRIGHT_BROWSERS; \
     fi \
  && rm -rf /var/lib/apt/lists/* /root/.npm

COPY --chmod=755 entrypoint.sh /usr/local/bin/ci-runner-entrypoint

USER runner
# Created here so the cache volumes mounted on them belong to `runner`.
RUN mkdir -p /home/runner/.npm /home/runner/.cache/ms-playwright
WORKDIR /home/runner
ENTRYPOINT ["ci-runner-entrypoint"]
