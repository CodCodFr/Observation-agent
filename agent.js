// agent.js
require('dotenv').config();

const express = require('express');
const { exec } = require('child_process');
const crypto = require('crypto');

// --- Configuration de l'Agent ---
const PORT = parseInt(process.env.PORT || '3000');
const API_SECRET = process.env.API_SECRET;

if (!API_SECRET) {
    console.error('Erreur: API_SECRET non définie. L\'agent ne peut pas démarrer.');
    process.exit(1);
}

const app = express();
app.use(express.json());

// --- Middleware d'Authentification ---
function authenticateRequest(req, res, next) {
    console.log(`[Agent] Requête entrante sur ${req.path}`); // Log pour chaque requête
    
    const authHeader = req.headers['authorization'];
    if (!authHeader) {
        console.warn(`[Agent] Tentative d'accès non autorisé: Authorization header manquant.`);
        return res.status(401).json({ error: 'Authorization header missing' });
    }

    const token = authHeader.split(' ')[1];
    const expectedToken = crypto.createHash('sha256').update(API_SECRET).digest('hex');

    console.log(`[Agent] Tentative d'authentification...`); // Log avant la vérification
    if (token === expectedToken) {
        console.log(`[Agent] Authentification réussie.`);
        next();
    } else {
        console.warn(`[Agent] Échec d'authentification: Jeton invalide.`);
        res.status(403).json({ error: 'Invalid authentication token' });
    }
}

app.use(authenticateRequest);

// --- Définition des Commandes Exécutables ---
const COMMAND_MAPPING = {
    'HOSTNAME': 'hostname',
    'MEMORY_TOTAL': "free -h | grep Mem | awk '{print $2}'",
    'DISK_USAGE': "df -h / | grep '/' | awk '{print $5}'",
    'DOCKER_CONTAINERS': "docker ps --format '{{.Names}}'",
};

// --- Route pour Exécuter les Commandes ---
app.post('/execute-command', (req, res) => {
    const { commandName } = req.body;
    
    console.log(`[Agent] Requête reçue pour exécuter la commande: ${commandName}`);

    if (!commandName || !COMMAND_MAPPING[commandName]) {
        console.error(`[Agent] Commande invalide ou non supportée: ${commandName}`);
        return res.status(400).json({ error: 'Invalid or unsupported commandName' });
    }

    const commandToExecute = COMMAND_MAPPING[commandName];
    console.log(`[Agent] Exécution de la commande shell: "${commandToExecute}"`);

    exec(commandToExecute, (error, stdout, stderr) => {
        if (error) {
            console.error(`[Agent] Erreur d'exécution de la commande '${commandName}': ${error.message}`);
            return res.status(500).json({ 
                error: `Failed to execute command: ${commandName}`, 
                details: error.message, 
                stderr: stderr 
            });
        }
        if (stderr) {
            console.warn(`[Agent] Commande '${commandName}' a produit un stderr: ${stderr}`);
        }

        console.log(`[Agent] Commande '${commandName}' exécutée avec succès.`);
        res.json({ 
            command: commandName, 
            result: stdout.trim() 
        });
    });
});

// --- Démarrage du Serveur HTTP (écouter sur localhost uniquement) ---
app.listen(PORT, '127.0.0.1', () => {
    console.log(`[Agent] Agent Node.js en écoute sur http://127.0.0.1:${PORT}`);
    console.log(`[Agent] API_SECRET chargée depuis .env`);
});