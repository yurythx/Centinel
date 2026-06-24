COMPOSE = docker compose

.PHONY: up down restart logs ps update backup

## Sobe todos os serviços em background
up:
	$(COMPOSE) up -d

## Derruba todos os serviços (preserva volumes)
down:
	$(COMPOSE) down

## Reinicia um serviço específico: make restart s=keycloak
restart:
	$(COMPOSE) restart $(s)

## Logs em tempo real (todos os serviços ou make logs s=keycloak)
logs:
	$(COMPOSE) logs -f $(s)

## Status dos containers
ps:
	$(COMPOSE) ps

## Atualiza imagens e recria containers afetados
update:
	$(COMPOSE) pull
	$(COMPOSE) up -d --remove-orphans

## Dump do Postgres com timestamp (requer o container postgres rodando)
backup:
	@mkdir -p ./backups
	docker exec postgres pg_dump -U $${KC_DB_USER} $${KC_DB_NAME} \
		| gzip > ./backups/postgres_$$(date +%Y%m%d_%H%M%S).sql.gz
	@echo "Backup salvo em ./backups/"
