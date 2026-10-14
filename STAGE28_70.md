# Etapa 28.70 — Matriz exaustiva de bytes iniciais UTF-8

## Escopo

Adicionado teste em `src/text.zig` para classificar os 256 valores possíveis do primeiro byte de uma sequência UTF-8. A classificação esperada é independente da implementação de `decodeOne`.

- ASCII: `0x00..0x7f` deve consumir um byte.
- Bytes não ASCII isolados: sempre inválidos.
- Com sufixo `0x80 0x80 0x80`, apenas `0xc2..0xdf` (2 bytes), `0xe1..0xef` (3 bytes) e `0xf1..0xf4` (4 bytes) devem ser aceitos.
- Demais bytes iniciais, incluindo overlong, continuation e valores acima de `0xf4`, devem ser rejeitados.

O teste não modifica o runtime, APIs públicas, alocações ou contratos. Versão permanece 0.2.0.

## Validação

Executar `sh tools/validate_zig_017.sh` com Zig 0.17.0. Sem compilador disponível no ambiente de preparação, não há comprovação de compilação nem execução de testes Zig. O autoteste Shell usa Zig simulado e não substitui essa validação.
