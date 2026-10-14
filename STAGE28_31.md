# Etapa 28.31 — Regressão de substituição seguida por falha

## Escopo
Adicionado teste em `src/text_input.zig` para o processamento de um lote em que uma seleção é substituída com sucesso, mas a inserção Unicode seguinte falha por falta de capacidade. O teste exige que a edição anterior permaneça aplicada, que o evento que falhou não seja consumido, e que a retomada preserve o modificador Shift e a seleção subsequente.

## Contratos
- Nenhuma alteração de API ou de runtime.
- O evento com falha permanece fora do prefixo consumido.
- A aplicação decide explicitamente descartar o evento com falha antes da retomada.
- Sem novas alocações, buffers ou dependências.

## Validação
Teste adicionado, mas **não executado**: o executável Zig 0.17.0 não foi encontrado neste ambiente. Não há afirmação de compatibilidade, aprovação dos testes ou desempenho. O ZIP foi submetido à verificação de integridade.

## Próximo passo
Obter Zig 0.17.0, executar `zig build test -Doptimize=Debug`, `zig build test -Doptimize=ReleaseFast`, `zig build integration` e corrigir falhas reais antes de ampliar a API.
