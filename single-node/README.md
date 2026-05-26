# Deploy Wazuh Docker in single node configuration

This deployment is defined in the `docker-compose.yml` file with one Wazuh manager containers, one Wazuh indexer containers, and one Wazuh dashboard container. It can be deployed by following these steps: 

1) Increase max_map_count on your host (Linux). This command must be run with root permissions:
```
$ sysctl -w vm.max_map_count=262144
```
2) Run the certificate creation script:
```
$ docker compose -f generate-indexer-certs.yml run --rm generator
```
3) Create `.env` from template and set secret values:
```
$ cp .env.example .env
```
4) Create local dashboard credentials file (kept out of Git):
```
$ cp config/wazuh_dashboard/wazuh.yml config/wazuh_dashboard/wazuh.local.yml
# then edit password in wazuh.local.yml to match API_PASSWORD
```
4) Start the environment with docker compose:

- In the foregroud:
```
$ docker compose up
```
- In the background:
```
$ docker compose up -d
```

The environment takes about 1 minute to get up (depending on your Docker host) for the first time since Wazuh Indexer must be started for the first time and the indexes and index patterns must be generated.

## GitHub publish safety

- Never commit `.env`.
- Never commit `config/wazuh_dashboard/wazuh.local.yml`.
- Never commit `config/wazuh_indexer_ssl_certs/` (contains private keys/certs).

## Defense regression test

Run a full end-to-end validation (services, ingest, custom rule trigger, active-response, and iptables DROP):

```bash
chmod +x scripts/defense_regression.sh
./scripts/defense_regression.sh
```

Expected result: all checks show `[PASS]` and script exits `0`.
