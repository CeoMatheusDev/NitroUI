# Etapa 28.39 — Teste offline do procedimento de validação

Sem Zig 0.17.0 disponível, a etapa verifica o próprio script de validação por meio de um executável `zig` simulado e isolado em diretório temporário.

## Arquivos
- `tools/test_validate_zig_017.sh`: novo teste do guard de versão, propagação de falha e ordem dos quatro comandos.
- Nenhuma modificação no runtime, nas APIs públicas, no build ou nas dependências.

## Execução
`sh tools/test_validate_zig_017.sh`

O teste **não** compila Zig nem executa testes do projeto; verifica somente a orquestração do script. O teste de ausência do compilador continua sendo coberto pela execução direta de `tools/validate_zig_017.sh` quando Zig não está no PATH.

## Pendências
Compilação real com Zig 0.17.0, testes Debug/ReleaseFast, integração headless, benchmarks e integração com engine real.
