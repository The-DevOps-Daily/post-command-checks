# post-command-checks

Scripts that record the real terminal output used in [DevOps Daily](https://devops-daily.com) posts.

Each folder has a `run.sh`. The `run` workflow (manual trigger) runs one folder on a fresh GitHub Actions runner and keeps the full log as an artifact, so every command and its output in a post can be traced back to a run.

| Folder | Post |
|---|---|
| [docker-compose-lifecycle](docker-compose-lifecycle) | [How to rebuild, restart and upgrade a Docker Compose container](https://devops-daily.com/posts/rebuild-docker-container-compose) |

## Run one yourself

```bash
cd docker-compose-lifecycle
bash run.sh
```

You need Docker with the Compose plugin and `curl`. The scripts create their own files in a temporary directory and clean up at the end.
