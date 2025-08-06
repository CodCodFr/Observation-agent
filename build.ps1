git add .
git commit -m "update"
git push
docker buildx build -t ghcr.io/codcodfr/observation-agent:latest --push .