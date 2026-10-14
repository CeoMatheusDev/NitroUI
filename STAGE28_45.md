# NitroUI — Etapa 28.45

## Correção

A verificação de formatação (`zig fmt --check build.zig src bench examples`) existia apenas no workflow CI, não no validador local. A validação agora possui seis operações, iniciando por formatação, seguidas de testes Debug/ReleaseFast, integração Debug/ReleaseFast e benchmark ReleaseFast. O CI usa o mesmo script e não duplica a verificação de formatação.

## Contratos

- Zig 0.17.0 obrigatório; versão errada interrompe antes de qualquer operação.
- Qualquer falha (inclusive formatação) interrompe a sequência e propaga o código de saída.
- Sem alterações no runtime, API pública ou dependências.

## Validação

Testes Shell com Zig simulado verificam ordem, interrupção e códigos de saída. Esses testes **não** compilam o código Zig. Compilação, testes reais, integração e benchmark continuam pendentes se o compilador não estiver instalado.
