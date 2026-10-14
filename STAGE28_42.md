# Etapa 28.42 — Descoberta explícita de testes

## Alteração

`src/root.zig` inclui agora um bloco `test` que importa explicitamente os 13 módulos internos da NitroUI. O objetivo é tornar explícita a intenção de incluir os testes dos subsistemas ao executar `zig build test`, cujo módulo raiz é `src/root.zig`.

Não há alteração nas APIs públicas, alocações, renderização ou hot paths. A versão permanece 0.2.0.

## Verificação

Inspeção estática: todos os arquivos `.zig` em `src/` exceto `root.zig` estão representados no bloco de teste, sem duplicatas. O comando `zig` não está instalado neste ambiente; compilação, execução dos testes e benchmarks continuam pendentes. Não é possível confirmar descoberta efetiva dos testes sem o compilador.
