# post-command-checks

Scripts that record the real terminal output used in [DevOps Daily](https://devops-daily.com) posts.

Each folder has a `run.sh`. The `run` workflow (manual trigger) runs one folder on a fresh GitHub Actions runner and keeps the full log as an artifact, so every command and its output in a post can be traced back to a run.

| Folder | Post |
|---|---|
| [docker-compose-lifecycle](docker-compose-lifecycle) | [How to rebuild, restart and upgrade a Docker Compose container](https://devops-daily.com/posts/rebuild-docker-container-compose) |
| [consolidation-batch-1](consolidation-batch-1) | Sections added when 25 short posts were merged into existing pages (Docker posts, Docker guide parts 3 and 6, Kubernetes guide parts 5 and 9, the stuck-pods post) |
| [consolidation-batch-2](consolidation-batch-2) | Sections added when 27 short posts were merged into existing pages (Docker posts and Docker guide part 3, the exec post, Kubernetes guide part 6, Terraform guide part 10, the local IP post) |

`docker-compose-lifecycle/run.sh` produced the post's terminal blocks ([log](docker-compose-lifecycle/logs/run-2026-10-12.log)). `build-recreate-check.sh` compares when `up -d --build` recreates the container on Compose 2.38.2 (bake and classic builder) and 5.6.0 ([log](docker-compose-lifecycle/logs/build-recreate-check-2026-10-12.log)).

`consolidation-batch-1` has four scripts: `docker.sh` (EXPOSE and -P, single-file mounts, exec in CMD, Compose, logs, prune, registries), `logs.sh` (docker logs after a truncated json-file log), `registry.sh` (push to a registry with a password) and `kind.sh` (a namespace stuck in Terminating, Service ports, a failing init container). Logs are in [consolidation-batch-1/logs](consolidation-batch-1/logs). The first `kind.sh` run hung on `kubectl delete namespace --force` until the job timed out; that log is kept too.

`consolidation-batch-2` has six scripts. `docker.sh` covers image contents without a shell, deleting every image, save and load, export and import, port ranges and `EXPOSE`, and the Python standard library interface listing. `docker-rerun.sh` gives a clean transcript for deleting every image. `docker-attach.sh` and `docker-attach-2.sh` check `docker attach` with and without `-it`. `kind.sh` decodes Secrets, and `terraform.sh` plans an AWS key pair and a Google Cloud VM with a public key from a file. Logs are in [consolidation-batch-2/logs](consolidation-batch-2/logs). In the first `docker.sh` run, the attach cases after the first non-TTY one had no container: killing `docker attach` had stopped it. `docker-attach.sh` hung on its last case, because `docker attach --sig-proxy=false` ignores SIGTERM, and the job was cancelled after 20 minutes; that log is kept too.

## Run one yourself

```bash
cd docker-compose-lifecycle
bash run.sh
```

You need Docker with the Compose plugin and `curl`. The scripts create their own files in a temporary directory and clean up at the end. `run.sh` installs Compose 5.6.0 into `~/.docker/cli-plugins`, which replaces your user-level Compose plugin, so run it on a throwaway machine or CI runner.
