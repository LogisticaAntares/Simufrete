-- =============================================================================
-- 00. EXTENSÕES
-- =============================================================================
-- pgcrypto: gen_random_uuid() usado como default de todas as PKs.
-- pg_trgm:  índices de busca por nome (autocomplete de cidade) mais rápidos
--           que ILIKE simples.
create extension if not exists pgcrypto with schema public;
create extension if not exists pg_trgm with schema public;
