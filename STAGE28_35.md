# Etapa 28.35 — Âncora inválida durante navegação Shift+Home

## Escopo

Adicionado um teste de regressão para a ponte `text_input.applyTracked` quando
uma aplicação corrompe a âncora externa do editor e envia Shift seguido de Home.
O teste exige rejeição por `error.InvalidCursor`, contabilização exclusiva do
prefixo consumido (Shift), preservação do texto, cursor e âncora, e não execução
da inserção subsequente. Nenhuma API pública, implementação de runtime, versão
ou dependência foi alterada.

## Arquivos

- `src/text_input.zig`: um teste adicional.
- `STAGE28_35.md`: este relatório.

## Validação

- Inspeção estática do caso e integridade do ZIP: realizadas.
- Zig 0.17.0, testes Debug/ReleaseFast, integração e benchmarks: **não executados**
  porque o compilador não está disponível neste ambiente.
- O teste descreve um resultado esperado, não um resultado observado.

## Riscos

A validação acumulada com Zig 0.17.0 permanece bloqueadora para a prontidão
profissional. O armazenamento é de propriedade da aplicação e deve respeitar
os invariantes de UTF-8 e de posições de cursor/âncora.
