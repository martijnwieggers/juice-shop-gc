# Juice Shop GC — Deploymenthandleiding

Deze handleiding beschrijft hoe je de Graafschap College-versie van OWASP Juice Shop installeert en beheert op een server met Docker en Nginx Proxy Manager.

---

## Inhoudsopgave

1. [Vereisten](#vereisten)
2. [Eerste installatie](#eerste-installatie)
3. [Enkelvoudige instantie](#enkelvoudige-instantie)
4. [Meerdere sites per klas](#meerdere-sites-per-klas)
5. [Score-isolatie tussen omgevingen](#score-isolatie-tussen-omgevingen)
6. [Aanpassen van de configuratie](#aanpassen-van-de-configuratie)
7. [Beheer](#beheer)

---

## Vereisten

- Docker en Docker Compose geïnstalleerd
- Nginx Proxy Manager actief (verwacht op het `portainer_default`-netwerk)
- `git` en `jq` geïnstalleerd (`apt install git jq`)
- DNS-records voor de gewenste subdomeinen wijzen naar het server-IP

---

## Eerste installatie

```bash
git clone https://github.com/martijnwieggers/juice-shop-gc.git
cd juice-shop-gc
```

De image wordt lokaal gebouwd vanuit de meegeleverde `Dockerfile`. Er wordt niets van Docker Hub gepulld.

---

## Enkelvoudige instantie

Gebruik `docker-compose.yml` om één Juice Shop-container te starten.

**1. Pas de omgevingsvariabelen aan:**

Open `docker-compose.yml` en vul de gewenste waarden in. De meest relevante instellingen:

| Variabele | Omschrijving |
|---|---|
| `CONTINUE_CODE_SALT` | Sleutel voor score-export/-import (standaard challenges) |
| `CONTINUE_CODE_SALT_FINDIT` | Sleutel voor FindIt-challenges |
| `CONTINUE_CODE_SALT_FIXIT` | Sleutel voor FixIt-challenges |
| `NODE_ENV` | Welke configuratie wordt geladen (standaard: `graafschap-college`) |
| `PORT` | Poort waarop de app luistert (standaard: `3000`) |

**2. Bouwen en starten:**

```bash
docker compose build
docker compose up -d
```

**3. Stoppen:**

```bash
docker compose down
```

> **Let op:** Bij elke herstart wordt de database opnieuw aangemaakt. Voortgang van studenten gaat verloren tenzij je een volume koppelt aan `/juice-shop/data/`.

---

## Meerdere sites per klas

Het script `generate-compose.sh` genereert automatisch een `docker-compose-gc.yml` met één container per studentengroep en configureert optioneel Nginx Proxy Manager via de API.

### Stap 1 — Script uitvoeren

```bash
bash generate-compose.sh
```

Het script stelt de volgende vragen:

| Vraag | Toelichting |
|---|---|
| Aantal sites | Het aantal te genereren containers |
| NPM Docker-netwerk | Wordt automatisch gedetecteerd (standaard: `portainer_default`) |
| Initialen per site | Bijv. `mw` → container heet `juice-shop-mw`, subdomein wordt `js-mw.wieggers.eu` |
| NPM automatisch configureren? | `j` = proxy hosts + SSL-certificaten worden via de NPM API aangemaakt |
| NPM e-mailadres + wachtwoord | Inloggegevens van de NPM-beheerdersaccount |
| Let's Encrypt e-mailadres | Wordt gebruikt voor het aanvragen van SSL-certificaten |

### Stap 2 — Containers starten

```bash
docker compose -f docker-compose-gc.yml up -d
```

### Wat het script aanmaakt

- Per site een container met naam `juice-shop-<initialen>`
- Unieke, willekeurig gegenereerde salts per site (voorkomt score-uitwisseling)
- Containers op het NPM-netwerk (geen host-poorten nodig)

### NPM handmatig instellen (als je `n` koos)

Voeg per site een Proxy Host toe in Nginx Proxy Manager:

| Veld | Waarde |
|---|---|
| Domain Names | `js-<initialen>.wieggers.eu` |
| Forward Hostname/IP | `juice-shop-<initialen>` (containernaam) |
| Forward Port | `3000` |
| SSL | Request new certificate (Let's Encrypt) |

---

## Score-isolatie tussen omgevingen

Elke container gebruikt eigen **salts** voor het versleutelen van voortgangscodes. Een code geëxporteerd uit omgeving A werkt niet in omgeving B als de salts verschillen.

Het script genereert automatisch willekeurige salts per site. In de logging van elke container is te zien welke salt actief is:

```
info: Continue code export (standard) using salt: "a3f9..."
info: Continue code import (standard) using salt: "a3f9..."
```

Logs bekijken:

```bash
docker logs juice-shop-mw
```

---

## Aanpassen van de configuratie

Alle aanpassingen voor de Graafschap College-omgeving staan in:

```
config/graafschap-college.yml
```

Dit bestand is een volledige kopie van de standaardconfiguratie. Veelgebruikte instellingen:

| Instelling | Pad in YAML | Omschrijving |
|---|---|---|
| Applicatienaam | `application.name` | Naam in de header van de webshop |
| Thema | `application.theme` | Kleurschema (bijv. `bluegrey-lightgreen`) |
| Hinttonen | `challenges.showHints` | Hints zichtbaar voor studenten (`true`/`false`) |
| Notificaties | `challenges.showSolvedNotifications` | Melding bij opgelost challenge |
| Coding challenges | `challenges.codingChallengesEnabled` | `never`, `solved` of `always` |

Na een wijziging in de configuratie moet de container opnieuw worden gebouwd:

```bash
docker compose build
docker compose up -d
```

---

## Beheer

### Alle containers bekijken

```bash
docker ps
```

### Logs van een specifieke container

```bash
docker logs juice-shop-<initialen>
```

### Container herstarten

```bash
docker compose -f docker-compose-gc.yml restart juice-shop-<initialen>
```

### Alles stoppen en verwijderen

```bash
docker compose -f docker-compose-gc.yml down
```

### Image opnieuw bouwen (na een update)

```bash
git pull
docker compose -f docker-compose-gc.yml build --no-cache
docker compose -f docker-compose-gc.yml up -d
```
