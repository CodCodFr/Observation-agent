git add .\setup_agent.sh
git commit -m "update"
git push
docker buildx build -t ghcr.io/codcodfr/observation-agent:latest --push .