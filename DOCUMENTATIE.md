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
- `openssl` beschikbaar (standaard aanwezig op Linux)

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

De multi-site opzet bestaat uit twee stappen en twee scripts:

| Script | Doel |
|---|---|
| `generate-compose.sh` | Genereert `docker-compose-gc.yml` en `sites.csv` |
| `configure-npm.sh` | Configureert Nginx Proxy Manager via de API op basis van `sites.csv` |

Door de stappen te splitsen kun je de containers starten en DNS-records instellen voordat je SSL-certificaten aanvraagt.

---

### Stap 1 — Docker Compose genereren

```bash
bash generate-compose.sh
```

Het script stelt de volgende vragen:

| Vraag | Toelichting |
|---|---|
| Aantal sites | Het aantal te genereren containers |
| NPM Docker-netwerk | Wordt automatisch gedetecteerd (standaard: `portainer_default`) |
| Initialen per site | Bijv. `mw` → container heet `juice-shop-mw`, subdomein wordt `js-mw.wieggers.eu` |

Het script maakt aan:

- `docker-compose-gc.yml` — één service per site, met willekeurig gegenereerde salts
- `sites.csv` — overzicht van domeinen en containernamen (invoer voor stap 3)

---

### Stap 2 — Containers starten

```bash
docker compose -f docker-compose-gc.yml up -d
```

Wacht tot alle containers de status `Up` hebben:

```bash
docker ps
```

---

### Stap 3 — DNS-records instellen

Maak voor elk subdomein een A-record aan dat wijst naar het IP-adres van de server. Controleer de propagatie voordat je doorgaat:

```bash
nslookup js-<initialen>.wieggers.eu
```

---

### Stap 4 — NPM configureren en SSL aanvragen

> **Vereiste:** Stel het Let's Encrypt e-mailadres in via NPM → SSL Certificates → Add SSL Certificate → Let's Encrypt (of via Settings als jouw NPM-versie dat heeft). Het script gebruikt de globale instelling; als dit niet is ingevuld, mislukt de certificaataanvraag.

```bash
bash configure-npm.sh
```

Het script stelt de volgende vragen:

| Vraag | Toelichting |
|---|---|
| NPM e-mailadres | Inloggegevens van de NPM-beheerdersaccount |
| NPM wachtwoord | Inloggegevens van de NPM-beheerdersaccount |

Per site doet het script:

1. Proxy host aanmaken (of hergebruiken als die al bestaat)
2. Let's Encrypt-certificaat aanvragen via HTTP-01 challenge
3. SSL koppelen aan de proxy host

Als een site mislukt (bijv. DNS nog niet actief), wordt die overgeslagen. Je kunt het script daarna opnieuw draaien — al geconfigureerde sites worden herkend en overgeslagen.

---

### Wat er per site wordt aangemaakt

- Container met naam `juice-shop-<initialen>`, verbonden aan het NPM-netwerk
- Unieke, willekeurig gegenereerde salts (voorkomt score-uitwisseling tussen sites)
- Proxy host in NPM: `js-<initialen>.wieggers.eu` → `juice-shop-<initialen>:3000`
- Let's Encrypt-certificaat met automatische HTTPS-redirect

---

### NPM handmatig instellen (als alternatief voor `configure-npm.sh`)

Voeg per site een Proxy Host toe in de NPM-webinterface:

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
docker compose -f docker-compose-gc.yml build --no-cache
docker compose -f docker-compose-gc.yml up -d
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

### sites.csv opnieuw uitvoeren na DNS-wijzigingen

`configure-npm.sh` is idempotent: al geconfigureerde proxy hosts en certificaten worden herkend en niet opnieuw aangemaakt. Je kunt het script veilig meerdere keren draaien.
