#!/bin/bash

# Configuration
DOCKER_IMAGE_NAME="ghcr.io/gaetanse/observation-agent-image:latest"
SERVICE_NAME="observation-agent"

# Redirection de la sortie vers un fichier de log
LOG_FILE="/var/log/agent-update.log"
exec >> "${LOG_FILE}" 2>&1
echo "--- Début de la mise à jour de l'agent : $(date) ---"

# Pull de la dernière image Docker
echo "Vérification et pull de la dernière image..."
docker pull "$DOCKER_IMAGE_NAME" || { echo "Échec du pull de l'image. Fin du script." && exit 1; }

# Récupération de l'ID de l'image locale actuelle
CURRENT_IMAGE_ID=$(docker service inspect "$SERVICE_NAME" --format '{{.Spec.TaskTemplate.ContainerSpec.Image}}' | cut -d'@' -f2)

# Récupération de l'ID de la nouvelle image
LATEST_IMAGE_ID=$(docker image inspect "$DOCKER_IMAGE_NAME" --format '{{.RepoDigests}}' | cut -d'@' -f2 | sed 's/\[//;s/\]//')

# Comparaison des IDs pour éviter les mises à jour inutiles
if [ "$CURRENT_IMAGE_ID" != "$LATEST_IMAGE_ID" ]; then
    echo "Nouvelle version de l'image détectée. Mise à jour du service..."
    docker service update --image "$DOCKER_IMAGE_NAME" "$SERVICE_NAME"
    echo "Service mis à jour avec succès."
else
    echo "Aucune nouvelle version de l'image. Le service est à jour."
fi

echo "--- Fin de la mise à jour : $(date) ---"