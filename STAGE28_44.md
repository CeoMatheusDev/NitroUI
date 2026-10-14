# Etapa 28.44 — CI e validador com sequência única

## Problema
O CI executava integração ReleaseFast, mas `tools/validate_zig_017.sh` não; as sequências local e CI podiam divergir.

## Mudança
O validador passa a executar cinco comandos, incluindo `zig build integration -Doptimize=ReleaseFast` antes do benchmark. O autoteste de falhas cobre o novo comando. O workflow CI usa o mesmo validador após a verificação de formatação, evitando duplicação da lista de builds.

## Contratos
Sem mudanças no runtime, API pública ou dependências. A execução para na primeira falha; o validador exige Zig 0.17.0.

## Limitação
O autoteste usa um Zig simulado. Sem compilador Zig 0.17.0 disponível, não se pode confirmar compilação, integração nem desempenho.
