# scripts2027

Scripts voor het beheren van Juice Shop-instanties per student. Elke site draait als een losse Docker-container achter Nginx Proxy Manager (NPM).

## Vereisten

- Docker + Docker Compose v2
- `jq` (`apt install jq`)
- `openssl`
- Nginx Proxy Manager bereikbaar op `http://127.0.0.1:81`

## Werkwijze

### Site toevoegen

```bash
bash scripts2027/add-site.sh [initialen]
```

Doet in één stap:
1. Genereert drie unieke salts en schrijft die met de sitegegevens naar `sites.csv`
2. Regenereert `docker-compose-gc.yml` vanuit `sites.csv`
3. Start **alleen** de nieuwe container (`docker compose up -d --no-deps <service>`)
4. Configureert optioneel NPM: proxy host + Let's Encrypt-certificaat + SSL

Bestaande containers worden niet herstart. Docker Compose vergelijkt de configuratie per service; omdat salts in `sites.csv` worden opgeslagen en nooit opnieuw gegenereerd, blijven bestaande service-definities identiek.

### Site verwijderen

```bash
bash scripts2027/remove-site.sh [initialen]
```

Doet in één stap:
1. Stopt en verwijdert de container
2. Verwijdert optioneel de NPM proxy host en het certificaat
3. Verwijdert de regel uit `sites.csv`
4. Regenereert `docker-compose-gc.yml`

### NPM configureren voor alle sites

```bash
bash scripts2027/configure-npm.sh
```

Configureert NPM voor alle sites in `sites.csv`. Idempotent: bestaande proxy hosts en certificaten worden overgeslagen. Handig als NPM opnieuw is opgezet of als `add-site.sh` zonder NPM-stap is uitgevoerd.

### Alle containers verwijderen

```bash
bash scripts2027/cleanup-containers.sh
bash scripts2027/cleanup-npm.sh     # verwijdert ook alle NPM-config
```

## Bestandsformaat sites.csv

`sites.csv` is de bron van waarheid voor alle sites. Het bestand wordt aangemaakt door `add-site.sh` en bijgehouden door `add-site.sh` en `remove-site.sh`.

```
domain,container,network,salt,salt_findit,salt_fixit
js-ab.wieggers.eu,juice-shop-ab,portainer_default,<hex>,<hex>,<hex>
js-cd.wieggers.eu,juice-shop-cd,portainer_default,<hex>,<hex>,<hex>
```

De drie salt-kolommen bepalen de Hashids-encryptie van continue-codes. Ze worden eenmalig aangemaakt bij `add-site.sh` en daarna nooit meer gewijzigd, zodat studenten hun voortgang niet kwijtraken bij een heropstart van de container of een regeneratie van de compose file.

## Overzicht scripts

| Script | Doel |
|---|---|
| `add-site.sh` | Voeg één site toe |
| `remove-site.sh` | Verwijder één site |
| `generate-compose.sh` | Regenereer `docker-compose-gc.yml` vanuit `sites.csv` |
| `configure-npm.sh` | Configureer NPM voor alle sites in `sites.csv` |
| `cleanup-npm.sh` | Verwijder NPM-config voor alle sites |
| `cleanup-containers.sh` | Stop en verwijder alle containers |
| `_npm-lib.sh` | Gedeelde NPM API-functies (intern gebruik) |
