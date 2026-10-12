# post-command-checks

Scripts that record the real terminal output used in [DevOps Daily](https://devops-daily.com) posts.

Each folder has a `run.sh`. The `run` workflow (manual trigger) runs one folder on a fresh GitHub Actions runner and keeps the full log as an artifact, so every command and its output in a post can be traced back to a run.

| Folder | Post |
|---|---|
| [docker-compose-lifecycle](docker-compose-lifecycle) | [How to rebuild, restart and upgrade a Docker Compose container](https://devops-daily.com/posts/rebuild-docker-container-compose) |

`docker-compose-lifecycle/run.sh` produced the post's terminal blocks ([run log](https://github.com/The-DevOps-Daily/post-command-checks/actions/runs/38251072361)). `build-recreate-check.sh` compares when `up -d --build` recreates the container on Compose 2.38.2 (bake and classic builder) and 5.6.0 ([run log](https://github.com/The-DevOps-Daily/post-command-checks/actions/runs/38250445430)).

## Run one yourself

```bash
cd docker-compose-lifecycle
bash run.sh
```

You need Docker with the Compose plugin and `curl`. The scripts create their own files in a temporary directory and clean up at the end. `run.sh` installs Compose 5.6.0 into `~/.docker/cli-plugins`, which replaces your user-level Compose plugin, so run it on a throwaway machine or CI runner.
