# Etapa 24.16 — Precisão de erros de configuração

Versão mantida: 0.1.0. 1 variante de erro adicionada (aditiva); 7 linhas de
produção; 1 teste novo (total 81).

## Problema

`widgetState()` e as 6 funções `reserve*` retornavam `error.OutOfCapacity`
quando o armazenamento sequer havia sido anexado, confundindo "não
configurado" com "cheio". Um integrador que esquecesse `setStateStorage()` ou
`setBuffers()` receberia um diagnóstico que sugere aumentar capacidade
inexistente.

## Contrato

- Novo `Error.MissingStorage`: armazenamento proprietário obrigatório nunca
  anexado. Distinto de `OutOfCapacity` (anexado, porém cheio), que continua
  vindo da arena/tabela.
- Mudança anterior ao primeiro release, sem consumidores existentes;
  compatível com chamadores baseados em `try`. Documentada aqui em vez de
  silenciosa.

## Correção (`src/root.zig`)

- `widgetState()` sem tabela → `MissingStorage` (tabela cheia segue
  `OutOfCapacity` da tabela).
- `reserveScratch/Render/Persistent` e variantes `Aligned` sem arena →
  `MissingStorage` (arena cheia segue `OutOfCapacity` da arena).

## Teste

`stage24_16 unconfigured storage reports MissingStorage, full reports
OutOfCapacity`: afirma `MissingStorage` nos 7 caminhos sem configuração e
`OutOfCapacity` nos mesmos caminhos configurados-porém-cheios.

## Validação executada (Zig 0.17.0)

```sh
zig fmt --check build.zig src bench            # limpo
zig build test --summary all                   # 81/81 (Debug)
zig build test -Doptimize=ReleaseFast --summary all  # 81/81
zig test src/root.zig                          # 81/81
zig build bench -Doptimize=ReleaseFast         # 12 linhas, medians estáveis
```
