# Etapa 26.1 — Alinhamento no eixo transversal

Implementado `layout.Alignment` (`start`, `center`, `end`), `layout.Stack.nextAligned` e `Context.nextAlignedLayoutRect`. O alinhamento atua apenas no eixo transversal, sem alterar o avanço principal. Em regiões verticais alinha X; em regiões horizontais alinha Y. A dimensão explícita do item deve caber na área interna transversal; caso contrário retorna `InvalidSize` sem avançar o cursor. O cálculo preserva o contrato existente de `next` e não introduz alocações.

Arquivos alterados: `src/layout.zig`, `src/root.zig`; este relatório foi criado. Foram adicionados três testes (alinhamento vertical/horizontal, falhas atômicas e estado de frame).

**Limitação:** não há ainda distribuição proporcional/flex de espaço, nem alinhamento automático de conteúdo de texto. Não há Zig 0.17.0 disponível neste ambiente: compilação, testes e benchmarks não executados. Antes de integrar, executar `zig fmt --check build.zig src bench examples`, `zig build test`, `zig build test -Doptimize=ReleaseFast`, `zig build integration` e `zig build bench -Doptimize=ReleaseFast`.
